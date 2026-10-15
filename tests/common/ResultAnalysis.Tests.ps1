# =============================================================================
# ResultAnalysis.Tests.ps1 - offline fixtures only, no cluster
# =============================================================================

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'common\modules\ResultAnalysis\ResultAnalysis.psm1') -Force
    $script:Fx = Join-Path $script:Root 'tests\fixtures\results'
    function script:Fx([string]$n) { Join-Path $script:Fx $n }
}

Describe 'ConvertTo-NormalizedResult' {
    It 'reads the collector shape and derives total throughput' {
        $r = ConvertTo-NormalizedResult -Path (Fx 'baseline-aggregate.json')
        $r.RunId | Should -Be 'fixture-baseline-001'
        $r.Metrics['total_iops'] | Should -Be 120000
        $r.Metrics['total_throughput_mbps'] | Should -BeGreaterThan 900
        $r.Parameters.block_size | Should -Be '8k'
    }
    It 'reads the sample shape with a results block and p95/p99' {
        $r = ConvertTo-NormalizedResult -Path (Join-Path $script:Root 'tools\vmfleet\examples\sample-aggregate-results.json')
        $r.Metrics['p99_latency_ms'] | Should -Be 15.22
        @($r.PerNode).Count | Should -BeGreaterThan 0
    }
    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a non-numeric metric'; File = 'candidate-invalid-aggregate.json' }
        @{ Name = 'a negative metric'; File = 'candidate-negative-aggregate.json' }
    ) {
        { ConvertTo-NormalizedResult -Path (Fx $File) } | Should -Throw
    }
    It 'rejects a missing file and broken JSON' {
        { ConvertTo-NormalizedResult -Path (Fx 'nope.json') } | Should -Throw '*not found*'
        $bad = Join-Path $TestDrive 'bad.json'
        '{ not json' | Set-Content $bad
        { ConvertTo-NormalizedResult -Path $bad } | Should -Throw '*not valid JSON*'
    }
}

Describe 'Compare-LoadTestResult (regression gate)' {
    It 'passes a candidate within the thresholds (exit 0)' {
        $c = Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'candidate-ok-aggregate.json')
        $c.Status | Should -Be 'Pass'
        $c.ExitCode | Should -Be 0
    }
    It 'flags a regression (exit 1) and names the metrics' {
        $c = Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'candidate-regressed-aggregate.json')
        $c.ExitCode | Should -Be 1
        ($c.Metrics | Where-Object Status -EQ 'Regression').Metric | Should -Contain 'total_iops'
        ($c.Metrics | Where-Object Status -EQ 'Regression').Metric | Should -Contain 'avg_latency_ms'
    }
    It 'passes an improvement' {
        (Compare-LoadTestResult -Baseline (Fx 'candidate-regressed-aggregate.json') -Candidate (Fx 'baseline-aggregate.json')).ExitCode | Should -Be 0
    }
    It 'treats a different profile as not comparable (exit 2), never as a pass' {
        $c = Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'candidate-mismatch-aggregate.json')
        $c.ExitCode | Should -Be 2
        $c.Status | Should -Be 'NotComparable'
    }
    It 'compares a mismatched profile only with -AllowMismatch and still lists the mismatch' {
        $c = Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'candidate-mismatch-aggregate.json') -AllowMismatch
        $c.ExitCode | Should -Be 0
        ($c.Notes -join ' ') | Should -Match 'profile differs'
    }
    It 'fails closed when a required gated metric is missing (exit 2)' {
        $c = Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'candidate-missing-metric-aggregate.json')
        $c.ExitCode | Should -Be 2
        ($c.Metrics | Where-Object Metric -EQ 'avg_latency_ms').Status | Should -Be 'Missing'
    }
    It 'fails closed on invalid input (exit 2)' {
        (Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'candidate-invalid-aggregate.json')).ExitCode | Should -Be 2
        (Compare-LoadTestResult -Baseline (Fx 'nope.json') -Candidate (Fx 'baseline-aggregate.json')).ExitCode | Should -Be 2
    }
    It 'honours a per-metric threshold override' {
        $strict = Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'candidate-ok-aggregate.json') -Threshold @{ total_iops = 2 }
        $strict.ExitCode | Should -Be 1
        $loose = Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'candidate-regressed-aggregate.json') -MaxDropPercent 40 -MaxRisePercent 100
        $loose.ExitCode | Should -Be 0
    }
    It 'rejects an unknown or negative threshold (exit 2)' {
        (Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'baseline-aggregate.json') -Threshold @{ bogus = 1 }).ExitCode | Should -Be 2
        (Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'baseline-aggregate.json') -Threshold @{ total_iops = -1 }).ExitCode | Should -Be 2
    }
    It 'does not divide by zero when the baseline value is 0' {
        $b = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'b'; profile_name = 'P'; vm_count = 1; total_iops = 0; total_throughput_mbps = 0; avg_latency_ms = 0 })
        $c = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'c'; profile_name = 'P'; vm_count = 1; total_iops = 10; total_throughput_mbps = 1; avg_latency_ms = 5 })
        $r = Compare-LoadTestResult -Baseline $b -Candidate $c
        $r.ExitCode | Should -Be 2   # a baseline with no I/O is not a reference
        ($r.Metrics | Where-Object Metric -EQ 'total_iops').Status | Should -Be 'Missing'
    }
    It 'does not let a zero baseline latency hide a slow candidate' {
        $b = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'b'; profile_name = 'P'; vm_count = 1; total_iops = 100; total_throughput_mbps = 10; avg_latency_ms = 0 })
        $c = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'c'; profile_name = 'P'; vm_count = 1; total_iops = 100; total_throughput_mbps = 10; avg_latency_ms = 5 })
        (Compare-LoadTestResult -Baseline $b -Candidate $c).ExitCode | Should -Be 1
    }
    It 'refuses a threshold that disables the gate' {
        { Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'baseline-aggregate.json') -MaxDropPercent 100 } | Should -Throw
        (Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'baseline-aggregate.json') -Threshold @{ total_iops = 100 }).ExitCode | Should -Be 2
    }
    It 'refuses to compare a run with itself' {
        (Compare-LoadTestResult -Baseline (Fx 'baseline-aggregate.json') -Candidate (Fx 'baseline-aggregate.json')).ExitCode | Should -Be 2
    }
    It 'refuses a candidate from another cluster' {
        $b = ConvertTo-NormalizedResult -Path (Fx 'baseline-aggregate.json')
        $o = ConvertTo-NormalizedResult -Path (Fx 'candidate-ok-aggregate.json')
        $o.ClusterName = 'another-cluster'
        (Compare-LoadTestResult -Baseline $b -Candidate $o).ExitCode | Should -Be 2
    }
    It 'refuses a candidate whose workload parameters were removed' {
        $b = ConvertTo-NormalizedResult -Path (Fx 'baseline-aggregate.json')
        $o = ConvertTo-NormalizedResult -Path (Fx 'candidate-ok-aggregate.json')
        $o.Parameters = $null
        (Compare-LoadTestResult -Baseline $b -Candidate $o).ExitCode | Should -Be 2
    }
    It 'fails closed when the candidate drops a tail-latency metric the baseline had' {
        $b = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'b'; profile_name = 'P'; vm_count = 1; total_iops = 100; total_throughput_mbps = 10; avg_latency_ms = 1; p99_latency_ms = 5 })
        $c = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'c'; profile_name = 'P'; vm_count = 1; total_iops = 100; total_throughput_mbps = 10; avg_latency_ms = 1 })
        (Compare-LoadTestResult -Baseline $b -Candidate $c).ExitCode | Should -Be 2
    }
    It 'treats an overflowing limit as not credible' {
        $b = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'b'; profile_name = 'P'; vm_count = 1; total_iops = 100; total_throughput_mbps = 10; avg_latency_ms = 1.7e308 })
        $c = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'c'; profile_name = 'P'; vm_count = 1; total_iops = 100; total_throughput_mbps = 10; avg_latency_ms = 1 })
        (Compare-LoadTestResult -Baseline $b -Candidate $c -MaxRisePercent 1000).ExitCode | Should -Be 2
    }
    It 'allows latency noise inside the absolute slack' {
        $b = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'b'; profile_name = 'P'; vm_count = 1; total_iops = 100; total_throughput_mbps = 10; avg_latency_ms = 0.2 })
        $c = ConvertTo-NormalizedResult -InputObject ([pscustomobject]@{ run_id = 'c'; profile_name = 'P'; vm_count = 1; total_iops = 100; total_throughput_mbps = 10; avg_latency_ms = 0.31 })
        (Compare-LoadTestResult -Baseline $b -Candidate $c).ExitCode | Should -Be 0
        (Compare-LoadTestResult -Baseline $b -Candidate $c -LatencySlackMs 0).ExitCode | Should -Be 1
    }
}

Describe 'Get-ResultTrend' {
    It 'orders by timestamp and compares each run with the previous one' {
        $t = @(Get-ResultTrend -Path @((Fx 'candidate-regressed-aggregate.json'), (Fx 'baseline-aggregate.json'), (Fx 'candidate-ok-aggregate.json')))
        $t.RunId | Should -Be @('fixture-baseline-001', 'fixture-candidate-ok-002', 'fixture-candidate-regressed-003')
        $t[0].VersusPrevious | Should -Be 'First'
        $t[1].VersusPrevious | Should -Be 'Pass'
        $t[2].VersusPrevious | Should -Be 'Regression'
    }
}

Describe 'New-ResultReport' {
    It 'writes HTML and CSV, with the comparison when a baseline is given' {
        $out = Join-Path $TestDrive 'rep'
        $r = New-ResultReport -Result (Fx 'candidate-regressed-aggregate.json') -Baseline (Fx 'baseline-aggregate.json') -OutputPath $out
        Test-Path $r.HtmlPath | Should -BeTrue
        Test-Path $r.CsvPath | Should -BeTrue
        (Get-Content $r.HtmlPath -Raw) | Should -Match 'Regression'
        (Import-Csv $r.CsvPath | Where-Object name -EQ 'total_iops').status | Should -Be 'Regression'
    }
    It 'encodes HTML and neutralises spreadsheet formulas' {
        $obj = [pscustomobject]@{ run_id = '=cmd|calc'; cluster_name = '<script>alert(1)</script>'; profile_name = 'P'; vm_count = 1; total_iops = 10; total_throughput_mbps = 1; avg_latency_ms = 1 }
        $n = ConvertTo-NormalizedResult -InputObject $obj
        $out = Join-Path $TestDrive 'inj'
        $r = New-ResultReport -Result $n -OutputPath $out
        (Get-Content $r.HtmlPath -Raw) | Should -Not -Match '<script>alert'
        (Get-Content $r.HtmlPath -Raw) | Should -Match '&lt;script&gt;'
        (Import-Csv $r.CsvPath)[0].run_id | Should -Be "'=cmd|calc"
        (Split-Path $r.HtmlPath -Leaf) | Should -Not -Match '[=|]'
    }
    It 'writes nothing under -WhatIf' {
        $out = Join-Path $TestDrive 'whatif'
        New-ResultReport -Result (Fx 'baseline-aggregate.json') -OutputPath $out -WhatIf | Out-Null
        Test-Path $out | Should -BeFalse
    }
}
