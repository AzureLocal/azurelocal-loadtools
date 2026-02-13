# =============================================================================
# Watch-VMFleetMonitor.ps1 - Azure Local Load Tools
# =============================================================================
# Real-time monitoring dashboard for a running VMFleet workload.
# Can be run alongside Start-VMFleetTest for live metrics.
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

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'

if ($LogToFile) {
    Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force
    $logSession = Start-LogSession -Component 'VMFleet-Watch' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')
}

try {
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

    Write-Host "VMFleet Monitor - Refreshing every ${RefreshIntervalSeconds}s | Press Ctrl+C to stop" -ForegroundColor Cyan
    Write-Host "Cluster: $($clusterConfig.cluster.name) | Node: $primaryNode" -ForegroundColor Gray
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
            $liveData = Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
                Import-Module VMFleet -ErrorAction Stop

                $data = Get-FleetDataXml -ErrorAction SilentlyContinue
                if (-not $data) { return $null }

                $vmCount = ($data | Measure-Object).Count
                @{
                    VMCount           = $vmCount
                    TotalReadIOPS     = ($data | Measure-Object -Property ReadIOPS -Sum).Sum
                    TotalWriteIOPS    = ($data | Measure-Object -Property WriteIOPS -Sum).Sum
                    AvgReadLatencyMs  = [math]::Round(($data | Measure-Object -Property ReadLatencyMs -Average).Average, 2)
                    AvgWriteLatencyMs = [math]::Round(($data | Measure-Object -Property WriteLatencyMs -Average).Average, 2)
                    TotalReadMBps     = [math]::Round(($data | Measure-Object -Property ReadBytesPerSecond -Sum).Sum / 1MB, 1)
                    TotalWriteMBps    = [math]::Round(($data | Measure-Object -Property WriteBytesPerSecond -Sum).Sum / 1MB, 1)
                }
            } -MaxRetries 1

            if ($liveData) {
                $totalIOPS = $liveData.TotalReadIOPS + $liveData.TotalWriteIOPS
                $elapsed = Format-Duration $stopwatch.Elapsed

                # Clear line and print update
                Write-Host "`r[$elapsed] VMs:$($liveData.VMCount) | IOPS:$totalIOPS (R:$($liveData.TotalReadIOPS) W:$($liveData.TotalWriteIOPS)) | Lat(ms) R:$($liveData.AvgReadLatencyMs) W:$($liveData.AvgWriteLatencyMs) | Thru(MB/s) R:$($liveData.TotalReadMBps) W:$($liveData.TotalWriteMBps)" -NoNewline

                if ($LogToFile) {
                    Write-Log -Message "IOPS=$totalIOPS ReadLat=$($liveData.AvgReadLatencyMs)ms WriteLat=$($liveData.AvgWriteLatencyMs)ms ReadMBps=$($liveData.TotalReadMBps) WriteMBps=$($liveData.TotalWriteMBps)" -Severity Information
                }
            }
            else {
                Write-Host "`r[$(Format-Duration $stopwatch.Elapsed)] No active workload detected" -NoNewline
            }
        }
        catch {
            Write-Host "`r[$(Format-Duration $stopwatch.Elapsed)] Connection error: $($_.Exception.Message)" -NoNewline -ForegroundColor Red
        }

        Start-Sleep -Seconds $RefreshIntervalSeconds
    }
}
catch {
    if ($LogToFile) {
        Write-Log -Message "Monitor failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    }
    throw
}
finally {
    Write-Host ''
    if ($LogToFile) { Stop-LogSession }
}
