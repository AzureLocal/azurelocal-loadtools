# =============================================================================
# Install.node.ps1 - node-side payload of Install-VMFleet.ps1
# =============================================================================
# Runs ON the first cluster node as a one-shot scheduled task (Windows PowerShell
# 5.1: the VMFleet and FailoverClusters modules need it). Get-VMFleetNodeWrapperScript
# in VMFleet-Common.ps1 wraps this body: it provides Get-Arg, $StepArgs, $Secrets and
# collects $StepResult. Not meant to be run by hand.
#
# Installs the VMFleet module (PSGallery, needs internet on the node) and runs
# Install-Fleet, which needs a CSV named 'collect' and one CSV per node whose name
# starts with the node name. Install-Fleet also creates the control/flag/result/tools
# folders on the Collect volume, downloads DiskSpd into <collect>\tools (or finds a
# copy you placed there) and, unless -KeepBlockCache is set, turns the CSV block
# cache off for the cluster.
# =============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The wrapper reads $StepResult after it ran this body.')]
param()

$version = [string](Get-Arg 'VMFleetVersion' '')
if (-not $version) {
    throw 'VMFleetVersion is empty. Set vmfleet_version in tools\vmfleet\config\vmfleet.json or pass -VMFleetVersion.'
}

$installed = @(Get-Module -ListAvailable -Name VMFleet | Where-Object { $_.Version.ToString() -eq $version })
if ($installed.Count -eq 0) {
    Write-Host "Installing the VMFleet module $version from the PowerShell Gallery"
    Install-Module -Name VMFleet -RequiredVersion $version -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
} else {
    Write-Host "VMFleet $version is already installed"
}
Import-Module -Name VMFleet -RequiredVersion $version -Force -ErrorAction Stop

$installParams = @{}
if (Get-Arg 'KeepBlockCache' $false) { $installParams['KeepBlockCache'] = $true }
if (Get-Arg 'NoTools' $false) { $installParams['NoTools'] = $true }
if (Get-Arg 'Force' $false) { $installParams['Force'] = $true }

Install-Fleet @installParams -ErrorAction Stop

$components = @(Get-FleetVersion | ForEach-Object { @{ Component = [string]$_.Component; Version = [string]$_.Version } })
$StepResult = @{ VMFleetVersion = $version; Components = $components }
