# =============================================================================
# Test-MarkdownLinks.ps1 - Check relative links and anchors-free targets in Markdown
# =============================================================================
# Offline only: external (http/https/mailto) links are not fetched.
# Usage: pwsh -File tests/Test-MarkdownLinks.ps1
# Exit code: 0 when every relative link resolves, 1 otherwise.
# =============================================================================

#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter()]
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skipDirs = '[\\/](\.git|node_modules|archive|\.ai|styles)[\\/]'
$files = Get-ChildItem -Path $ProjectRoot -Recurse -Filter *.md -File |
    Where-Object { $_.FullName -notmatch $skipDirs }

$broken = [System.Collections.Generic.List[object]]::new()
$checked = 0
$linkPattern = '(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)|!\[[^\]]*\]\(([^)\s]+)\)'

foreach ($file in $files) {
    $inFence = $false
    $lineNo = 0
    foreach ($line in (Get-Content -Path $file.FullName)) {
        $lineNo++
        if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        $clean = [regex]::Replace($line, '`[^`]*`', '')
        foreach ($m in [regex]::Matches($clean, $linkPattern)) {
            $target = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            if ($target -match '^(https?:|mailto:|#|tel:)') { continue }
            $path = ($target -split '#')[0]
            if (-not $path) { continue }
            $path = [uri]::UnescapeDataString($path)
            $checked++
            $base = if ($path.StartsWith('/')) { Join-Path $ProjectRoot 'docs' } else { $file.DirectoryName }
            $full = Join-Path $base $path.TrimStart('/')
            if (-not (Test-Path -LiteralPath $full)) {
                $broken.Add([pscustomobject]@{
                        File   = $file.FullName.Substring($ProjectRoot.Length + 1)
                        Line   = $lineNo
                        Target = $target
                    })
            }
        }
    }
}

Write-Information "Checked $checked relative links in $($files.Count) files." -InformationAction Continue
if ($broken.Count -gt 0) {
    $broken | Format-Table -AutoSize | Out-String | Write-Information -InformationAction Continue
    Write-Error "$($broken.Count) broken link(s)."
    exit 1
}
exit 0
