# =============================================================================
# Undo-VMFleetFault.ps1 - Azure Local Load Tools
# =============================================================================
# Reverses the fault applied by Invoke-VMFleetFault.ps1, waits for the storage
# repair to finish and the cluster to stay Healthy for several polls, and only
# then clears the fault lock. Without -AllowFault it only prints what it would do.
# NOT PROVEN ON A LIVE CLUSTER.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$ComputerName,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [switch]$AllowFault,

    [Parameter()]
    [ValidateRange(0, 600)]
    [double]$ResyncTimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
Import-Module (Join-Path $ProjectRoot 'common\modules\FaultInjection\FaultInjection.psm1') -Force

$undoParams = @{ ComputerName = $ComputerName; AllowFault = $AllowFault; ResyncTimeoutMinutes = $ResyncTimeoutMinutes }
if ($Credential) { $undoParams['Credential'] = $Credential }
if ($WhatIfPreference) { $undoParams['WhatIf'] = $true }
if ($PSBoundParameters.ContainsKey('Confirm')) { $undoParams['Confirm'] = [bool]$PSBoundParameters['Confirm'] }

Undo-FaultInjection @undoParams
