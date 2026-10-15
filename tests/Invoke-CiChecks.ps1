# =============================================================================
# Invoke-CiChecks.ps1 - the same checks locally and in CI (.github/workflows/ci.yml)
# =============================================================================
#   pwsh -File tests/Invoke-CiChecks.ps1 -Check All
#   pwsh -File tests/Invoke-CiChecks.ps1 -Check Analyzer -MaxWarnings 50
#
# Analyzer: PSScriptAnalyzer with .psscriptanalyzer.psd1; fails on any Error and on
#           more than -MaxWarnings Warnings (the budget; the repo is at 0).
# Pester:   one process per *.Tests.ps1 (a hung or crashing suite cannot hide the others).
# Links:    relative Markdown links (tests/Test-MarkdownLinks.ps1), offline.
# Writes one JSON summary per check when -ResultPath is given.
# Exit code: 0 all checks passed, 1 at least one failed.
# =============================================================================

#Requires -Version 7.2
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'The parameters are read inside the check functions below (script scope); the analyzer does not follow that.')]
param(
    [Parameter()]
    [ValidateSet('Analyzer', 'Pester', 'Links', 'All')]
    [string]$Check = 'All',

    [Parameter()]
    [ValidateRange(0, 10000)]
    [int]$MaxWarnings = 50,

    [Parameter()]
    [string]$ResultPath,

    [Parameter()]
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$results = [System.Collections.Generic.List[object]]::new()

function Save-CheckResult {
    param([string]$Name, [bool]$Passed, [hashtable]$Detail)
    $obj = [ordered]@{ check = $Name; passed = $Passed } + $Detail
    $script:results.Add([pscustomobject]$obj)
    if ($ResultPath) { [pscustomobject]$obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ResultPath -Encoding utf8 }
    Write-Information ("{0}: {1}" -f $Name, $(if ($Passed) { 'PASS' } else { 'FAIL' })) -InformationAction Continue
}

function Invoke-AnalyzerCheck {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $settings = Join-Path $ProjectRoot '.psscriptanalyzer.psd1'
    $findings = @(Invoke-ScriptAnalyzer -Path $ProjectRoot -Recurse -Settings $settings |
            Where-Object { $_.ScriptPath -notmatch '[\\/](\.git|archive|node_modules)[\\/]' })
    $errors = @($findings | Where-Object Severity -EQ 'Error')
    $warnings = @($findings | Where-Object Severity -EQ 'Warning')
    foreach ($f in ($errors + $warnings | Select-Object -First 50)) {
        Write-Information ("{0}:{1} {2} {3}" -f $f.ScriptPath, $f.Line, $f.RuleName, $f.Message) -InformationAction Continue
    }
    $ok = ($errors.Count -eq 0 -and $warnings.Count -le $MaxWarnings)
    Save-CheckResult 'analyzer' $ok @{ errors = $errors.Count; warnings = $warnings.Count; max_warnings = $MaxWarnings }
}

function Invoke-PesterCheck {
    $suites = @(Get-ChildItem -Path $ProjectRoot -Recurse -Filter '*.Tests.ps1' -File |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|archive|node_modules)[\\/]' } | Sort-Object FullName)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($s in $suites) {
        $cmd = "Import-Module Pester -MinimumVersion 5.0; `$c = New-PesterConfiguration; `$c.Run.Path = '$($s.FullName -replace "'", "''")'; `$c.Run.PassThru = `$true; `$c.Output.Verbosity = 'Minimal'; `$r = Invoke-Pester -Configuration `$c; [pscustomobject]@{ total = `$r.TotalCount; passed = `$r.PassedCount; failed = `$r.FailedCount; skipped = `$r.SkippedCount } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) 'loadtools-pester-result.json'); if (`$r.FailedCount -gt 0) { exit 1 }"
        $tmp = Join-Path ([IO.Path]::GetTempPath()) 'loadtools-pester-result.json'
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        & pwsh -NoProfile -Command $cmd
        $code = $LASTEXITCODE
        $r = if (Test-Path -LiteralPath $tmp) { Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json } else { $null }
        $rows.Add([pscustomobject]@{
                suite   = $s.FullName.Substring($ProjectRoot.Length + 1)
                total   = $(if ($r) { $r.total } else { 0 })
                passed  = $(if ($r) { $r.passed } else { 0 })
                failed  = $(if ($r) { $r.failed } else { -1 })
                skipped = $(if ($r) { $r.skipped } else { 0 })
                exit    = $code
            })
    }
    $bad = @($rows | Where-Object { $_.exit -ne 0 -or $_.failed -ne 0 -or $_.total -eq 0 })
    Save-CheckResult 'pester' ($bad.Count -eq 0 -and $rows.Count -gt 0) @{
        suites       = $rows.Count
        tests_total  = [int](($rows | Measure-Object -Property total -Sum).Sum)
        tests_passed = [int](($rows | Measure-Object -Property passed -Sum).Sum)
        tests_failed = [int](($rows | Where-Object { $_.failed -gt 0 } | Measure-Object -Property failed -Sum).Sum)
        detail       = $rows.ToArray()
    }
}

function Invoke-LinksCheck {
    & pwsh -NoProfile -File (Join-Path $ProjectRoot 'tests\Test-MarkdownLinks.ps1') -ProjectRoot $ProjectRoot
    $linkExit = $LASTEXITCODE
    Save-CheckResult 'links' ($linkExit -eq 0) @{ exit = $linkExit }
}

if ($Check -in 'Analyzer', 'All') { Invoke-AnalyzerCheck }
if ($Check -in 'Pester', 'All') { Invoke-PesterCheck }
if ($Check -in 'Links', 'All') { Invoke-LinksCheck }

if ($ResultPath -and $Check -eq 'All') {
    $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ResultPath -Encoding utf8
}
$failed = @($results | Where-Object { -not $_.passed })
exit $(if ($failed.Count -gt 0) { 1 } else { 0 })
