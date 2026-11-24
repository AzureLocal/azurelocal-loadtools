# =============================================================================
# Remove-VMFleet.ps1 - Azure Local Load Tools
# =============================================================================
# Removes the whole VMFleet fleet with Remove-Fleet (every fleet VM, its cluster
# role, its folder on the node volumes, the flag files and the FleetInternal
# vSwitch), run on the first node as a one-shot scheduled task. Then it checks that
# no vm-* VM and no vm-* folder is left and fails if one is. Cleanup phase of the
# VMFleet pipeline. NOT PROVEN ON A LIVE CLUSTER.
#
# It does NOT delete the base image, the Collect volume or the VMFleet module.
# -RemoveCollectData also deletes the DiskSpd result files (result-*.xml,
# perfctr-*.blg) from <collect>\result.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Force is part of the common phase-script parameter set; removal is gated by ShouldProcess (-WhatIf/-Confirm).')]
param(
    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$RunId,

    # Also delete the DiskSpd result files from the Collect volume (the old name RemoveVHDs still works).
    [Parameter()]
    [Alias('RemoveVHDs')]
    [switch]$RemoveCollectData,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [int]$TimeoutMinutes = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
. (Join-Path $PSScriptRoot 'VMFleet-Common.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$null = Start-LogSession -Component 'VMFleet-Remove' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet cleanup phase' -Severity Information
    if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

    if (-not $ClusterConfigPath) { $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot }
    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath

    $Credential = Get-VMFleetCredentialOrExit -Credential $Credential -ProjectRoot $ProjectRoot

    if ($PSCmdlet.ShouldProcess($cluster.ClusterName, 'Remove every VMFleet VM and its files (Remove-Fleet)')) {
        Write-Log -Message 'Stopping the workload and removing the fleet (node task)...' -Severity Information
        $result = Invoke-VMFleetNodeTask -ComputerName $cluster.PrimaryNode -Credential $Credential -Step 'Remove' -RunId $RunId `
            -CollectPath $cluster.CollectPath -TimeoutSeconds ($TimeoutMinutes * 60) `
            -Arguments @{ RemoveCollectData = $RemoveCollectData.IsPresent }

        $leftVMs = @($result.Output.RemainingVMs)
        $leftDirs = @($result.Output.RemainingDirectories)
        if ($leftVMs.Count -gt 0 -or $leftDirs.Count -gt 0) {
            throw "Cleanup is incomplete. VMs left: $($leftVMs -join ', '). Folders left: $($leftDirs -join ', '). Fix the cause (see $($result.TranscriptPath) on the node) and run this script again."
        }
        Write-Log -Message 'No fleet VM and no fleet folder is left' -Severity Information
    }

    Write-Log -Message 'VMFleet cleanup completed' -Severity Information
    Write-Host 'VMFleet cleanup complete.' -ForegroundColor Green
} catch {
    Write-Log -Message "Cleanup failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
} finally {
    Stop-LogSession
}
