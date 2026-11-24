# =============================================================================
# Stop.node.ps1 - node-side payload of Stop-VMFleetTest.ps1
# =============================================================================
# Runs ON the first cluster node as a one-shot scheduled task (Windows PowerShell
# 5.1). See Install.node.ps1 for the wrapper contract.
#
# Stop-Fleet pauses the fleet and shuts the fleet VMs down.
# =============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The wrapper reads $StepResult after it ran this body.')]
param()

Import-Module -Name VMFleet -ErrorAction Stop

Stop-Fleet -ErrorAction Stop

$states = @(Get-FleetVM | ForEach-Object { [string]$_.State })
$StepResult = @{ VMs = $states.Count; States = $states }
