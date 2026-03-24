# =============================================================================
# Start-FioTest.ps1 - Azure Local Load Tools
# =============================================================================
# Runs a fio workload against target Linux VMs using a SSH-based execution
# model. Supports profile-driven parameter resolution.
# Phase 2 of the fio pipeline.
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
    [string]$BlockSize,

    [Parameter()]
    [string]$IoEngine,

    [Parameter()]
    [int]$IoDepth,

    [Parameter()]
    [int]$NumJobs,

    [Parameter()]
    [int]$RuntimeSeconds,

    [Parameter()]
    [string]$TestDirectory,

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

$logSession = Start-LogSession -Component 'Fio-Test' -LogRootPath (Join-Path $ProjectRoot 'logs\fio')

try {
    Write-Log -Message 'Starting fio test phase' -Severity Information

    if (-not $RunId) { $RunId = "fio-$(Get-Timestamp -FilenameSafe)" }

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\fio\config\fio.json'
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

    # Resolve parameters: explicit param > profile > solution config
    $blkSize    = if ($BlockSize)      { $BlockSize }      elseif ($profile) { $profile.profile.parameters.block_size }   else { $solutionConfig.fio_block_size }
    $engine     = if ($IoEngine)       { $IoEngine }       elseif ($profile) { $profile.profile.parameters.io_engine }    else { $solutionConfig.fio_io_engine }
    $ioDepthVal = if ($IoDepth)        { $IoDepth }        elseif ($profile) { $profile.profile.parameters.io_depth }     else { [int]$solutionConfig.fio_io_depth }
    $jobs       = if ($NumJobs)        { $NumJobs }        elseif ($profile) { $profile.profile.parameters.num_jobs }     else { [int]$solutionConfig.fio_num_jobs }
    $runtime    = if ($RuntimeSeconds) { $RuntimeSeconds } elseif ($profile) { $profile.profile.parameters.runtime_seconds } else { [int]$solutionConfig.fio_runtime_seconds }
    $testDir    = if ($TestDirectory)  { $TestDirectory }  elseif ($profile) { $profile.profile.parameters.test_directory }  else { '/tmp/fio-test' }
    $rw         = if ($profile)        { $profile.profile.parameters.rw }        else { 'randrw' }
    $rwMixRead  = if ($profile)        { $profile.profile.parameters.rwmixread } else { 70 }

    $nodes = $clusterConfig.nodes | Where-Object { $_.role -eq 'worker' -or -not $_.role } | ForEach-Object { $_.name }
    if ($nodes.Count -eq 0) {
        $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    }

    Write-Log -Message "Test parameters: block=$blkSize engine=$engine iodepth=$ioDepthVal jobs=$jobs runtime=${runtime}s rw=$rw" -Severity Information
    Write-Log -Message "Target nodes: $($nodes -join ', ')" -Severity Information

    # Resolve SSH credentials
    $sshUserVal = if ($SshUser) { $SshUser } else { $clusterConfig.cluster.ssh_user }
    $sshKeyVal  = if ($SshKeyPath) { $SshKeyPath } else { $clusterConfig.cluster.ssh_key_path }

    if (-not $sshUserVal) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $sshCreds = Get-ManagedCredential -CredentialName 'linux_ssh' -ProjectRoot $ProjectRoot
        $sshUserVal = $sshCreds.UserName
    }

    # Results staging directory on remote nodes
    $remoteResultsDir = "/tmp/fio-results/$RunId"

    # Build fio command
    $fioCmd = "mkdir -p $remoteResultsDir && " +
              "fio --name=fio-$RunId " +
              "--rw=$rw " +
              "--rwmixread=$rwMixRead " +
              "--bs=$blkSize " +
              "--ioengine=$engine " +
              "--iodepth=$ioDepthVal " +
              "--numjobs=$jobs " +
              "--size=1G " +
              "--runtime=$runtime " +
              "--time_based " +
              "--directory=$testDir " +
              "--create_on_open=1 " +
              "--output-format=json " +
              "--output=$remoteResultsDir/fio-results.json " +
              "--filename_format=fio-\$jobnum.dat && " +
              "echo 'FIO_DONE'"

    $nodeResults = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($node in $nodes) {
        if ($PSCmdlet.ShouldProcess($node, "Run fio workload")) {
            Write-Log -Message "Starting fio on node: $node" -Severity Information

            $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
            if ($sshKeyVal) { $sshArgs += '-i', $sshKeyVal }
            $sshArgs += "$sshUserVal@$node", $fioCmd

            $output = & ssh @sshArgs 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0) {
                Write-Log -Message "fio failed on $node (exit $exitCode): $output" -Severity Error
                $nodeResults.Add(@{ Node = $node; Status = 'Failed'; ExitCode = $exitCode })
            }
            else {
                Write-Log -Message "fio completed on $node" -Severity Information
                $nodeResults.Add(@{
                    Node              = $node
                    Status            = 'Completed'
                    RemoteResultsPath = $remoteResultsDir
                })
            }
        }
    }

    Write-Log -Message "fio workload complete on $($nodeResults.Count) nodes" -Severity Information
    Write-Host "fio test finished. Run ID: $RunId" -ForegroundColor Green

    return @{
        RunId           = $RunId
        NodeResults     = $nodeResults
        RemoteResultDir = $remoteResultsDir
        Parameters      = @{
            BlockSize      = $blkSize
            IoEngine       = $engine
            IoDepth        = $ioDepthVal
            NumJobs        = $jobs
            RuntimeSeconds = $runtime
            Rw             = $rw
            RwMixRead      = $rwMixRead
            ProfileName    = if ($profile) { $profile.profile.name } else { 'custom' }
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
