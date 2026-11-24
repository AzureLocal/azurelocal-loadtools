# =============================================================================
# Remove.node.ps1 - node-side payload of Remove-VMFleet.ps1
# =============================================================================
# Runs ON the first cluster node as a one-shot scheduled task (Windows PowerShell
# 5.1). See Install.node.ps1 for the wrapper contract.
#
# Remove-Fleet (no -VMs) removes every fleet VM and its cluster role on every node,
# the VM folders on the node volumes, the flag files and the FleetInternal vSwitch.
# Afterwards this checks that no vm-* VM and no vm-* folder is left, and optionally
# deletes the DiskSpd result files from the Collect volume.
# =============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The wrapper reads $StepResult after it ran this body.')]
param()

Import-Module -Name VMFleet -ErrorAction Stop

try {
    Stop-Fleet -ErrorAction Stop
} catch {
    Write-Host "Stop-Fleet reported: $($_.Exception.Message) (continuing with removal)"
}

Remove-Fleet -ErrorAction Stop

$remainingVMs = @(Get-FleetVM | ForEach-Object { [string]$_.Name })

$remainingDirectories = @()
foreach ($csv in @(Get-ClusterSharedVolume)) {
    $root = $csv.SharedVolumeInfo.FriendlyVolumeName
    $remainingDirectories += @(Get-ChildItem -LiteralPath $root -Directory -Filter 'vm-*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
}

$removedResults = 0
if (Get-Arg 'RemoveCollectData' $false) {
    $resultDir = Get-FleetPath -PathType Result
    $old = @(Get-ChildItem -LiteralPath $resultDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'result-*.xml' -or $_.Name -like 'perfctr-*.blg' })
    foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force }
    $removedResults = $old.Count
    Write-Host "Removed $removedResults result files from $resultDir"
}

$StepResult = @{ RemainingVMs = $remainingVMs; RemainingDirectories = $remainingDirectories; RemovedResultFiles = $removedResults }
