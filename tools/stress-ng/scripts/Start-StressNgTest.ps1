# =============================================================================
# Start-StressNgTest.ps1 - Azure Local Load Tools
# =============================================================================
# Runs stress-ng workloads on target Linux VMs via SSH.
# Supports cpu, memory (vm), and I/O (hdd) stressor profiles.
# Phase 1 of the stress-ng pipeline.
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

    [Parameter()]
    [string]$SshUser,

    [Parameter()]
    [string]$SshKeyPath,

    [Parameter()]
    [string[]]$Stressors,

    [Parameter()]
    [int]$Workers,

    [Parameter()]
    [string]$Timeout,

    [Parameter()]
    [string]$RunId
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'StressNg-Test' -LogRootPath (Join-Path $ProjectRoot 'logs\stress-ng')

try {
    Write-Log -Message 'Starting stress-ng test phase' -Severity Information

    if (-not $RunId) { $RunId = "stressng-$(Get-Timestamp -FilenameSafe)" }

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\stress-ng\config\stress-ng.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    # Load workload profile
    $profile = $null
    if ($ProfilePath -and (Test-Path $ProfilePath)) {
        $profile = Get-Content -Path $ProfilePath -Raw | ConvertFrom-Yaml
        Write-Log -Message "Loaded profile: $($profile.profile.name)" -Severity Information
    }

    # Resolve parameters: explicit > profile > solution config
    $stressorList = if ($Stressors -and $Stressors.Count -gt 0) {
        $Stressors
    }
    elseif ($profile) {
        $profile.profile.parameters.stressors
    }
    else {
        $solutionConfig.stress_ng_stressors
    }

    $workersVal = if ($Workers -gt 0) {
        $Workers
    }
    elseif ($profile) {
        $profile.profile.parameters.workers
    }
    else {
        [int]$solutionConfig.stress_ng_workers
    }

    $timeoutVal = if ($Timeout) {
        $Timeout
    }
    elseif ($profile) {
        $profile.profile.parameters.timeout
    }
    else {
        $solutionConfig.stress_ng_timeout
    }

    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    $sshUserVal = if ($SshUser) { $SshUser } else { $clusterConfig.cluster.ssh_user }
    $sshKeyVal  = if ($SshKeyPath) { $SshKeyPath } else { $clusterConfig.cluster.ssh_key_path }

    Write-Log -Message "Stressors: $($stressorList -join ', ') | Workers: $workersVal | Timeout: $timeoutVal" -Severity Information
    Write-Log -Message "Target nodes: $($nodes -join ', ')" -Severity Information

    $remoteResultsDir = "/tmp/stress-ng-results/$RunId"

    # Build stress-ng command
    # stress-ng --metrics-brief writes results to stderr/stdout; use --yaml for structured output
    $stressorFlags = ''
    foreach ($stressor in $stressorList) {
        $stressorFlags += "--$stressor $workersVal "
    }

    $stressCmd = "mkdir -p $remoteResultsDir && " +
                 "stress-ng $stressorFlags" +
                 "--timeout $timeoutVal " +
                 "--metrics-brief " +
                 "--yaml $remoteResultsDir/stress-ng-results.yml " +
                 "--log-file $remoteResultsDir/stress-ng.log " +
                 "&& echo 'STRESSNG_DONE'"

    $nodeResults = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($node in $nodes) {
        if ($PSCmdlet.ShouldProcess($node, "Run stress-ng on $node")) {
            Write-Log -Message "Starting stress-ng on $node..." -Severity Information

            $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
            if ($sshKeyVal) { $sshArgs += '-i', $sshKeyVal }
            $sshArgs += "$sshUserVal@$node", $stressCmd

            $output = & ssh @sshArgs 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0) {
                Write-Log -Message "stress-ng failed on $node (exit $exitCode): $output" -Severity Error
                $nodeResults.Add(@{ Node = $node; Status = 'Failed'; ExitCode = $exitCode })
            }
            else {
                Write-Log -Message "stress-ng completed on $node" -Severity Information
                $nodeResults.Add(@{
                    Node              = $node
                    Status            = 'Completed'
                    RemoteResultsPath = $remoteResultsDir
                })
            }
        }
    }

    $completed = ($nodeResults | Where-Object { $_.Status -eq 'Completed' }).Count
    Write-Log -Message "stress-ng finished on $completed/$($nodeResults.Count) nodes" -Severity Information
    Write-Host "stress-ng test finished. Run ID: $RunId" -ForegroundColor Green

    return @{
        RunId           = $RunId
        NodeResults     = $nodeResults
        RemoteResultDir = $remoteResultsDir
        Parameters      = @{
            Stressors   = $stressorList
            Workers     = $workersVal
            Timeout     = $timeoutVal
            ProfileName = if ($profile) { $profile.profile.name } else { 'custom' }
        }
    }
}
catch {
    Write-Log -Message "Test phase failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
