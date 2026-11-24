# =============================================================================
# Install-VMFleet.ps1 - Azure Local Load Tools
# =============================================================================
# Installs the VMFleet module on the first cluster node and runs Install-Fleet
# there (as a one-shot scheduled task, see VMFleet-Common.ps1). Phase 2 of the
# VMFleet pipeline.
#
# Prerequisites on the cluster: a CSV named 'collect' (ReFS) and one CSV per node
# whose name starts with the node name (Get-FleetVolumeEstimate sizes them).
# NOT PROVEN ON A LIVE CLUSTER.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'DiskSpdVersion keeps the common phase-script parameter set; VMFleet 2.1 downloads its own DiskSpd.')]
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
    [string]$RunId,

    [Parameter()]
    [string]$VMFleetVersion,

    # Kept for the common phase-script parameter set; VMFleet 2.1 downloads its own DiskSpd.
    [Parameter()]
    [string]$DiskSpdVersion,

    # Keep the CSV block cache (Install-Fleet turns it off for the whole cluster by default).
    [Parameter()]
    [switch]$KeepBlockCache,

    # Do not download DiskSpd; place diskspd.exe (2.1.0.0 or later) in <collect>\tools yourself.
    [Parameter()]
    [switch]$NoTools,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [int]$TimeoutMinutes = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve project root
if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

# Load core modules
. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
. (Join-Path $PSScriptRoot 'VMFleet-Common.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

# Initialize logging
$null = Start-LogSession -Component 'VMFleet-Install' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet installation phase' -Severity Information
    if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

    if (-not $SolutionConfigPath) { $SolutionConfigPath = Join-Path $ProjectRoot 'tools\vmfleet\config\vmfleet.json' }
    if (-not $ClusterConfigPath) { $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot }

    $solutionConfig = Get-Content -LiteralPath $SolutionConfigPath -Raw | ConvertFrom-Json
    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath

    # Override chain: parameter > solution JSON (vmfleet_version)
    $vmfleetVer = if ($VMFleetVersion) { $VMFleetVersion } else { [string](Get-VMFleetConfigValue $solutionConfig 'vmfleet_version' '') }
    if (-not $vmfleetVer) { throw 'No VMFleet version: pass -VMFleetVersion or set vmfleet_version in tools\vmfleet\config\vmfleet.json.' }

    Write-Log -Message "Cluster: $($cluster.ClusterName) | VMFleet: $vmfleetVer | primary node: $($cluster.PrimaryNode)" -Severity Information
    Write-Log -Message "Nodes: $($cluster.Nodes -join ', ')" -Severity Information

    $Credential = Get-VMFleetCredentialOrExit -Credential $Credential -ProjectRoot $ProjectRoot

    Write-Log -Message 'Testing cluster connectivity...' -Severity Information
    $connectivity = Test-ClusterConnectivity -NodeNames $cluster.Nodes -Credential $Credential
    $unreachable = @($connectivity | Where-Object { -not $_.Reachable })
    if ($unreachable.Count -gt 0) {
        throw "Cannot reach nodes: $($unreachable.Node -join ', ')"
    }
    Write-Log -Message 'All nodes reachable' -Severity Information

    if ($PSCmdlet.ShouldProcess($cluster.PrimaryNode, "Install VMFleet $vmfleetVer and run Install-Fleet")) {
        Write-Log -Message "Installing VMFleet on $($cluster.PrimaryNode) (node task)..." -Severity Information
        $nodeArguments = @{
            VMFleetVersion = $vmfleetVer
            KeepBlockCache = $KeepBlockCache.IsPresent
            NoTools        = $NoTools.IsPresent
            Force          = $Force.IsPresent
        }
        $result = Invoke-VMFleetNodeTask -ComputerName $cluster.PrimaryNode -Credential $Credential -Step 'Install' -RunId $RunId `
            -CollectPath $cluster.CollectPath -TimeoutSeconds ($TimeoutMinutes * 60) -Arguments $nodeArguments
        foreach ($component in @($result.Output.Components)) {
            Write-Log -Message "Installed component: $($component.Component) $($component.Version)" -Severity Information
        }
    }

    Write-Log -Message 'VMFleet installation phase completed successfully' -Severity Information
    Write-Host 'VMFleet installation complete.' -ForegroundColor Green
} catch {
    Write-Log -Message "Installation failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
} finally {
    Stop-LogSession
}
