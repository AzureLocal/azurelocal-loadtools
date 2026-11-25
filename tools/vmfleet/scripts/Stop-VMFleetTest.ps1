# =============================================================================
# Stop-VMFleetTest.ps1 - Azure Local Load Tools
# =============================================================================
# Stops the VMFleet workload with Stop-Fleet (pauses the fleet and shuts the fleet
# VMs down), run on the first node as a one-shot scheduled task. Phase 6 of the
# VMFleet pipeline. NOT PROVEN ON A LIVE CLUSTER.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Force is part of the common phase-script parameter set; Stop-Fleet has no confirmation to force.')]
param(
    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$RunId,

    [Parameter()]
    [switch]$Force,

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

$null = Start-LogSession -Component 'VMFleet-Stop' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Stopping VMFleet workload' -Severity Information
    if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

    if (-not $ClusterConfigPath) { $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot }
    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath

    $Credential = Get-VMFleetCredentialOrExit -Credential $Credential -ProjectRoot $ProjectRoot

    if ($PSCmdlet.ShouldProcess($cluster.PrimaryNode, 'Stop VMFleet workload (Stop-Fleet)')) {
        $null = Invoke-VMFleetNodeTask -ComputerName $cluster.PrimaryNode -Credential $Credential -Step 'Stop' -RunId $RunId `
            -CollectPath $cluster.CollectPath -TimeoutSeconds ($TimeoutMinutes * 60)

        Write-Log -Message 'VMFleet workload stopped' -Severity Information
        Write-Host 'VMFleet workload stopped.' -ForegroundColor Green
    }
} catch {
    Write-Log -Message "Stop failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
} finally {
    Stop-LogSession
}
