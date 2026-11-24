# =============================================================================
# Collect.node.ps1 - node-side payload of Collect-VMFleetResults.ps1
# =============================================================================
# Runs ON the first cluster node as a one-shot scheduled task (Windows PowerShell
# 5.1). See Install.node.ps1 for the wrapper contract.
#
# Every fleet VM leaves one DiskSpd XML result (-Rxml) in the Collect volume's
# result folder; the sweep tag is part of the file name. This reduces each file to
# IOPS, bytes per second and average latency, the way VMFleet itself does.
# =============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The wrapper reads $StepResult after it ran this body.')]
param()

Import-Module -Name VMFleet -ErrorAction Stop

$tag = [string](Get-Arg 'Tag' '')
$collectPath = [string](Get-Arg 'CollectPath' '')
if (-not $tag -and $collectPath) {
    $markerFile = Join-Path (Join-Path $collectPath 'loadtools') 'last-test.json'
    if (Test-Path -LiteralPath $markerFile) { $tag = [string]((Get-Content -LiteralPath $markerFile -Raw | ConvertFrom-Json).Tag) }
}
if (-not $tag) { throw 'No sweep tag: pass the run id of the test, or run Start-VMFleetTest.ps1 first.' }

$resultDir = Get-FleetPath -PathType Result
$files = @(Get-ChildItem -LiteralPath $resultDir -Filter ('result-*' + $tag + '*.xml') -File -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) { throw "No DiskSpd result files for tag $tag in $resultDir." }

function Get-Sum {
    param($Nodes, [string]$Name)
    $sum = 0.0
    foreach ($n in @($Nodes)) { $sum += [double]$n.$Name }
    return $sum
}

$rows = @()
foreach ($file in $files) {
    $xml = [xml](Get-Content -LiteralPath $file.FullName -Raw)
    $timeSpan = @($xml.SelectNodes('/Results/TimeSpan'))
    $targets = @($xml.SelectNodes('/Results/TimeSpan/Thread/Target'))
    if ($timeSpan.Count -eq 0 -or $targets.Count -eq 0) { throw "The result file has no DiskSpd target data (the load failed in the VM): $($file.Name)" }
    $seconds = Get-Sum $timeSpan 'TestTimeSeconds'
    if ($seconds -le 0) { throw "The result file reports no test time: $($file.Name)" }
    $readLatency = 0.0
    $writeLatency = 0.0
    $latencyNode = $xml.SelectSingleNode('/Results/TimeSpan/Latency')
    if ($latencyNode) {
        $readNode = $latencyNode.SelectSingleNode('AverageReadMilliseconds')
        $writeNode = $latencyNode.SelectSingleNode('AverageWriteMilliseconds')
        if ($readNode) { $readLatency = [double]$readNode.InnerText }
        if ($writeNode) { $writeLatency = [double]$writeNode.InnerText }
    }
    $vmName = $file.BaseName
    $at = $vmName.IndexOf($tag)
    if ($at -ge 0) { $vmName = $vmName.Substring($at + $tag.Length).TrimStart('-') }
    if (-not $vmName) { $vmName = $file.BaseName }
    $rows += @{
        VMName              = $vmName
        ReadIOPS            = (Get-Sum $targets 'ReadCount') / $seconds
        WriteIOPS           = (Get-Sum $targets 'WriteCount') / $seconds
        ReadBytesPerSecond  = (Get-Sum $targets 'ReadBytes') / $seconds
        WriteBytesPerSecond = (Get-Sum $targets 'WriteBytes') / $seconds
        ReadLatencyMs       = $readLatency
        WriteLatencyMs      = $writeLatency
    }
}

$StepResult = @{ Tag = $tag; ResultDirectory = $resultDir; Files = $files.Count; VMs = $rows }
