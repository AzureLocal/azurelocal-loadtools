# =============================================================================
# Start-VMFleetTest.ps1 - Azure Local Load Tools
# =============================================================================
# Starts a VMFleet DiskSpd workload test with the specified profile.
# Phase 3 of the VMFleet pipeline.
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
    [string]$BlockSize,

    [Parameter()]
    [int]$WriteRatio,

    [Parameter()]
    [int]$RandomRatio,

    [Parameter()]
    [int]$OutstandingIO,

    [Parameter()]
    [int]$ThreadsPerVM,

    [Parameter()]
    [int]$DurationSeconds,

    [Parameter()]
    [int]$WarmupSeconds
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'VMFleet-Test' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet test phase' -Severity Information

    # Load configurations
    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'config\variables\solutions\vmfleet.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\example-cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    # Load workload profile if specified
    $profile = $null
    if ($ProfilePath) {
        if (Test-Path $ProfilePath) {
            $profile = Get-Content -Path $ProfilePath -Raw | ConvertFrom-Yaml
            Write-Log -Message "Loaded profile: $($profile.name)" -Severity Information
        }
        else {
            Write-Log -Message "Profile not found: $ProfilePath" -Severity Warning
        }
    }

    # Resolve parameters: explicit param > profile > solution config
    $blockSz   = if ($BlockSize)        { $BlockSize }        elseif ($profile) { $profile.parameters.block_size }      else { $solutionConfig.vmfleet_block_size }
    $writeR    = if ($WriteRatio)       { $WriteRatio }       elseif ($profile) { $profile.parameters.write_ratio }     else { [int]$solutionConfig.vmfleet_write_ratio }
    $randomR   = if ($RandomRatio)      { $RandomRatio }      elseif ($profile) { $profile.parameters.random_ratio }    else { [int]$solutionConfig.vmfleet_random_ratio }
    $outIO     = if ($OutstandingIO)    { $OutstandingIO }    elseif ($profile) { $profile.parameters.outstanding_io }  else { [int]$solutionConfig.vmfleet_outstanding_io }
    $threads   = if ($ThreadsPerVM)     { $ThreadsPerVM }     elseif ($profile) { $profile.parameters.threads_per_vm }  else { [int]$solutionConfig.vmfleet_threads_per_vm }
    $duration  = if ($DurationSeconds)  { $DurationSeconds }  elseif ($profile) { $profile.parameters.duration }        else { [int]$solutionConfig.vmfleet_test_duration }
    $warmup    = if ($WarmupSeconds)    { $WarmupSeconds }    elseif ($profile) { $profile.parameters.warmup }          else { [int]$solutionConfig.vmfleet_warmup_seconds }

    $primaryNode = ($clusterConfig.nodes | ForEach-Object { $_.name })[0]

    Write-Log -Message "Test parameters: Block=$blockSz Write=$writeR% Random=$randomR% OIO=$outIO Threads=$threads Duration=${duration}s Warmup=${warmup}s" -Severity Information

    # Get credentials
    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    # Start the workload
    if ($PSCmdlet.ShouldProcess($primaryNode, "Start VMFleet DiskSpd workload")) {
        Write-Log -Message 'Starting DiskSpd workload across fleet VMs...' -Severity Information

        Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            param($BlockSize, $WriteRatio, $RandomRatio, $OutstandingIO, $Threads, $Duration, $Warmup)

            Import-Module VMFleet -ErrorAction Stop

            $startParams = @{
                b = $BlockSize
                w = $WriteRatio
                r = $RandomRatio
                o = $OutstandingIO
                t = $Threads
                d = $Duration
                W = $Warmup
            }

            Start-Fleet @startParams

            Write-Output "VMFleet workload started with DiskSpd parameters: -b$BlockSize -w$WriteRatio -r$RandomRatio -o$OutstandingIO -t$Threads -d$Duration -W$Warmup"
        } -ArgumentList @($blockSz, $writeR, $randomR, $outIO, $threads, $duration, $warmup)

        Write-Log -Message 'VMFleet workload started successfully' -Severity Information
    }

    # Inform about test duration
    $totalTime = $warmup + $duration
    Write-Log -Message "Test will run for approximately $totalTime seconds (${warmup}s warmup + ${duration}s test)" -Severity Information
    Write-Host "VMFleet test started. Expected duration: $(Format-Duration ([TimeSpan]::FromSeconds($totalTime)))" -ForegroundColor Green

    # Return test metadata for downstream scripts
    return @{
        StartTime  = Get-Timestamp
        Duration   = $duration
        Warmup     = $warmup
        BlockSize  = $blockSz
        WriteRatio = $writeR
        RandomRatio = $randomR
        OutstandingIO = $outIO
        Threads    = $threads
        ProfileName = if ($profile) { $profile.name } else { 'custom' }
    }
}
catch {
    Write-Log -Message "Test start failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
