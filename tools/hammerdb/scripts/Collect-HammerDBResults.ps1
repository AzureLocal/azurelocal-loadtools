# =============================================================================
# Collect-HammerDBResults.ps1 - Azure Local Load Tools
# =============================================================================
# Retrieves HammerDB run logs from the target node, parses NOPM/TPM metrics,
# and writes normalized aggregate results to the standard output schema.
# Phase 3 of the HammerDB pipeline.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$SolutionConfigPath,

    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$OutputPath,

    [Parameter(Mandatory)]
    [string]$RunId,

    [Parameter()]
    [hashtable]$TestMetadata
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'HammerDB-Collect' -LogRootPath (Join-Path $ProjectRoot 'logs\hammerdb')

# Parses NOPM and TPM values from hammerdbcli output log
function Get-HammerDBMetrics {
    [CmdletBinding()]
    param([string]$LogContent)

    $nopmValues = [System.Collections.Generic.List[int]]::new()
    $tpmValues  = [System.Collections.Generic.List[int]]::new()

    foreach ($line in ($LogContent -split "`n")) {
        # Typical output: "TEST RESULT : System achieved 12345 NOPM from 23456 PostgreSQL TPM"
        if ($line -match 'System achieved (\d+) NOPM from (\d+)') {
            $nopmValues.Add([int]$Matches[1])
            $tpmValues.Add([int]$Matches[2])
        }
        # Virtual user result lines: "VUSER2:TEST RESULT : System achieved ..."
        elseif ($line -match 'achieved (\d+) NOPM') {
            $nopmValues.Add([int]$Matches[1])
        }
    }

    return @{
        NopmValues = $nopmValues
        TpmValues  = $tpmValues
        PeakNopm   = if ($nopmValues.Count -gt 0) { ($nopmValues | Measure-Object -Maximum).Maximum } else { 0 }
        PeakTpm    = if ($tpmValues.Count -gt 0)  { ($tpmValues  | Measure-Object -Maximum).Maximum } else { 0 }
        AvgNopm    = if ($nopmValues.Count -gt 0) { [math]::Round(($nopmValues | Measure-Object -Average).Average, 0) } else { 0 }
        AvgTpm     = if ($tpmValues.Count -gt 0)  { [math]::Round(($tpmValues  | Measure-Object -Average).Average, 0) } else { 0 }
        Samples    = $nopmValues.Count
    }
}

try {
    Write-Log -Message 'Starting HammerDB results collection' -Severity Information

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\hammerdb\config\hammerdb.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    if (-not $OutputPath) {
        $OutputPath = Join-Path $ProjectRoot "logs\hammerdb\$RunId"
    }
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    $primaryNode = $nodes[0]

    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    $remoteResultsDir = "C:\\hammerdb-results\\$RunId"

    # Retrieve log from remote node
    Write-Log -Message "Retrieving HammerDB logs from $primaryNode..." -Severity Information

    $logContent = Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
        param($ResultsDir)
        $logFile = Join-Path $ResultsDir 'hammerdb-run.log'
        if (Test-Path $logFile) {
            return Get-Content -Path $logFile -Raw
        }
        throw "HammerDB log not found: $logFile"
    } -ArgumentList @($remoteResultsDir)

    # Save raw log locally
    $rawLogFile = Join-Path $OutputPath "$RunId-hammerdb.log"
    $logContent | Set-Content -Path $rawLogFile -Encoding UTF8
    Write-Log -Message "Raw log saved: $rawLogFile" -Severity Information

    # Parse metrics
    $metrics = Get-HammerDBMetrics -LogContent $logContent

    Write-Log -Message "Parsed $($metrics.Samples) result sample(s) from log" -Severity Information

    if ($metrics.Samples -eq 0) {
        Write-Log -Message 'WARNING: No NOPM/TPM results found in log. Test may not have completed successfully.' -Severity Warning
    }

    # Build normalized aggregate
    $aggregate = @{
        run_id          = $RunId
        timestamp       = Get-Timestamp
        cluster_name    = $clusterConfig.cluster.name
        primary_node    = $primaryNode
        profile_name    = if ($TestMetadata) { $TestMetadata.Parameters.ProfileName } else { 'unknown' }
        benchmark_type  = if ($TestMetadata) { $TestMetadata.Parameters.BenchmarkType } else { 'tpcc' }
        db_type         = if ($TestMetadata) { $TestMetadata.Parameters.DbType } else { $solutionConfig.hammerdb_db_type }
        warehouse_count = if ($TestMetadata) { $TestMetadata.Parameters.WarehouseCount } else { $solutionConfig.hammerdb_warehouse_count }
        virtual_users   = if ($TestMetadata) { $TestMetadata.Parameters.VirtualUsers } else { $solutionConfig.hammerdb_virtual_users }
        peak_nopm       = $metrics.PeakNopm
        avg_nopm        = $metrics.AvgNopm
        peak_tpm        = $metrics.PeakTpm
        avg_tpm         = $metrics.AvgTpm
        result_samples  = $metrics.Samples
    }

    if ($TestMetadata) {
        $aggregate['test_parameters'] = $TestMetadata.Parameters
    }

    # Write output files
    $aggregateFile = Join-Path $OutputPath "$RunId-aggregate.json"
    $aggregate | ConvertTo-Json -Depth 5 | Set-Content -Path $aggregateFile -Encoding UTF8
    Write-Log -Message "Aggregate results written: $aggregateFile" -Severity Information

    # Print summary
    Write-Host "`n===== HammerDB Results Summary =====" -ForegroundColor Cyan
    Write-Host "  Run ID:         $RunId"
    Write-Host "  Benchmark:      $($aggregate.benchmark_type.ToUpper())"
    Write-Host "  DB Type:        $($aggregate.db_type)"
    Write-Host "  Warehouses:     $($aggregate.warehouse_count)"
    Write-Host "  Virtual Users:  $($aggregate.virtual_users)"
    Write-Host "  Peak NOPM:      $($aggregate.peak_nopm)"
    Write-Host "  Avg NOPM:       $($aggregate.avg_nopm)"
    Write-Host "  Peak TPM:       $($aggregate.peak_tpm)"
    Write-Host "  Avg TPM:        $($aggregate.avg_tpm)"
    Write-Host "====================================" -ForegroundColor Cyan

    # Clean up remote results
    if ($PSCmdlet.ShouldProcess($primaryNode, 'Remove remote HammerDB result files')) {
        Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            param($Dir)
            if (Test-Path $Dir) { Remove-Item -Path $Dir -Recurse -Force }
        } -ArgumentList @($remoteResultsDir)
    }

    Write-Log -Message 'HammerDB results collection completed' -Severity Information

    return @{
        RunId      = $RunId
        OutputPath = $OutputPath
        Aggregate  = $aggregate
    }
}
catch {
    Write-Log -Message "Collection failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
