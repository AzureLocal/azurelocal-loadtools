# =============================================================================
# PSScriptAnalyzer.ps1 - Lint all PowerShell scripts
# =============================================================================
# Runs PSScriptAnalyzer across the entire project.
# Usage: pwsh -File tests/PSScriptAnalyzer.ps1
# =============================================================================

#Requires -Version 7.2

param(
    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [switch]$Fix
)

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'Installing PSScriptAnalyzer...' -ForegroundColor Yellow
    Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
}

Import-Module PSScriptAnalyzer

$scriptPaths = @(
    (Join-Path $ProjectRoot 'src')
    (Join-Path $ProjectRoot 'tests')
)

$excludeRules = @(
    'PSAvoidUsingConvertToSecureStringWithPlainText'  # Demo/template code
)

$totalIssues = 0

foreach ($path in $scriptPaths) {
    if (-not (Test-Path $path)) { continue }

    Write-Host "`nAnalyzing: $path" -ForegroundColor Cyan

    $params = @{
        Path        = $path
        Recurse     = $true
        ExcludeRule = $excludeRules
    }

    if ($Fix) {
        $params['Fix'] = $true
    }

    $results = Invoke-ScriptAnalyzer @params

    if ($results.Count -eq 0) {
        Write-Host "  No issues found." -ForegroundColor Green
    }
    else {
        $totalIssues += $results.Count
        $results | Group-Object -Property Severity | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Count) issues" -ForegroundColor $(
                switch ($_.Name) {
                    'Error'       { 'Red' }
                    'Warning'     { 'Yellow' }
                    'Information' { 'Cyan' }
                    default       { 'Gray' }
                }
            )
        }
        $results | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize
    }
}

Write-Host "`n===== Summary =====" -ForegroundColor Cyan
Write-Host "Total issues: $totalIssues" -ForegroundColor $(if ($totalIssues -eq 0) { 'Green' } else { 'Yellow' })

exit $(if ($totalIssues -gt 0) { 1 } else { 0 })
