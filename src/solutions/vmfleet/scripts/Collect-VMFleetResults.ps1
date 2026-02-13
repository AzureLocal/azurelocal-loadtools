# =============================================================================
# Collect-VMFleetResults.ps1 - Azure Local Load Tools
# =============================================================================
# Collects DiskSpd results from fleet VMs and generates structured output.
# Phase 5 of the VMFleet pipeline.
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

    [Parameter()]
    [string]$RunId,

    [Parameter()]
    [hashtable]$TestMetadata
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'VMFleet-Collect' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet results collection' -Severity Information

    if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

    if (-not $OutputPath) {
        $OutputPath = Join-Path $ProjectRoot "reports\$RunId"
    }
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\example-cluster.yml'
    }

    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml
    $primaryNode = ($clusterConfig.nodes | ForEach-Object { $_.name })[0]

    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    # Collect results from VMFleet
    Write-Log -Message 'Retrieving results from fleet VMs...' -Severity Information

    $rawResults = Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
        Import-Module VMFleet -ErrorAction Stop

        # Get fleet performance data
        $data = Get-FleetDataXml

        # Parse fleet results
        $results = @()
        foreach ($vm in $data) {
            $results += @{
                VMName           = $vm.VMName
                ReadIOPS         = $vm.ReadIOPS
                WriteIOPS        = $vm.WriteIOPS
                TotalIOPS        = $vm.ReadIOPS + $vm.WriteIOPS
                ReadThroughputMBps  = [math]::Round($vm.ReadBytesPerSecond / 1MB, 2)
                WriteThroughputMBps = [math]::Round($vm.WriteBytesPerSecond / 1MB, 2)
                ReadLatencyMs    = [math]::Round($vm.ReadLatencyMs, 3)
                WriteLatencyMs   = [math]::Round($vm.WriteLatencyMs, 3)
                AvgLatencyMs     = [math]::Round(($vm.ReadLatencyMs + $vm.WriteLatencyMs) / 2, 3)
            }
        }

        return $results
    }

    Write-Log -Message "Collected results from $($rawResults.Count) VMs" -Severity Information

    # Aggregate results
    $aggregate = @{
        run_id            = $RunId
        timestamp         = Get-Timestamp
        cluster_name      = $clusterConfig.cluster.name
        vm_count          = $rawResults.Count
        profile_name      = if ($TestMetadata) { $TestMetadata.ProfileName } else { 'unknown' }
        total_read_iops   = ($rawResults | Measure-Object -Property ReadIOPS -Sum).Sum
        total_write_iops  = ($rawResults | Measure-Object -Property WriteIOPS -Sum).Sum
        total_iops        = ($rawResults | Measure-Object -Property TotalIOPS -Sum).Sum
        avg_read_latency_ms  = [math]::Round(($rawResults | Measure-Object -Property ReadLatencyMs -Average).Average, 3)
        avg_write_latency_ms = [math]::Round(($rawResults | Measure-Object -Property WriteLatencyMs -Average).Average, 3)
        avg_latency_ms       = [math]::Round(($rawResults | Measure-Object -Property AvgLatencyMs -Average).Average, 3)
        total_read_throughput_mbps  = [math]::Round(($rawResults | Measure-Object -Property ReadThroughputMBps -Sum).Sum, 2)
        total_write_throughput_mbps = [math]::Round(($rawResults | Measure-Object -Property WriteThroughputMBps -Sum).Sum, 2)
    }

    if ($TestMetadata) {
        $aggregate['test_parameters'] = $TestMetadata
    }

    # Write results
    $aggregateFile = Join-Path $OutputPath "$RunId-aggregate.json"
    $aggregate | ConvertTo-Json -Depth 5 | Set-Content -Path $aggregateFile -Encoding UTF8
    Write-Log -Message "Aggregate results: $aggregateFile" -Severity Information

    $perVmFile = Join-Path $OutputPath "$RunId-per-vm.json"
    $rawResults | ConvertTo-Json -Depth 5 | Set-Content -Path $perVmFile -Encoding UTF8
    Write-Log -Message "Per-VM results: $perVmFile" -Severity Information

    # Print summary
    Write-Host "`n===== VMFleet Results Summary =====" -ForegroundColor Cyan
    Write-Host "  Run ID:         $RunId"
    Write-Host "  VMs:            $($rawResults.Count)"
    Write-Host "  Total IOPS:     $($aggregate.total_iops)"
    Write-Host "  Read IOPS:      $($aggregate.total_read_iops)"
    Write-Host "  Write IOPS:     $($aggregate.total_write_iops)"
    Write-Host "  Avg Latency:    $($aggregate.avg_latency_ms) ms"
    Write-Host "  Read Throughput: $($aggregate.total_read_throughput_mbps) MB/s"
    Write-Host "  Write Throughput: $($aggregate.total_write_throughput_mbps) MB/s"
    Write-Host "===================================" -ForegroundColor Cyan

    Write-Log -Message 'Results collection completed' -Severity Information

    return @{
        RunId       = $RunId
        OutputPath  = $OutputPath
        Aggregate   = $aggregate
        VMResults   = $rawResults
    }
}
catch {
    Write-Log -Message "Collection failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
