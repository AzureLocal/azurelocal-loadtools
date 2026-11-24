# =============================================================================
# Deploy.node.ps1 - node-side payload of Deploy-VMFleet.ps1
# =============================================================================
# Runs ON the first cluster node as a one-shot scheduled task (Windows PowerShell
# 5.1). See Install.node.ps1 for the wrapper contract.
#
# New-Fleet creates the fleet VMs (-VMs is PER NODE) from the base VHD on the
# node's own CSV and specializes each copy with the local administrator password
# (-AdminPass) and the account the VMs use to reach the Collect volume
# (-ConnectUser / -ConnectPass, an admin on every node). Set-Fleet sizes the VMs
# (they must be Off), Start-Fleet starts them, and Get-FleetVM reports State
# 'Ok' once the heartbeat is up. Passwords come in through $Secrets only.
# =============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The wrapper reads $StepResult after it ran this body.')]
param()

Import-Module -Name VMFleet -ErrorAction Stop

$baseVhd = [string](Get-Arg 'BaseVhdPath' '')
if (-not $baseVhd) { throw 'BaseVhdPath is empty. Set storage.base_vhd_path in the cluster YAML, base_vhd_path in vmfleet.json or pass -BaseVHDPath.' }
if (-not (Test-Path -LiteralPath $baseVhd)) { throw "The base VHD was not found on the node: $baseVhd" }

$vmsPerNode = [int](Get-Arg 'VMsPerNode' 0)
if ($vmsPerNode -lt 1) { throw 'VMsPerNode must be at least 1.' }
$expected = [int](Get-Arg 'ExpectedVMs' $vmsPerNode)
$admin = [string](Get-Arg 'Admin' 'Administrator')
$connectUser = [string](Get-Arg 'ConnectUser' '')
$adminPass = [string]$Secrets['FleetAdminPassword']
$connectPass = [string]$Secrets['ConnectPassword']
if (-not $adminPass) { throw 'The fleet administrator password did not arrive (FleetAdminCredential is required).' }
if (-not $connectUser -or -not $connectPass) { throw 'The connect account did not arrive (-Credential or -FleetConnectCredential is required).' }

$current = @(Get-FleetVM)
$okNow = @($current | Where-Object { $_.State -eq 'Ok' })
if ($current.Count -ge $expected -and $okNow.Count -eq $current.Count) {
    Write-Host "The fleet already has $($current.Count) VMs, all Ok; nothing to deploy"
    $StepResult = @{ AlreadyDeployed = $true; VMsExpected = $expected; VMsOk = $okNow.Count }
} else {
    Write-Host "Creating $vmsPerNode VMs per node from $baseVhd"
    New-Fleet -BaseVHD $baseVhd -VMs $vmsPerNode -Admin $admin -AdminPass $adminPass -ConnectUser $connectUser -ConnectPass $connectPass -ErrorAction Stop

    $cpu = [int](Get-Arg 'ProcessorCount' 0)
    $memory = [int64](Get-Arg 'MemoryStartupBytes' 0)
    if ($cpu -gt 0 -and $memory -gt 0) {
        Write-Host "Sizing the fleet VMs: $cpu vCPU, $memory bytes static memory"
        Set-Fleet -ProcessorCount $cpu -MemoryStartupBytes $memory -ErrorAction Stop
    }

    Write-Host 'Starting the fleet VMs'
    Start-Fleet -ErrorAction Stop

    $waitMinutes = [int](Get-Arg 'WaitMinutes' 30)
    $deadline = (Get-Date).AddMinutes($waitMinutes)
    do {
        Start-Sleep -Seconds 30
        $vms = @(Get-FleetVM)
        $ok = @($vms | Where-Object { $_.State -eq 'Ok' }).Count
        Write-Host "Fleet VMs Ok: $ok of $expected ($($vms.Count) exist)"
    } while ($ok -lt $expected -and (Get-Date) -lt $deadline)

    if ($ok -lt $expected) {
        throw "Only $ok of $expected fleet VMs reached state Ok within $waitMinutes minutes."
    }
    $StepResult = @{ AlreadyDeployed = $false; VMsExpected = $expected; VMsOk = $ok }
}
