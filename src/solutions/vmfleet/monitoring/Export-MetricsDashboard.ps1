# =============================================================================
# Export-MetricsDashboard.ps1 - Azure Local Load Tools
# =============================================================================
# Exports collected metrics into a dashboard-friendly format (HTML/JSON).
# =============================================================================

#Requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MetricsPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [ValidateSet('HTML', 'JSON')]
    [string]$Format = 'HTML',

    [Parameter()]
    [string]$RunId
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')

if (-not $RunId) { $RunId = "dashboard-$(Get-Timestamp -FilenameSafe)" }
if (-not $OutputPath) { $OutputPath = Join-Path $ProjectRoot "reports\$RunId" }
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# Aggregate metrics from all .jsonl files
$allMetrics = @()
$metricFiles = Get-ChildItem -Path $MetricsPath -Filter '*.jsonl' -Recurse

foreach ($file in $metricFiles) {
    $entries = Get-Content -Path $file.FullName | Where-Object { $_ -match '\S' } | ConvertFrom-Json
    $allMetrics += $entries
}

if ($allMetrics.Count -eq 0) {
    Write-Warning "No metrics found in $MetricsPath"
    return
}

# Group by counter name and compute aggregates
$grouped = $allMetrics | Group-Object -Property counter_name
$summaryData = foreach ($group in $grouped) {
    $values = $group.Group | ForEach-Object { $_.value } | Where-Object { $null -ne $_ -and $_ -is [double] -or $_ -is [int] }
    if ($values.Count -eq 0) { continue }

    [PSCustomObject]@{
        Counter  = $group.Name
        Samples  = $values.Count
        Average  = [math]::Round(($values | Measure-Object -Average).Average, 3)
        Min      = [math]::Round(($values | Measure-Object -Minimum).Minimum, 3)
        Max      = [math]::Round(($values | Measure-Object -Maximum).Maximum, 3)
        StdDev   = if ($values.Count -gt 1) {
            $avg = ($values | Measure-Object -Average).Average
            [math]::Round([math]::Sqrt(($values | ForEach-Object { [math]::Pow($_ - $avg, 2) } | Measure-Object -Average).Average), 3)
        } else { 0 }
    }
}

if ($Format -eq 'JSON') {
    $jsonFile = Join-Path $OutputPath "$RunId-dashboard.json"
    $summaryData | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonFile -Encoding UTF8
    Write-Host "Dashboard JSON exported: $jsonFile" -ForegroundColor Green
    return $jsonFile
}

# HTML dashboard
$htmlFile = Join-Path $OutputPath "$RunId-dashboard.html"

$tableRows = ($summaryData | ForEach-Object {
    "<tr><td>$($_.Counter)</td><td>$($_.Samples)</td><td>$($_.Average)</td><td>$($_.Min)</td><td>$($_.Max)</td><td>$($_.StdDev)</td></tr>"
}) -join "`n"

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Azure Local Load Test - Metrics Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 2rem; background: #f5f5f5; }
        h1 { color: #0078D4; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
        th { background: #0078D4; color: white; padding: 12px 16px; text-align: left; }
        td { padding: 10px 16px; border-bottom: 1px solid #e0e0e0; }
        tr:hover { background: #f0f6ff; }
        .meta { color: #666; margin-bottom: 1rem; }
    </style>
</head>
<body>
    <h1>Metrics Dashboard</h1>
    <p class="meta">Run: $RunId | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Metrics: $($summaryData.Count) counters | Samples: $($allMetrics.Count) total</p>
    <table>
        <thead>
            <tr><th>Counter</th><th>Samples</th><th>Average</th><th>Min</th><th>Max</th><th>Std Dev</th></tr>
        </thead>
        <tbody>
            $tableRows
        </tbody>
    </table>
</body>
</html>
"@

Set-Content -Path $htmlFile -Value $html -Encoding UTF8
Write-Host "Dashboard HTML exported: $htmlFile" -ForegroundColor Green
return $htmlFile
