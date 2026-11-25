# =============================================================================
# Collect-VMFleetResults.ps1 - Azure Local Load Tools
# =============================================================================
# Reads the DiskSpd XML results the fleet VMs left in the Collect volume's result
# folder (the files of the sweep tagged with -RunId), reduces them per VM on the
# first node (one-shot scheduled task) and writes <RunId>-aggregate.json and
# <RunId>-per-vm.json. Phase 7 of the VMFleet pipeline. NOT PROVEN ON A LIVE CLUSTER.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'SolutionConfigPath keeps the common phase-script parameter set; results collection does not read the solution config.')]
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

    # The run id the test was started with. Without it the sweep tag of the last test on the Collect volume is used.
    [Parameter()]
    [string]$RunId,

    [Parameter()]
    [hashtable]$TestMetadata,

    [Parameter()]
    [int]$TimeoutMinutes = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
. (Join-Path $PSScriptRoot 'VMFleet-Common.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$null = Start-LogSession -Component 'VMFleet-Collect' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet results collection' -Severity Information

    $runIdWasGiven = [bool]$RunId
    if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

    if (-not $OutputPath) {
        $OutputPath = Join-Path $ProjectRoot "reports\$RunId"
    }
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    if (-not $ClusterConfigPath) { $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot }
    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath

    $Credential = Get-VMFleetCredentialOrExit -Credential $Credential -ProjectRoot $ProjectRoot

    Write-Log -Message 'Retrieving DiskSpd results from the Collect volume (node task)...' -Severity Information
    $tag = if ($runIdWasGiven) { ConvertTo-VMFleetSafeName -Name $RunId -MaxLength 24 } else { '' }
    $nodeResult = Invoke-VMFleetNodeTask -ComputerName $cluster.PrimaryNode -Credential $Credential -Step 'Collect' -RunId $RunId `
        -CollectPath $cluster.CollectPath -TimeoutSeconds ($TimeoutMinutes * 60) `
        -Arguments @{ Tag = $tag; CollectPath = $cluster.CollectPath }

    $rawResults = @(foreach ($vm in @($nodeResult.Output.VMs)) {
            $readBytes = [double]$vm.ReadBytesPerSecond
            $writeBytes = [double]$vm.WriteBytesPerSecond
            $readIops = [double]$vm.ReadIOPS
            $writeIops = [double]$vm.WriteIOPS
            $totalIops = $readIops + $writeIops
            [ordered]@{
                VMName              = [string]$vm.VMName
                ReadIOPS            = [math]::Round($readIops, 2)
                WriteIOPS           = [math]::Round($writeIops, 2)
                TotalIOPS           = [math]::Round($totalIops, 2)
                ReadThroughputMBps  = [math]::Round($readBytes / 1MB, 2)
                WriteThroughputMBps = [math]::Round($writeBytes / 1MB, 2)
                ReadLatencyMs       = [math]::Round([double]$vm.ReadLatencyMs, 3)
                WriteLatencyMs      = [math]::Round([double]$vm.WriteLatencyMs, 3)
                # I/O-weighted average of the read and write latency of this VM
                AvgLatencyMs        = $(if ($totalIops -gt 0) { [math]::Round((([double]$vm.ReadLatencyMs * $readIops) + ([double]$vm.WriteLatencyMs * $writeIops)) / $totalIops, 3) } else { 0 })
            }
        })
    if ($rawResults.Count -eq 0) { throw 'The node returned no per-VM results.' }

    Write-Log -Message "Collected results from $($rawResults.Count) VMs" -Severity Information

    # Weighted averages: latency is weighted by the I/O count it was measured over.
    $sumReadIops = ($rawResults | ForEach-Object { $_.ReadIOPS } | Measure-Object -Sum).Sum
    $sumWriteIops = ($rawResults | ForEach-Object { $_.WriteIOPS } | Measure-Object -Sum).Sum
    $sumTotalIops = ($rawResults | ForEach-Object { $_.TotalIOPS } | Measure-Object -Sum).Sum
    $readWeighted = ($rawResults | ForEach-Object { $_.ReadLatencyMs * $_.ReadIOPS } | Measure-Object -Sum).Sum
    $writeWeighted = ($rawResults | ForEach-Object { $_.WriteLatencyMs * $_.WriteIOPS } | Measure-Object -Sum).Sum
    $readMbps = ($rawResults | ForEach-Object { $_.ReadThroughputMBps } | Measure-Object -Sum).Sum
    $writeMbps = ($rawResults | ForEach-Object { $_.WriteThroughputMBps } | Measure-Object -Sum).Sum

    $aggregate = [ordered]@{
        run_id                      = $RunId
        timestamp                   = Get-Timestamp
        cluster_name                = $cluster.ClusterName
        vm_count                    = $rawResults.Count
        profile_name                = $(if ($TestMetadata -and $TestMetadata.ContainsKey('ProfileName')) { $TestMetadata['ProfileName'] } else { 'unknown' })
        total_read_iops             = [math]::Round($sumReadIops, 2)
        total_write_iops            = [math]::Round($sumWriteIops, 2)
        total_iops                  = [math]::Round($sumTotalIops, 2)
        avg_read_latency_ms         = $(if ($sumReadIops -gt 0) { [math]::Round($readWeighted / $sumReadIops, 3) } else { 0 })
        avg_write_latency_ms        = $(if ($sumWriteIops -gt 0) { [math]::Round($writeWeighted / $sumWriteIops, 3) } else { 0 })
        avg_latency_ms              = $(if ($sumTotalIops -gt 0) { [math]::Round(($readWeighted + $writeWeighted) / $sumTotalIops, 3) } else { 0 })
        total_read_throughput_mbps  = [math]::Round($readMbps, 2)
        total_write_throughput_mbps = [math]::Round($writeMbps, 2)
        total_throughput_mbps       = [math]::Round($readMbps + $writeMbps, 2)
    }

    if ($TestMetadata) {
        # The task handle is runtime state, not a test parameter.
        $params = @{}
        foreach ($key in $TestMetadata.Keys) { if ($key -ne 'TaskHandle') { $params[$key] = $TestMetadata[$key] } }
        $aggregate['test_parameters'] = $params
    }

    # Write results
    $aggregateFile = Join-Path $OutputPath "$RunId-aggregate.json"
    $aggregate | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $aggregateFile -Encoding UTF8
    Write-Log -Message "Aggregate results: $aggregateFile" -Severity Information

    $perVmFile = Join-Path $OutputPath "$RunId-per-vm.json"
    $rawResults | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $perVmFile -Encoding UTF8
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
} catch {
    Write-Log -Message "Collection failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
} finally {
    Stop-LogSession
}
