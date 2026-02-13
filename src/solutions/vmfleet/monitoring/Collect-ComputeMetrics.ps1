# =============================================================================
# Collect-ComputeMetrics.ps1 - Azure Local Load Tools
# =============================================================================
# Collects compute (CPU, Memory, Hyper-V) counters during tests.
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
    [string]$OutputPath,

    [Parameter()]
    [int]$SampleIntervalSeconds = 5,

    [Parameter()]
    [int]$DurationSeconds = 300
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'Monitoring-Compute' -LogRootPath (Join-Path $ProjectRoot 'logs\monitoring')

try {
    Write-Log -Message 'Starting compute metrics collection' -Severity Information

    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\example-cluster.yml'
    }

    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml
    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }

    if (-not $OutputPath) {
        $OutputPath = Join-Path $ProjectRoot "logs\monitoring\compute-$(Get-Timestamp -FilenameSafe)"
    }
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    $computeCounters = @(
        '\Processor(_Total)\% Processor Time'
        '\Processor(*)\% Processor Time'
        '\Memory\Available MBytes'
        '\Memory\% Committed Bytes In Use'
        '\Memory\Pages/sec'
        '\Hyper-V Hypervisor Logical Processor(_Total)\% Total Run Time'
        '\Hyper-V Hypervisor Virtual Processor(*)\% Total Run Time'
        '\Hyper-V Dynamic Memory Balancer(*)\Available Memory'
        '\Hyper-V Virtual Machine Health Summary\Health OK'
    )

    $maxSamples = [math]::Ceiling($DurationSeconds / $SampleIntervalSeconds)
    Write-Log -Message "Collecting $($computeCounters.Count) counters from $($nodes.Count) nodes for ${DurationSeconds}s" -Severity Information

    $jobs = @()
    foreach ($node in $nodes) {
        $job = Invoke-Command -ComputerName $node -Credential $Credential -AsJob -ScriptBlock {
            param($Counters, $Interval, $MaxSamples)
            Get-Counter -Counter $Counters -SampleInterval $Interval -MaxSamples $MaxSamples -ErrorAction SilentlyContinue
        } -ArgumentList @($computeCounters, $SampleIntervalSeconds, $maxSamples)

        $jobs += @{ Node = $node; Job = $job }
        Write-Log -Message "Started collection on $node (Job $($job.Id))" -Severity Information
    }

    Write-Log -Message 'Waiting for collection to complete...' -Severity Information
    $jobs | ForEach-Object { $_.Job | Wait-Job -Timeout ($DurationSeconds + 60) }

    foreach ($j in $jobs) {
        $data = Receive-Job -Job $j.Job -ErrorAction SilentlyContinue
        $nodeFile = Join-Path $OutputPath "$($j.Node)-compute-metrics.jsonl"

        if ($data) {
            foreach ($sample in $data) {
                foreach ($reading in $sample.CounterSamples) {
                    $entry = @{
                        timestamp    = $sample.Timestamp.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                        node         = $j.Node
                        counter_path = $reading.Path
                        counter_name = $reading.CounterName
                        instance     = $reading.InstanceName
                        value        = $reading.CookedValue
                    } | ConvertTo-Json -Compress
                    Add-Content -Path $nodeFile -Value $entry
                }
            }
            Write-Log -Message "Saved $($j.Node) compute metrics" -Severity Information
        }

        Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
    }

    Write-Log -Message "Compute metrics collection complete: $OutputPath" -Severity Information
    return $OutputPath
}
catch {
    Write-Log -Message "Compute collection failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
