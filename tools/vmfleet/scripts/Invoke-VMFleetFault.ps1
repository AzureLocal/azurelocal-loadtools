# =============================================================================
# Invoke-VMFleetFault.ps1 - Azure Local Load Tools
# =============================================================================
# OPT-IN failure injection to run a VMFleet / DiskSpd test UNDER a failure
# condition (pause one node, or take one drive out). Never part of the pipeline
# and never a default. Without -AllowFault it only prints the plan.
#
#   1. Start the workload:  Start-VMFleetTest.ps1 -ProfilePath ...\failure-injection.yml
#   2. Inject one fault:    Invoke-VMFleetFault.ps1 -FaultType NodePause -NodeName <node> -ComputerName <cluster> -AllowFault
#   3. Observe, then undo:  Undo-VMFleetFault.ps1 -ComputerName <cluster> -AllowFault
#
# The UNDO command is printed first. The script refuses when the cluster is not
# healthy. NOT PROVEN ON A LIVE CLUSTER: prove it on a non-production cluster first.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('NodePause', 'DriveFault')]
    [string]$FaultType,

    [Parameter(Mandatory)]
    [string]$NodeName,

    [Parameter(Mandatory)]
    [string]$ComputerName,

    [Parameter()]
    [string]$DiskSerialNumber,

    [Parameter()]
    [ValidateSet('Retire', 'PnpDisable')]
    [string]$Method = 'Retire',

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [switch]$AllowFault,

    [Parameter()]
    [switch]$AcceptReducedRedundancy
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
Import-Module (Join-Path $ProjectRoot 'common\modules\FaultInjection\FaultInjection.psm1') -Force

$planParams = @{ FaultType = $FaultType; NodeName = $NodeName; ComputerName = $ComputerName; Method = $Method }
if ($DiskSerialNumber) { $planParams['DiskSerialNumber'] = $DiskSerialNumber }
$plan = New-FaultPlan @planParams

$injectParams = @{
    Plan                    = $plan
    ComputerName            = $ComputerName
    AllowFault              = $AllowFault
    AcceptReducedRedundancy = $AcceptReducedRedundancy
}
if ($Credential) { $injectParams['Credential'] = $Credential }
if ($WhatIfPreference) { $injectParams['WhatIf'] = $true }
if ($PSBoundParameters.ContainsKey('Confirm')) { $injectParams['Confirm'] = [bool]$PSBoundParameters['Confirm'] }

Invoke-FaultInjection @injectParams
