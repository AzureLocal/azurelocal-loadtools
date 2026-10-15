# =============================================================================
# Invoke-Day2Smoke.ps1 - Azure Local Load Tools
# =============================================================================
# Optional readiness-gate step: a ~15 minute VMFleet "Day2Smoke" run (the General
# profile shortened to 2 min warm-up + 10 min measured), evaluated against the
# profile thresholds and, optionally, a baseline. Writes day2-smoke-result.json
# (schema: docs/reference/day2-smoke-result.schema.json) and exits:
#   0 Pass | 1 Fail (threshold or regression) | 2 Error (invalid/incomparable/run failed) | 3 Skipped (plan only)
# A gate must treat every non-zero exit code as "not passed".
#
#   Run + evaluate:        Invoke-Day2Smoke.ps1 -OutputPath out -FleetAdminCredential $c -NodeCount 4
#   Evaluate existing run: Invoke-Day2Smoke.ps1 -ResultPath reports\<run>\<run>-aggregate.json -OutputPath out -NodeCount 4
#   Plan only (default when -WhatIf): prints the pipeline command, runs nothing, exit 3.
#
# NOT PROVEN ON A LIVE CLUSTER. Running it deploys a fleet of VMs on the cluster.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$ResultPath,

    [Parameter()]
    [string]$BaselinePath,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [Parameter()]
    [ValidateRange(0, 64)]
    [int]$NodeCount = 0,

    [Parameter()]
    [string]$ProfilePath,

    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$SolutionConfigPath,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [PSCredential]$FleetAdminCredential,

    [Parameter()]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
$started = (Get-Date).ToUniversalTime()

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
if (-not $ProfilePath) { $ProfilePath = Join-Path $ProjectRoot 'tools\vmfleet\config\profiles\day2-smoke.yml' }

Import-Module (Join-Path $ProjectRoot 'common\modules\ResultAnalysis\ResultAnalysis.psm1') -Force

function Write-SmokeResult {
    param($Result, [string]$Dir)
    # The result file is the gate output: write it even under -WhatIf (plan only).
    $null = New-Item -ItemType Directory -Path $Dir -Force -WhatIf:$false
    $file = Join-Path $Dir 'day2-smoke-result.json'
    $Result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding utf8 -WhatIf:$false
    Write-Information "Day-2 smoke: $($Result.status) (exit $($Result.exit_code)) -> $file" -InformationAction Continue
}

try {
    Import-Module powershell-yaml -ErrorAction Stop
    $profileData = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Yaml
    $thresholds = @{}
    foreach ($k in $profileData.profile.expected_thresholds.Keys) { $thresholds[$k] = $profileData.profile.expected_thresholds[$k] }

    if (-not $NodeCount -and $ClusterConfigPath -and (Test-Path -LiteralPath $ClusterConfigPath)) {
        $cc = Get-Content -LiteralPath $ClusterConfigPath -Raw | ConvertFrom-Yaml
        $NodeCount = @($cc.nodes).Count
    }

    $runId = "day2smoke-$($started.ToString('yyyyMMdd-HHmmss'))"
    $pipeline = Join-Path $ProjectRoot 'tools\vmfleet\Invoke-VMFleetPipeline.ps1'

    if (-not $ResultPath) {
        $pipelineParams = @{ ProfilePath = $ProfilePath; RunId = $runId; ProjectRoot = $ProjectRoot; ReportFormats = @('XLSX') }
        if ($ClusterConfigPath) { $pipelineParams['ClusterConfigPath'] = $ClusterConfigPath }
        if ($SolutionConfigPath) { $pipelineParams['SolutionConfigPath'] = $SolutionConfigPath }
        if ($Credential) { $pipelineParams['Credential'] = $Credential }
        if ($FleetAdminCredential) { $pipelineParams['FleetAdminCredential'] = $FleetAdminCredential }

        if (-not $PSCmdlet.ShouldProcess($ProjectRoot, "Run the Day2Smoke pipeline (deploys a VM fleet): $pipeline -ProfilePath $ProfilePath -RunId $runId")) {
            $skip = New-Day2SmokeResult -Status Skipped -Message 'Plan only: the pipeline was not run.' -NodeCount $NodeCount -StartedAt $started -FinishedAt (Get-Date).ToUniversalTime()
            Write-SmokeResult $skip $OutputPath
            exit 3
        }
        & $pipeline @pipelineParams
        $ResultPath = Join-Path $ProjectRoot "reports\$runId\$runId-aggregate.json"
        if (-not (Test-Path -LiteralPath $ResultPath)) { throw "The pipeline finished but no aggregate result was found at $ResultPath." }
    }

    $evalParams = @{ Result = $ResultPath; Threshold = $thresholds; NodeCount = $NodeCount; StartedAt = $started; FinishedAt = (Get-Date).ToUniversalTime() }
    if ($BaselinePath) { $evalParams['Baseline'] = $BaselinePath }
    $result = New-Day2SmokeResult @evalParams
}
catch {
    $result = New-Day2SmokeResult -Status Error -Message $_.Exception.Message -NodeCount $NodeCount -StartedAt $started -FinishedAt (Get-Date).ToUniversalTime()
}

Write-SmokeResult $result $OutputPath
exit $result.exit_code
