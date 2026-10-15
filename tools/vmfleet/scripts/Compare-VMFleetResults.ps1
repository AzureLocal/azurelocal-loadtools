# =============================================================================
# Compare-VMFleetResults.ps1 - Azure Local Load Tools
# =============================================================================
# Regression gate: compares a candidate aggregate result with a baseline and
# exits 0 (no regression), 1 (regression beyond a threshold) or 2 (not
# comparable / invalid input). Offline: reads two JSON files, touches no cluster.
# Optionally writes the comparison as JSON and an HTML + CSV report.
#
#   pwsh tools/vmfleet/scripts/Compare-VMFleetResults.ps1 -BaselinePath base.json -CandidatePath new.json
#   echo $LASTEXITCODE
#
# See docs/tools/vmfleet/regression-gate.md. Not proven on a live cluster.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BaselinePath,

    [Parameter(Mandatory)]
    [string]$CandidatePath,

    [Parameter()]
    [ValidateRange(0, 99)]
    [double]$MaxDropPercent = 10,

    [Parameter()]
    [ValidateRange(0, 10000)]
    [double]$MaxRisePercent = 15,

    [Parameter()]
    [ValidateRange(0, 1000)]
    [double]$LatencySlackMs = 0.1,

    [Parameter()]
    [hashtable]$Threshold = @{},

    [Parameter()]
    [switch]$AllowMismatch,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

try {
    Import-Module (Join-Path $ProjectRoot 'common\modules\ResultAnalysis\ResultAnalysis.psm1') -Force

    if (-not (Test-Path -LiteralPath $BaselinePath) -or -not (Test-Path -LiteralPath $CandidatePath)) {
        throw 'Baseline or candidate file not found.'
    }
    $sameFile = ((Resolve-Path -LiteralPath $BaselinePath).Path -eq (Resolve-Path -LiteralPath $CandidatePath).Path) -or
    ((Get-FileHash -LiteralPath $BaselinePath).Hash -eq (Get-FileHash -LiteralPath $CandidatePath).Hash)
    if ($sameFile) { throw 'Baseline and candidate are the same file (or identical content): nothing to compare.' }

    $cmp = Compare-LoadTestResult -Baseline $BaselinePath -Candidate $CandidatePath -MaxDropPercent $MaxDropPercent `
        -MaxRisePercent $MaxRisePercent -LatencySlackMs $LatencySlackMs -Threshold $Threshold -AllowMismatch:$AllowMismatch

    if ($OutputPath) {
        $null = New-Item -ItemType Directory -Path $OutputPath -Force
        $cmp | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputPath 'comparison.json') -Encoding utf8
        $null = New-ResultReport -Result $CandidatePath -Baseline $BaselinePath -OutputPath $OutputPath -Threshold $Threshold
    }

    foreach ($row in $cmp.Metrics) {
        Write-Information ('{0,-28} {1,12} -> {2,12}  {3,8}%  {4}' -f $row.Metric, $row.Baseline, $row.Candidate, $row.ChangePercent, $row.Status) -InformationAction Continue
    }
    foreach ($n in $cmp.Notes) { Write-Information "NOTE: $n" -InformationAction Continue }
    Write-Information "Result: $($cmp.Status) (exit $($cmp.ExitCode))" -InformationAction Continue
    $cmp
    exit $cmp.ExitCode
}
catch {
    Write-Error "Comparison could not be completed: $($_.Exception.Message)" -ErrorAction Continue
    exit 2
}
