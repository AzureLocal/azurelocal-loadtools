# =============================================================================
# ResultAnalysis.psm1 - Azure Local Load Tools
# =============================================================================
# Offline result handling: normalise a load-test result (VMFleet aggregate JSON
# in either the collector shape or the sample "results" shape), render an HTML +
# CSV report, compare two result sets with a regression threshold, and show a
# trend over several runs. No cluster, no network, no module beyond PowerShell 7.
#
# Gate semantics (Compare-LoadTestResult):
#   exit 0 = no regression, 1 = regression beyond a threshold, 2 = not comparable / invalid input.
# A gate that cannot compare must never report success: missing gated metrics,
# non-numeric or negative values, and a profile / VM count / parameter mismatch
# are exit 2, not 0.
#
# Reports and comparisons are only as good as the input; they are tested on
# fixtures, not proven on hardware.
# =============================================================================

#Requires -Version 7.2

Set-StrictMode -Version Latest

# Direction: 'Higher' = bigger is better, 'Lower' = smaller is better.
$script:MetricDefinitions = [ordered]@{
    total_iops                  = @{ Direction = 'Higher'; Gated = $true; Unit = 'IOPS'; Required = $true }
    total_read_iops             = @{ Direction = 'Higher'; Gated = $false; Unit = 'IOPS'; Required = $false }
    total_write_iops            = @{ Direction = 'Higher'; Gated = $false; Unit = 'IOPS'; Required = $false }
    total_throughput_mbps       = @{ Direction = 'Higher'; Gated = $true; Unit = 'MB/s'; Required = $true }
    total_read_throughput_mbps  = @{ Direction = 'Higher'; Gated = $false; Unit = 'MB/s'; Required = $false }
    total_write_throughput_mbps = @{ Direction = 'Higher'; Gated = $false; Unit = 'MB/s'; Required = $false }
    avg_latency_ms              = @{ Direction = 'Lower'; Gated = $true; Unit = 'ms'; Required = $true }
    avg_read_latency_ms         = @{ Direction = 'Lower'; Gated = $false; Unit = 'ms'; Required = $false }
    avg_write_latency_ms        = @{ Direction = 'Lower'; Gated = $false; Unit = 'ms'; Required = $false }
    p95_latency_ms              = @{ Direction = 'Lower'; Gated = $true; Unit = 'ms'; Required = $false }
    p99_latency_ms              = @{ Direction = 'Lower'; Gated = $true; Unit = 'ms'; Required = $false }
}

function Get-ResultMetricDefinition {
    <#
    .SYNOPSIS
        Returns the metric table (direction, gated, unit, required) used by the report and the gate.
    #>
    [CmdletBinding()]
    param()
    $script:MetricDefinitions
}

function ConvertTo-NormalizedResult {
    <#
    .SYNOPSIS
        Reads one aggregate result JSON (file or object) into a flat, validated result object.
    .DESCRIPTION
        Accepts the shape the VMFleet collector writes (metrics at the top level) and the sample shape
        (metrics under "results"). Numbers must be finite and not negative; anything else throws, so the
        gate reports "invalid input" instead of comparing garbage. total_throughput_mbps is derived from
        read + write when absent.
    .PARAMETER Path
        Path to an aggregate JSON file.
    .PARAMETER InputObject
        An already parsed object.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Object', ValueFromPipeline)][object]$InputObject
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Result file not found: $Path" }
            try { $InputObject = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20 }
            catch { throw "Result file is not valid JSON: $Path ($($_.Exception.Message))" }
        }
        if ($null -eq $InputObject) { throw 'Empty result.' }

        $source = $InputObject
        $hasResultsBlock = $InputObject.PSObject.Properties['results'] -and $null -ne $InputObject.results -and $InputObject.results -isnot [string]
        $metricsSource = if ($hasResultsBlock) { $InputObject.results } else { $InputObject }

        $metrics = [ordered]@{}
        foreach ($name in $script:MetricDefinitions.Keys) {
            $prop = $metricsSource.PSObject.Properties[$name]
            if ($prop -and $null -ne $prop.Value) {
                $raw = $prop.Value
                $num = 0.0
                if ($raw -is [bool] -or -not [double]::TryParse([string]::Format([cultureinfo]::InvariantCulture, '{0}', $raw), [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$num)) {
                    throw "Metric '$name' is not a number: '$raw'."
                }
                if ([double]::IsNaN($num) -or [double]::IsInfinity($num) -or $num -lt 0) { throw "Metric '$name' is not a finite non-negative number: '$raw'." }
                $metrics[$name] = $num
            }
        }
        if (-not $metrics.Contains('total_throughput_mbps') -and $metrics.Contains('total_read_throughput_mbps') -and $metrics.Contains('total_write_throughput_mbps')) {
            $metrics['total_throughput_mbps'] = $metrics['total_read_throughput_mbps'] + $metrics['total_write_throughput_mbps']
        }
        if (-not $metrics.Contains('total_iops') -and $metrics.Contains('total_read_iops') -and $metrics.Contains('total_write_iops')) {
            $metrics['total_iops'] = $metrics['total_read_iops'] + $metrics['total_write_iops']
        }
        if ($metrics.Count -eq 0) { throw 'No known metrics found in the result.' }

        $get = {
            param($o, $n, $d)
            $p = $o.PSObject.Properties[$n]
            if ($p -and $null -ne $p.Value) { $p.Value } else { $d }
        }
        $params = $null
        foreach ($n in 'parameters', 'test_parameters') {
            $p = $source.PSObject.Properties[$n]
            if ($p -and $null -ne $p.Value) { $params = $p.Value; break }
        }
        $perNode = @()
        $pn = $source.PSObject.Properties['per_node_summary']
        if ($pn -and $pn.Value) { $perNode = @($pn.Value) }

        [pscustomobject]@{
            RunId       = [string](& $get $source 'run_id' '')
            Timestamp   = [string](& $get $source 'timestamp' '')
            ClusterName = [string](& $get $source 'cluster_name' '')
            ProfileName = [string](& $get $source 'profile_name' '')
            VmCount     = [int](& $get $source 'vm_count' 0)
            Parameters  = $params
            Metrics     = $metrics
            PerNode     = $perNode
        }
    }
}

function Test-ResultComparable {
    <#
    .SYNOPSIS
        Returns the reasons two results must not be compared (empty = comparable).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Baseline,
        [Parameter(Mandatory)][pscustomobject]$Candidate
    )
    $why = [System.Collections.Generic.List[string]]::new()
    if ($Baseline.RunId -and $Baseline.RunId -eq $Candidate.RunId) { $why.Add("baseline and candidate are the same run ('$($Baseline.RunId)')") }
    if ($Baseline.ClusterName -and $Candidate.ClusterName -and $Baseline.ClusterName -ne $Candidate.ClusterName) { $why.Add("cluster differs ('$($Baseline.ClusterName)' vs '$($Candidate.ClusterName)')") }
    if ($Baseline.ProfileName -ne $Candidate.ProfileName) { $why.Add("profile differs ('$($Baseline.ProfileName)' vs '$($Candidate.ProfileName)')") }
    if ($Baseline.VmCount -ne $Candidate.VmCount) { $why.Add("VM count differs ($($Baseline.VmCount) vs $($Candidate.VmCount))") }
    if (($null -eq $Baseline.Parameters) -ne ($null -eq $Candidate.Parameters)) {
        $why.Add('workload parameters are recorded on one side only')
    }
    elseif ($Baseline.Parameters -and $Candidate.Parameters) {
        foreach ($k in 'block_size', 'write_ratio', 'random_ratio', 'outstanding_io', 'threads_per_vm', 'duration_seconds', 'warmup_seconds') {
            $b = $Baseline.Parameters.PSObject.Properties[$k]
            $c = $Candidate.Parameters.PSObject.Properties[$k]
            if (($null -eq $b) -ne ($null -eq $c)) { $why.Add("parameter $k is recorded on one side only") }
            elseif ($b -and "$($b.Value)" -ne "$($c.Value)") { $why.Add("parameter $k differs ($($b.Value) vs $($c.Value))") }
        }
    }
    , $why.ToArray()
}

function Compare-LoadTestResult {
    <#
    .SYNOPSIS
        Compares a candidate result with a baseline and applies a regression threshold.
    .DESCRIPTION
        For each gated metric: higher-is-better metrics (IOPS, throughput) fail when they drop by more than
        MaxDropPercent; lower-is-better metrics (latency) fail when they rise by more than MaxRisePercent plus
        LatencySlackMs. Per-metric overrides come from -Threshold (metric name -> percent). A required gated
        metric missing on either side is 'Missing' and fails the comparison as not comparable (exit 2).
        Exit code: 0 = Pass, 1 = Regression, 2 = NotComparable (invalid input, mismatch, missing metric).
    .PARAMETER Baseline
        Normalised result (ConvertTo-NormalizedResult) or a path.
    .PARAMETER Candidate
        Normalised result or a path.
    .PARAMETER MaxDropPercent
        Allowed drop for higher-is-better metrics (default 10).
    .PARAMETER MaxRisePercent
        Allowed rise for lower-is-better metrics (default 15).
    .PARAMETER LatencySlackMs
        Absolute latency noise allowance added to the rise limit (default 0.1 ms).
    .PARAMETER Threshold
        Per-metric percent override, for example @{ total_iops = 5; p99_latency_ms = 30 }.
    .PARAMETER AllowMismatch
        Compare even when profile, VM count or parameters differ (the mismatch is still listed).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Baseline,
        [Parameter(Mandatory)][object]$Candidate,
        [ValidateRange(0, 99)][double]$MaxDropPercent = 10,
        [ValidateRange(0, 10000)][double]$MaxRisePercent = 15,
        [ValidateRange(0, 1000)][double]$LatencySlackMs = 0.1,
        [hashtable]$Threshold = @{},
        [switch]$AllowMismatch
    )

    $notes = [System.Collections.Generic.List[string]]::new()
    try {
        if ($Baseline -is [string]) { $Baseline = ConvertTo-NormalizedResult -Path $Baseline }
        if ($Candidate -is [string]) { $Candidate = ConvertTo-NormalizedResult -Path $Candidate }
    }
    catch {
        return [pscustomobject]@{ Status = 'NotComparable'; ExitCode = 2; Metrics = @(); Notes = @($_.Exception.Message); BaselineRunId = ''; CandidateRunId = '' }
    }
    foreach ($k in $Threshold.Keys) {
        if (-not $script:MetricDefinitions.Contains($k)) { return [pscustomobject]@{ Status = 'NotComparable'; ExitCode = 2; Metrics = @(); Notes = @("Unknown metric in -Threshold: $k"); BaselineRunId = $Baseline.RunId; CandidateRunId = $Candidate.RunId } }
        $v = [double]$Threshold[$k]
        $cap = if ($script:MetricDefinitions[$k].Direction -eq 'Higher') { 99 } else { 10000 }
        if ([double]::IsNaN($v) -or $v -lt 0 -or $v -gt $cap) { return [pscustomobject]@{ Status = 'NotComparable'; ExitCode = 2; Metrics = @(); Notes = @("Invalid -Threshold value for $k"); BaselineRunId = $Baseline.RunId; CandidateRunId = $Candidate.RunId } }
    }

    $mismatch = Test-ResultComparable -Baseline $Baseline -Candidate $Candidate
    $blocked = ($mismatch.Count -gt 0 -and -not $AllowMismatch)
    foreach ($m in $mismatch) { $notes.Add("Not comparable: $m") }

    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    $anyRegression = $false
    $anyMissing = $false
    foreach ($name in $script:MetricDefinitions.Keys) {
        $def = $script:MetricDefinitions[$name]
        if (-not $def.Gated -and -not $Threshold.ContainsKey($name)) { continue }
        $hasB = $Baseline.Metrics.Contains($name)
        $hasC = $Candidate.Metrics.Contains($name)
        if (-not $hasB -and -not $hasC -and -not $def.Required) { continue }
        $b = if ($hasB) { [double]$Baseline.Metrics[$name] } else { $null }
        $c = if ($hasC) { [double]$Candidate.Metrics[$name] } else { $null }
        $limit = if ($Threshold.ContainsKey($name)) { [double]$Threshold[$name] } elseif ($def.Direction -eq 'Higher') { $MaxDropPercent } else { $MaxRisePercent }

        if ($null -eq $b -or $null -eq $c) {
            $status = if ($def.Required -or ($hasB -and -not $hasC)) { 'Missing' } else { 'Skipped' }
            if ($status -eq 'Missing') { $anyMissing = $true }
            $rows.Add([pscustomobject]@{ Metric = $name; Unit = $def.Unit; Direction = $def.Direction; Baseline = $b; Candidate = $c; ChangePercent = $null; LimitPercent = $limit; Status = $status })
            continue
        }

        if ($def.Direction -eq 'Higher' -and $name -in 'total_iops', 'total_throughput_mbps' -and $b -eq 0) {
            $notes.Add("Baseline $name is 0: the baseline performed no useful I/O, so it cannot be a reference.")
            $anyMissing = $true
            $rows.Add([pscustomobject]@{ Metric = $name; Unit = $def.Unit; Direction = $def.Direction; Baseline = $b; Candidate = $c; ChangePercent = $null; LimitPercent = $limit; Status = 'Missing' })
            continue
        }
        $change = $null
        if ($b -ne 0) { $change = [math]::Round((($c - $b) / $b) * 100, 2) }
        elseif ($c -eq 0) { $change = 0.0 }

        if ($def.Direction -eq 'Higher') {
            $floor = $b * (1 - $limit / 100)
            $bad = ($c -lt $floor)
            $better = ($c -gt $b)
        }
        else {
            $ceiling = $b * (1 + $limit / 100) + $LatencySlackMs
            if ([double]::IsInfinity($ceiling) -or [double]::IsNaN($ceiling)) {
                $notes.Add("The limit for $name overflowed; the value is not credible.")
                $anyMissing = $true
                $rows.Add([pscustomobject]@{ Metric = $name; Unit = $def.Unit; Direction = $def.Direction; Baseline = $b; Candidate = $c; ChangePercent = $null; LimitPercent = $limit; Status = 'Missing' })
                continue
            }
            $bad = ($c -gt $ceiling)
            $better = ($c -lt $b)
        }
        $status = if ($bad) { 'Regression' } elseif ($better) { 'Improved' } else { 'Pass' }
        if ($bad) { $anyRegression = $true }
        $rows.Add([pscustomobject]@{ Metric = $name; Unit = $def.Unit; Direction = $def.Direction; Baseline = $b; Candidate = $c; ChangePercent = $change; LimitPercent = $limit; Status = $status })
    }

    if ($anyMissing) { $notes.Add('A required gated metric is missing or unusable; the comparison cannot pass.') }
    $final = if ($blocked -or $anyMissing) { 'NotComparable' } elseif ($anyRegression) { 'Regression' } else { 'Pass' }
    $exit = switch ($final) { 'Pass' { 0 } 'Regression' { 1 } default { 2 } }

    [pscustomobject]@{
        Status         = $final
        ExitCode       = $exit
        BaselineRunId  = $Baseline.RunId
        CandidateRunId = $Candidate.RunId
        Metrics        = $rows.ToArray()
        Notes          = $notes.ToArray()
    }
}

function Get-ResultTrend {
    <#
    .SYNOPSIS
        Lines several result files up in time order and compares each run with the previous one.
    .DESCRIPTION
        Returns one row per run (timestamp order; files without a timestamp sort last by name) with the gated
        metrics and the Compare-LoadTestResult status against the previous run.
    .PARAMETER Path
        Aggregate JSON files.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param([Parameter(Mandatory)][string[]]$Path)

    $items = foreach ($p in $Path) {
        $r = ConvertTo-NormalizedResult -Path $p
        $ts = [datetime]::MinValue
        $ok = [datetime]::TryParse($r.Timestamp, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$ts)
        [pscustomobject]@{ Path = $p; Result = $r; Time = $(if ($ok) { $ts } else { [datetime]::MaxValue }) }
    }
    $sorted = @($items | Sort-Object -Property Time, Path)
    $prev = $null
    foreach ($i in $sorted) {
        $status = 'First'
        if ($prev) { $status = (Compare-LoadTestResult -Baseline $prev.Result -Candidate $i.Result).Status }
        [pscustomobject]@{
            RunId               = $i.Result.RunId
            Timestamp           = $i.Result.Timestamp
            TotalIops           = $i.Result.Metrics['total_iops']
            TotalThroughputMBps = $i.Result.Metrics['total_throughput_mbps']
            AvgLatencyMs        = $i.Result.Metrics['avg_latency_ms']
            VersusPrevious      = $status
        }
        $prev = $i
    }
}

function ConvertTo-SafeCsvCell {
    # Neutralise spreadsheet formula injection in free-text cells.
    param([string]$Text)
    if ($Text -match '^[=+\-@\t\r]') { return "'" + $Text }
    $Text
}

function New-ResultReport {
    <#
    .SYNOPSIS
        Writes a self-contained HTML report and a CSV file for one result (optionally against a baseline).
    .DESCRIPTION
        HTML: no scripts, no external resources, every value HTML-encoded. CSV: one row per metric
        (and per node when present); text cells that start with = + - @ are prefixed so a spreadsheet
        does not evaluate them. PDF/XLSX/DOCX stay with the ReportGenerator module (asciidoctor-pdf, ImportExcel).
    .PARAMETER Result
        Normalised result or a path.
    .PARAMETER Baseline
        Optional normalised baseline or path; adds the comparison columns.
    .PARAMETER OutputPath
        Output directory (created).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [object]$Baseline,
        [Parameter(Mandatory)][string]$OutputPath,
        [hashtable]$Threshold = @{}
    )
    if ($Result -is [string]) { $Result = ConvertTo-NormalizedResult -Path $Result }
    if ($Baseline -is [string]) { $Baseline = ConvertTo-NormalizedResult -Path $Baseline }
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }

    $comparison = $null
    if ($Baseline) { $comparison = Compare-LoadTestResult -Baseline $Baseline -Candidate $Result -Threshold $Threshold -AllowMismatch }

    $safeId = ($Result.RunId -replace '[^A-Za-z0-9._-]', '_')
    if (-not $safeId) { $safeId = 'result' }
    $htmlPath = Join-Path $OutputPath "$safeId-report.html"
    $csvPath = Join-Path $OutputPath "$safeId-metrics.csv"

    $rows = foreach ($name in $script:MetricDefinitions.Keys) {
        if (-not $Result.Metrics.Contains($name)) { continue }
        $cmp = if ($comparison) { @($comparison.Metrics | Where-Object { $_.Metric -eq $name }) | Select-Object -First 1 } else { $null }
        [pscustomobject]@{
            Metric        = $name
            Unit          = $script:MetricDefinitions[$name].Unit
            Value         = $Result.Metrics[$name]
            Baseline      = $(if ($Baseline -and $Baseline.Metrics.Contains($name)) { $Baseline.Metrics[$name] } else { $null })
            ChangePercent = $(if ($cmp) { $cmp.ChangePercent } else { $null })
            Status        = $(if ($cmp) { $cmp.Status } else { '' })
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">')
    $null = $sb.AppendLine("<title>Load test report $(& $enc $Result.RunId)</title>")
    $null = $sb.AppendLine('<style>:root{--bg:#fff;--fg:#1b1b1b;--mut:#5a5a5a;--line:#d0d0d0;--bad:#b00020;--good:#0a6b2b}@media (prefers-color-scheme:dark){:root{--bg:#161616;--fg:#eee;--mut:#aaa;--line:#444;--bad:#ff6b81;--good:#5fd38d}}body{background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;margin:0 auto;padding:16px;max-width:960px}table{border-collapse:collapse;width:100%;margin:12px 0}th,td{border:1px solid var(--line);padding:6px 10px;text-align:left}td.n{text-align:right;font-variant-numeric:tabular-nums}.Regression,.Missing{color:var(--bad);font-weight:600}.Pass,.Improved{color:var(--good)}.note{color:var(--mut)}</style></head><body>')
    $null = $sb.AppendLine("<h1>Load test report</h1><p class=""note"">Run $(& $enc $Result.RunId) &middot; profile $(& $enc $Result.ProfileName) &middot; cluster $(& $enc $Result.ClusterName) &middot; $(& $enc $Result.VmCount) VMs &middot; $(& $enc $Result.Timestamp)</p>")
    $null = $sb.AppendLine('<p class="note">Generated offline from a result file. Results are only as trustworthy as the run that produced them; this framework is not yet proven on a live cluster.</p>')
    if ($comparison) {
        $null = $sb.AppendLine("<h2>Comparison with baseline $(& $enc $Baseline.RunId): <span class=""$(& $enc $comparison.Status)"">$(& $enc $comparison.Status)</span></h2>")
        foreach ($n in $comparison.Notes) { $null = $sb.AppendLine("<p class=""note"">$(& $enc $n)</p>") }
    }
    $null = $sb.AppendLine('<h2>Metrics</h2><table><thead><tr><th>Metric</th><th>Unit</th><th>Value</th><th>Baseline</th><th>Change %</th><th>Status</th></tr></thead><tbody>')
    foreach ($r in $rows) {
        $f = { param($v) if ($null -eq $v) { '' } else { [string]::Format([cultureinfo]::InvariantCulture, '{0:N2}', $v) } }
        $null = $sb.AppendLine("<tr><td>$(& $enc $r.Metric)</td><td>$(& $enc $r.Unit)</td><td class=""n"">$(& $f $r.Value)</td><td class=""n"">$(& $f $r.Baseline)</td><td class=""n"">$(& $f $r.ChangePercent)</td><td class=""$(& $enc $r.Status)"">$(& $enc $r.Status)</td></tr>")
    }
    $null = $sb.AppendLine('</tbody></table>')
    if (@($Result.PerNode).Count -gt 0) {
        $null = $sb.AppendLine('<h2>Per node</h2><table><thead><tr><th>Node</th><th>VMs</th><th>IOPS</th><th>Avg latency ms</th><th>Throughput MB/s</th></tr></thead><tbody>')
        foreach ($n in $Result.PerNode) {
            $null = $sb.AppendLine("<tr><td>$(& $enc $n.node)</td><td class=""n"">$(& $enc $n.vm_count)</td><td class=""n"">$(& $enc $n.total_iops)</td><td class=""n"">$(& $enc $n.avg_latency_ms)</td><td class=""n"">$(& $enc $n.throughput_mbps)</td></tr>")
        }
        $null = $sb.AppendLine('</tbody></table>')
    }
    $null = $sb.AppendLine('</body></html>')

    $csvRows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($r in $rows) {
        $csvRows.Add([pscustomobject]@{ run_id = (ConvertTo-SafeCsvCell $Result.RunId); scope = 'cluster'; name = $r.Metric; unit = $r.Unit; value = $r.Value; baseline = $r.Baseline; change_percent = $r.ChangePercent; status = $r.Status })
    }
    foreach ($n in $Result.PerNode) {
        $csvRows.Add([pscustomobject]@{ run_id = (ConvertTo-SafeCsvCell $Result.RunId); scope = 'node'; name = (ConvertTo-SafeCsvCell ([string]$n.node)); unit = 'IOPS'; value = $n.total_iops; baseline = $null; change_percent = $null; status = '' })
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write HTML and CSV report')) {
        if (-not (Test-Path -LiteralPath $OutputPath)) { $null = New-Item -ItemType Directory -Path $OutputPath -Force }
        Set-Content -LiteralPath $htmlPath -Value $sb.ToString() -Encoding utf8
        $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
    }
    [pscustomobject]@{ HtmlPath = $htmlPath; CsvPath = $csvPath; Comparison = $comparison }
}


function New-Day2SmokeResult {
    <#
    .SYNOPSIS
        Builds the Day-2 smoke result object (docs/reference/day2-smoke-result.schema.json) from a result and the profile thresholds.
    .DESCRIPTION
        Absolute checks from the Day2Smoke profile (min IOPS per node, max average latency, min throughput) and,
        when a baseline is given, the regression comparison. status: Pass (exit 0), Fail (exit 1), Error (exit 2),
        Skipped (exit 3, nothing was run). A gate must treat every non-zero exit code as "not passed".
        Fail closed: an unreadable result, an unknown node count (when a per-node threshold applies) or a
        not-comparable baseline is Error, never Pass.
    .PARAMETER Result
        Normalised result or a path. $null with -Status Skipped/Error for runs that produced none.
    .PARAMETER Threshold
        Hashtable with min_iops_per_node, max_latency_ms, min_throughput_mbps (the profile expected_thresholds).
    .PARAMETER NodeCount
        Number of cluster nodes (needed for min_iops_per_node).
    .PARAMETER Baseline
        Optional baseline (normalised or path) for the regression check.
    .PARAMETER Status
        Force Skipped or Error with the reason in -Message (no evaluation).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory result object only.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object]$Result,
        [hashtable]$Threshold = @{},
        [int]$NodeCount = 0,
        [object]$Baseline,
        [ValidateSet('Evaluate', 'Skipped', 'Error')][string]$Status = 'Evaluate',
        [string]$Message = '',
        [datetime]$StartedAt = (Get-Date).ToUniversalTime(),
        [datetime]$FinishedAt = (Get-Date).ToUniversalTime(),
        [string]$ProfileName = 'Day2Smoke'
    )

    $checks = [System.Collections.Generic.List[pscustomobject]]::new()
    $notes = [System.Collections.Generic.List[string]]::new()
    $final = $Status
    $norm = $null
    $baselineId = $null

    if ($Status -eq 'Evaluate') {
        try {
            $norm = if ($Result -is [string]) { ConvertTo-NormalizedResult -Path $Result } else { $Result }
            if ($null -eq $norm) { throw 'No result to evaluate.' }
        }
        catch {
            $final = 'Error'
            $notes.Add($_.Exception.Message)
        }
    }
    elseif ($Message) { $notes.Add($Message) }

    if ($final -eq 'Evaluate') {
        $failed = $false
        $m = $norm.Metrics
        $minIopsNode = if ($Threshold.ContainsKey('min_iops_per_node')) { [double]$Threshold['min_iops_per_node'] } else { $null }
        if ($null -ne $minIopsNode) {
            if ($NodeCount -lt 1) {
                $final = 'Error'
                $notes.Add('min_iops_per_node needs the node count, which is unknown: refusing to guess.')
            }
            else {
                $perNode = [math]::Round($m['total_iops'] / $NodeCount, 2)
                $ok = ($perNode -ge $minIopsNode)
                if (-not $ok) { $failed = $true }
                $checks.Add([pscustomobject]@{ metric = 'iops_per_node'; kind = 'min'; limit = $minIopsNode; actual = $perNode; status = $(if ($ok) { 'Pass' } else { 'Fail' }) })
            }
        }
        if ($Threshold.ContainsKey('max_latency_ms')) {
            $lim = [double]$Threshold['max_latency_ms']
            $act = $m['avg_latency_ms']
            $ok = ($null -ne $act -and $act -le $lim)
            if (-not $ok) { $failed = $true }
            $checks.Add([pscustomobject]@{ metric = 'avg_latency_ms'; kind = 'max'; limit = $lim; actual = $act; status = $(if ($ok) { 'Pass' } else { 'Fail' }) })
        }
        if ($Threshold.ContainsKey('min_throughput_mbps')) {
            $lim = [double]$Threshold['min_throughput_mbps']
            $act = $m['total_throughput_mbps']
            $ok = ($null -ne $act -and $act -ge $lim)
            if (-not $ok) { $failed = $true }
            $checks.Add([pscustomobject]@{ metric = 'total_throughput_mbps'; kind = 'min'; limit = $lim; actual = $act; status = $(if ($ok) { 'Pass' } else { 'Fail' }) })
        }
        if ($checks.Count -eq 0 -and $final -ne 'Error' -and -not $Baseline) {
            $final = 'Error'
            $notes.Add('No thresholds and no baseline were supplied: nothing to evaluate against.')
        }
        if ($Baseline -and $final -ne 'Error') {
            $cmp = Compare-LoadTestResult -Baseline $Baseline -Candidate $norm
            $baselineId = $cmp.BaselineRunId
            foreach ($row in $cmp.Metrics) {
                $checks.Add([pscustomobject]@{ metric = $row.Metric; kind = 'regression'; limit = $row.LimitPercent; actual = $row.ChangePercent; status = $(if ($row.Status -in 'Pass', 'Improved') { 'Pass' } elseif ($row.Status -eq 'Regression') { 'Fail' } else { 'Error' }) })
            }
            foreach ($n in $cmp.Notes) { $notes.Add($n) }
            if ($cmp.ExitCode -eq 2) { $final = 'Error' }
            elseif ($cmp.ExitCode -eq 1) { $failed = $true }
        }
        if ($final -ne 'Error') { $final = if ($failed) { 'Fail' } else { 'Pass' } }
    }

    $exit = switch ($final) { 'Pass' { 0 } 'Fail' { 1 } 'Error' { 2 } 'Skipped' { 3 } }
    $metricsOut = $null
    if ($norm) {
        $metricsOut = [ordered]@{}
        foreach ($k in $norm.Metrics.Keys) { $metricsOut[$k] = $norm.Metrics[$k] }
    }
    [pscustomobject][ordered]@{
        schema_version      = '1.0'
        tool                = 'vmfleet'
        profile             = $ProfileName
        status              = $final
        exit_code           = $exit
        proven_on_hardware  = $false
        started_at          = $StartedAt.ToUniversalTime().ToString('o')
        finished_at         = $FinishedAt.ToUniversalTime().ToString('o')
        duration_seconds    = [int][math]::Max(0, [math]::Round(($FinishedAt - $StartedAt).TotalSeconds))
        run_id              = $(if ($norm) { $norm.RunId } else { '' })
        cluster_name        = $(if ($norm) { $norm.ClusterName } else { '' })
        node_count          = $NodeCount
        baseline_run_id     = $baselineId
        metrics             = $metricsOut
        checks              = @($checks.ToArray())
        notes               = @($notes.ToArray())
    }
}

Export-ModuleMember -Function @(
    'Get-ResultMetricDefinition'
    'ConvertTo-NormalizedResult'
    'Test-ResultComparable'
    'Compare-LoadTestResult'
    'Get-ResultTrend'
    'New-ResultReport'
    'New-Day2SmokeResult'
)
