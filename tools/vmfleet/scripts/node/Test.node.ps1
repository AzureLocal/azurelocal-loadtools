# =============================================================================
# Test.node.ps1 - node-side payload of Start-VMFleetTest.ps1
# =============================================================================
# Runs ON the first cluster node as a one-shot scheduled task (Windows PowerShell
# 5.1). See Install.node.ps1 for the wrapper contract.
#
# Start-FleetSweep runs DiskSpd inside every fleet VM and BLOCKS until the run is
# finished (duration + warm-up + cool-down plus about a minute of overhead). -b is
# the block size in KB, -t threads, -o outstanding I/O, -w write percentage,
# -p r (random) or s (sequential), -d the measured seconds, -Warm and -Cool the
# DiskSpd warm-up and cool-down. -AddSpec puts a unique tag in every result file
# name so a repeated run never reuses an old result ("already done").
# =============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The wrapper reads $StepResult after it ran this body.')]
param()

Import-Module -Name VMFleet -ErrorAction Stop

$tag = [string](Get-Arg 'Tag' '')
if (-not $tag) { throw 'Tag is empty; it labels the result files of this run.' }

$vms = @(Get-FleetVM)
$ok = @($vms | Where-Object { $_.State -eq 'Ok' })
if ($vms.Count -eq 0 -or $ok.Count -ne $vms.Count) {
    throw "The fleet is not ready: $($ok.Count) of $($vms.Count) VMs are Ok. Run Deploy-VMFleet.ps1 first."
}

$collectPath = [string](Get-Arg 'CollectPath' '')
if ($collectPath) {
    $marker = @{
        RunId   = [string](Get-Arg 'RunId' '')
        Tag     = $tag
        Started = (Get-Date).ToUniversalTime().ToString('o')
        Profile = [string](Get-Arg 'ProfileName' '')
        VMs     = $vms.Count
    }
    $markerDir = Join-Path $collectPath 'loadtools'
    if (-not (Test-Path -LiteralPath $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
    $marker | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $markerDir 'last-test.json') -Encoding UTF8
}

$sweep = @{
    b       = [int](Get-Arg 'BlockSizeKB' 8)
    t       = [int](Get-Arg 'Threads' 2)
    o       = [int](Get-Arg 'OutstandingIO' 8)
    w       = [int](Get-Arg 'WriteRatio' 30)
    p       = [string](Get-Arg 'Pattern' 'r')
    d       = [int](Get-Arg 'DurationSeconds' 300)
    Warm    = [int](Get-Arg 'WarmupSeconds' 60)
    Cool    = [int](Get-Arg 'CooldownSeconds' 30)
    AddSpec = $tag
}
Write-Host ('Start-FleetSweep ' + (($sweep.GetEnumerator() | Sort-Object Name | ForEach-Object { '-' + $_.Name + ' ' + $_.Value }) -join ' '))
Start-FleetSweep @sweep -ErrorAction Stop

$StepResult = @{ Tag = $tag; VMs = $vms.Count; Finished = (Get-Date).ToUniversalTime().ToString('o') }
