# =============================================================================
# New-VMFleetReport.ps1 - Azure Local Load Tools
# =============================================================================
# Offline HTML + CSV report from one aggregate result JSON (optionally compared
# with a baseline). No cluster, no asciidoctor, no Excel module needed.
# PDF / DOCX / XLSX reports are produced by the pipeline's ReportGenerator module
# when asciidoctor-pdf / pandoc / ImportExcel are installed.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResultPath,

    [Parameter()]
    [string]$BaselinePath,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [Parameter()]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
Import-Module (Join-Path $ProjectRoot 'common\modules\ResultAnalysis\ResultAnalysis.psm1') -Force

$params = @{ Result = $ResultPath; OutputPath = $OutputPath }
if ($BaselinePath) { $params['Baseline'] = $BaselinePath }
if ($WhatIfPreference) { $params['WhatIf'] = $true }
New-ResultReport @params
