# =============================================================================
# Watch-VMFleetMonitor.ps1 - Azure Local Load Tools
# =============================================================================
# Real-time monitoring dashboard for a running VMFleet workload: the CSV file system
# counters of every node (IOPS, throughput, latency), summed over the cluster.
# Run it in a second window while Start-VMFleetTest.ps1 is running. NOT PROVEN ON A
# LIVE CLUSTER. (VMFleet 2.1 has no cmdlet that returns live data; its own live view,
# Watch-FleetCluster, is interactive and must run on a node.)
# =============================================================================

#Requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [int]$RefreshIntervalSeconds = 5,

    [Parameter()]
    [int]$DurationMinutes = 0,

    [Parameter()]
    [switch]$LogToFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
. (Join-Path $PSScriptRoot 'VMFleet-Common.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'

if ($LogToFile) {
    Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force
    $null = Start-LogSession -Component 'VMFleet-Watch' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')
}

try {
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot
    }

    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath
    $nodes = $cluster.Nodes

    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        # No prompt: -Credential, CLUSTER_ADMIN_USERNAME/CLUSTER_ADMIN_PASSWORD or the Key Vault mapping; otherwise stop (exit 2).
        try {
            $Credential = Get-ManagedCredential -Name 'cluster_admin' -ProjectRoot $ProjectRoot
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorAction Continue
            exit 2
        }
    }

    Write-Host "VMFleet Monitor - Refreshing every ${RefreshIntervalSeconds}s | Press Ctrl+C to stop" -ForegroundColor Cyan
    Write-Host "Cluster: $($cluster.ClusterName) | Nodes: $($nodes -join ', ')" -ForegroundColor Gray
    Write-Host ''

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $iteration = 0

    while ($true) {
        $iteration++

        # Check duration limit
        if ($DurationMinutes -gt 0 -and $stopwatch.Elapsed.TotalMinutes -ge $DurationMinutes) {
            Write-Host "`nMonitoring duration ($DurationMinutes min) reached. Exiting." -ForegroundColor Yellow
            break
        }

        try {
            # VMFleet 2.1 has no cmdlet that returns live data: read the CSV file system counters of every node
            # (each Invoke-Command reads its own node only, so there is no second hop).
            $nodeSamples = @(foreach ($node in $nodes) {
                    Invoke-RemoteCommand -ComputerName $node -Credential $Credential -MaxRetries 1 -ScriptBlock {
                        $paths = '\Cluster CSVFS(_Total)\reads/sec', '\Cluster CSVFS(_Total)\writes/sec', '\Cluster CSVFS(_Total)\read bytes/sec',
                        '\Cluster CSVFS(_Total)\write bytes/sec', '\Cluster CSVFS(_Total)\avg. sec/read', '\Cluster CSVFS(_Total)\avg. sec/write'
                        $values = @{}
                        foreach ($sample in (Get-Counter -Counter $paths -ErrorAction Stop).CounterSamples) {
                            $values[($sample.Path -split '\\')[-1]] = $sample.CookedValue
                        }
                        $values
                    }
                })

            $liveData = $null
            if ($nodeSamples.Count -gt 0) {
                $sumOf = { param($key) ($nodeSamples | ForEach-Object { [double]$_[$key] } | Measure-Object -Sum).Sum }
                $readIops = & $sumOf 'reads/sec'
                $writeIops = & $sumOf 'writes/sec'
                $readLatency = ($nodeSamples | ForEach-Object { [double]$_['avg. sec/read'] * [double]$_['reads/sec'] } | Measure-Object -Sum).Sum
                $writeLatency = ($nodeSamples | ForEach-Object { [double]$_['avg. sec/write'] * [double]$_['writes/sec'] } | Measure-Object -Sum).Sum
                if (($readIops + $writeIops) -gt 0) {
                    $liveData = @{
                        VMCount           = $nodeSamples.Count
                        TotalReadIOPS     = [math]::Round($readIops)
                        TotalWriteIOPS    = [math]::Round($writeIops)
                        AvgReadLatencyMs  = $(if ($readIops -gt 0) { [math]::Round($readLatency / $readIops * 1000, 2) } else { 0 })
                        AvgWriteLatencyMs = $(if ($writeIops -gt 0) { [math]::Round($writeLatency / $writeIops * 1000, 2) } else { 0 })
                        TotalReadMBps     = [math]::Round((& $sumOf 'read bytes/sec') / 1MB, 1)
                        TotalWriteMBps    = [math]::Round((& $sumOf 'write bytes/sec') / 1MB, 1)
                    }
                }
            }

            if ($liveData) {
                $totalIOPS = $liveData.TotalReadIOPS + $liveData.TotalWriteIOPS
                $elapsed = Format-Duration $stopwatch.Elapsed

                # Clear line and print update
                Write-Host "`r[$elapsed] Nodes:$($liveData.VMCount) | IOPS:$totalIOPS (R:$($liveData.TotalReadIOPS) W:$($liveData.TotalWriteIOPS)) | Lat(ms) R:$($liveData.AvgReadLatencyMs) W:$($liveData.AvgWriteLatencyMs) | Thru(MB/s) R:$($liveData.TotalReadMBps) W:$($liveData.TotalWriteMBps)" -NoNewline

                if ($LogToFile) {
                    Write-Log -Message "IOPS=$totalIOPS ReadLat=$($liveData.AvgReadLatencyMs)ms WriteLat=$($liveData.AvgWriteLatencyMs)ms ReadMBps=$($liveData.TotalReadMBps) WriteMBps=$($liveData.TotalWriteMBps)" -Severity Information
                }
            } else {
                Write-Host "`r[$(Format-Duration $stopwatch.Elapsed)] No active workload detected" -NoNewline
            }
        } catch {
            Write-Host "`r[$(Format-Duration $stopwatch.Elapsed)] Connection error: $($_.Exception.Message)" -NoNewline -ForegroundColor Red
        }

        Start-Sleep -Seconds $RefreshIntervalSeconds
    }
} catch {
    if ($LogToFile) {
        Write-Log -Message "Monitor failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    }
    throw
} finally {
    Write-Host ''
    if ($LogToFile) { Stop-LogSession }
}
