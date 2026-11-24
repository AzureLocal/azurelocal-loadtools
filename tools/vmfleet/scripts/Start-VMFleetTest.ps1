# =============================================================================
# Start-VMFleetTest.ps1 - Azure Local Load Tools
# =============================================================================
# Runs a VMFleet DiskSpd workload with Start-FleetSweep on the first node (one-shot
# scheduled task, see VMFleet-Common.ps1). Phase 4 of the VMFleet pipeline.
#
# Start-FleetSweep blocks until the run is over (duration + warm-up + cool-down plus
# about a minute). By default this script waits for it and returns the run metadata.
# With -NoWait it returns right after the task started (the metadata has a TaskHandle)
# so the pipeline can watch the cluster while the load runs, then calls
# Wait-VMFleetNodeTask.
#
# Parameter precedence: explicit parameter > profile (profile.parameters:
# block_size, write_ratio, random_ratio, outstanding_io, threads_per_vm,
# duration_seconds, warmup_seconds, cooldown_seconds) > vmfleet.json
# (test_duration_seconds, warmup_seconds, cooldown_seconds) > General-profile defaults.
#
# NOT PROVEN ON A LIVE CLUSTER.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$SolutionConfigPath,

    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProfilePath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    # Labels the result files; Collect-VMFleetResults.ps1 finds them with the same RunId.
    [Parameter()]
    [string]$RunId,

    # DiskSpd block size, for example 8k (VMFleet takes whole KB).
    [Parameter()]
    [string]$BlockSize,

    [Parameter()]
    [int]$WriteRatio,

    # Percent random; VMFleet's sweep is random OR sequential: 50 or more selects random.
    [Parameter()]
    [int]$RandomRatio,

    [Parameter()]
    [int]$OutstandingIO,

    [Parameter()]
    [int]$ThreadsPerVM,

    [Parameter()]
    [int]$DurationSeconds,

    [Parameter()]
    [int]$WarmupSeconds,

    [Parameter()]
    [int]$CooldownSeconds,

    # Return as soon as the task has started; wait with Wait-VMFleetNodeTask.
    [Parameter()]
    [switch]$NoWait,

    # Extra time on top of duration + warm-up + cool-down before the wait gives up.
    [Parameter()]
    [int]$GraceMinutes = 30
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

$null = Start-LogSession -Component 'VMFleet-Test' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet test phase' -Severity Information
    if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

    if (-not $SolutionConfigPath) { $SolutionConfigPath = Join-Path $ProjectRoot 'tools\vmfleet\config\vmfleet.json' }
    if (-not $ClusterConfigPath) { $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot }

    $solutionConfig = Get-Content -LiteralPath $SolutionConfigPath -Raw | ConvertFrom-Json
    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath
    $loadProfile = Import-VMFleetProfile -ProfilePath $ProfilePath

    $override = @{}
    foreach ($key in 'BlockSize', 'WriteRatio', 'RandomRatio', 'OutstandingIO', 'ThreadsPerVM', 'DurationSeconds', 'WarmupSeconds', 'CooldownSeconds') {
        if ($PSBoundParameters.ContainsKey($key)) { $override[$key] = $PSBoundParameters[$key] }
    }
    $test = Resolve-VMFleetTestParameters -LoadProfile $loadProfile -SolutionConfig $solutionConfig -Override $override
    $tag = ConvertTo-VMFleetSafeName -Name $RunId -MaxLength 24

    Write-Log -Message "Test parameters ($($test.ProfileName)): Block=$($test.BlockSizeKB)k Write=$($test.WriteRatio)% Pattern=$($test.Pattern) OIO=$($test.OutstandingIO) Threads=$($test.ThreadsPerVM) Duration=$($test.DurationSeconds)s Warmup=$($test.WarmupSeconds)s Cooldown=$($test.CooldownSeconds)s Tag=$tag" -Severity Information
    if ($test.Mixed) {
        Write-Log -Message "random_ratio $($test.RandomRatio) is a mix; VMFleet's sweep runs a single pattern, so it runs '$($test.Pattern)' (100% $(if ($test.Pattern -eq 'r') { 'random' } else { 'sequential' }))." -Severity Warning
    }

    $Credential = Get-VMFleetCredentialOrExit -Credential $Credential -ProjectRoot $ProjectRoot

    $metadata = @{
        RunId         = $RunId
        Tag           = $tag
        StartTime     = $null
        ProfileName   = $test.ProfileName
        BlockSize     = "$($test.BlockSizeKB)k"
        WriteRatio    = $test.WriteRatio
        RandomRatio   = $test.RandomRatio
        Pattern       = $test.Pattern
        OutstandingIO = $test.OutstandingIO
        Threads       = $test.ThreadsPerVM
        Duration      = $test.DurationSeconds
        Warmup        = $test.WarmupSeconds
        Cooldown      = $test.CooldownSeconds
        TotalSeconds  = $test.TotalSeconds
        Started       = $false
        TaskHandle    = $null
    }

    if ($PSCmdlet.ShouldProcess($cluster.PrimaryNode, "Start the VMFleet DiskSpd sweep ($($test.TotalSeconds) s)")) {
        $nodeArguments = @{
            Tag             = $tag
            RunId           = $RunId
            ProfileName     = $test.ProfileName
            CollectPath     = $cluster.CollectPath
            BlockSizeKB     = $test.BlockSizeKB
            Threads         = $test.ThreadsPerVM
            OutstandingIO   = $test.OutstandingIO
            WriteRatio      = $test.WriteRatio
            Pattern         = $test.Pattern
            DurationSeconds = $test.DurationSeconds
            WarmupSeconds   = $test.WarmupSeconds
            CooldownSeconds = $test.CooldownSeconds
        }
        Write-Log -Message 'Starting Start-FleetSweep on the primary node (node task)...' -Severity Information
        $handle = Start-VMFleetNodeTask -ComputerName $cluster.PrimaryNode -Credential $Credential -Step 'Test' -RunId $RunId `
            -CollectPath $cluster.CollectPath -Arguments $nodeArguments
        $metadata.StartTime = Get-Timestamp
        $metadata.Started = $true
        $metadata.TaskHandle = $handle

        if (-not $NoWait) {
            $null = Wait-VMFleetNodeTask -Handle $handle -Credential $Credential -TimeoutSeconds (($test.TotalSeconds) + ($GraceMinutes * 60))
            $metadata.TaskHandle = $null
            Write-Log -Message 'VMFleet workload finished' -Severity Information
        } else {
            Write-Log -Message 'VMFleet workload started; not waiting (-NoWait)' -Severity Information
        }
    }

    Write-Host "VMFleet test $(if ($NoWait) { 'started' } else { 'finished' }). Run id: $RunId. Expected duration: $(Format-Duration ([TimeSpan]::FromSeconds($test.TotalSeconds)))" -ForegroundColor Green

    # Return test metadata for downstream scripts
    return $metadata
} catch {
    Write-Log -Message "Test start failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
} finally {
    Stop-LogSession
}
