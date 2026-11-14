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

    # Minutes to wait for the repair and the cluster to settle (0 = check once). Default: fault_resync_timeout_minutes in the config file.
    [Parameter()]
    [ValidateRange(0, 600)]
    [double]$ResyncTimeoutMinutes,

    # Seconds between two health polls. Default: fault_settle_poll_seconds in the config file.
    [Parameter()]
    [ValidateRange(1, 300)]
    [int]$PollSeconds,

    # Consecutive healthy polls before the lock is cleared. Default: fault_settle_observations in the config file.
    [Parameter()]
    [ValidateRange(1, 20)]
    [int]$SettleObservations,

    # The tool's config file the fault settings are read from. Default: tools/vmfleet/config/vmfleet.json.
    [Parameter()]
    [string]$SolutionConfigPath
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
Import-Module (Join-Path $ProjectRoot 'common\modules\FaultInjection\FaultInjection.psm1') -Force

if (-not $SolutionConfigPath) { $SolutionConfigPath = Join-Path $ProjectRoot 'tools\vmfleet\config\vmfleet.json' }
$undoParams = @{ ComputerName = $ComputerName; AllowFault = $AllowFault; SolutionConfigPath = $SolutionConfigPath }
foreach ($name in 'ResyncTimeoutMinutes', 'PollSeconds', 'SettleObservations') {
    if ($PSBoundParameters.ContainsKey($name)) { $undoParams[$name] = $PSBoundParameters[$name] }
}
if ($Credential) { $undoParams['Credential'] = $Credential }
if ($WhatIfPreference) { $undoParams['WhatIf'] = $true }
if ($PSBoundParameters.ContainsKey('Confirm')) { $undoParams['Confirm'] = [bool]$PSBoundParameters['Confirm'] }

Undo-FaultInjection @undoParams
