# =============================================================================
# Day2Smoke.Tests.ps1 - schema, evaluation and exit codes (fixtures, no cluster)
# =============================================================================

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'common\modules\ResultAnalysis\ResultAnalysis.psm1') -Force
    $script:Schema = Join-Path $script:Root 'docs\reference\day2-smoke-result.schema.json'
    $script:Fx = Join-Path $script:Root 'tests\fixtures\results'
    $script:SmokeFx = Join-Path $script:Root 'tests\fixtures\day2-smoke'
    $script:Script = Join-Path $script:Root 'tools\vmfleet\scripts\Invoke-Day2Smoke.ps1'
    $script:Thr = @{ min_iops_per_node = 5000; max_latency_ms = 25; min_throughput_mbps = 100 }
    function script:Fx([string]$n) { Join-Path $script:Fx $n }
    function script:ToJson($o) { $o | ConvertTo-Json -Depth 8 }
}

Describe 'Day-2 smoke result schema' {
    It 'the schema file is itself valid JSON with the expected id' {
        ((Get-Content $script:Schema -Raw) | ConvertFrom-Json).title | Should -Be 'Day-2 smoke result'
    }
    It 'accepts the committed fixture <Name>' -ForEach @(
        @{ Name = 'pass.json' }, @{ Name = 'fail.json' }, @{ Name = 'error.json' }, @{ Name = 'skipped.json' }
    ) {
        Test-Json -Json (Get-Content (Join-Path $script:SmokeFx $Name) -Raw) -SchemaFile $script:Schema | Should -BeTrue
    }
    It 'rejects the invalid fixture <Name>' -ForEach @(
        @{ Name = 'invalid-pass-with-exit1.json' }, @{ Name = 'invalid-missing-field.json' }, @{ Name = 'invalid-unknown-status.json' }
    ) {
        Test-Json -Json (Get-Content (Join-Path $script:SmokeFx $Name) -Raw) -SchemaFile $script:Schema -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'accepts what New-Day2SmokeResult emits for every status' {
        $ok = New-Day2SmokeResult -Result (Fx 'candidate-ok-aggregate.json') -Threshold $script:Thr -NodeCount 4
        $bad = New-Day2SmokeResult -Result (Fx 'candidate-regressed-aggregate.json') -Threshold @{ min_iops_per_node = 50000 } -NodeCount 4
        $err = New-Day2SmokeResult -Status Error -Message 'boom'
        $skip = New-Day2SmokeResult -Status Skipped -Message 'plan only'
        foreach ($r in $ok, $bad, $err, $skip) { Test-Json -Json (ToJson $r) -SchemaFile $script:Schema | Should -BeTrue }
        $ok.status | Should -Be 'Pass'
        $bad.status | Should -Be 'Fail'
        $err.exit_code | Should -Be 2
        $skip.exit_code | Should -Be 3
    }
}

Describe 'New-Day2SmokeResult evaluation' {
    It 'passes when every threshold holds' {
        (New-Day2SmokeResult -Result (Fx 'candidate-ok-aggregate.json') -Threshold $script:Thr -NodeCount 4).exit_code | Should -Be 0
    }
    It 'fails when IOPS per node is below the minimum' {
        $r = New-Day2SmokeResult -Result (Fx 'candidate-ok-aggregate.json') -Threshold @{ min_iops_per_node = 50000 } -NodeCount 4
        $r.exit_code | Should -Be 1
        ($r.checks | Where-Object metric -EQ 'iops_per_node').status | Should -Be 'Fail'
    }
    It 'fails when latency is above the maximum' {
        (New-Day2SmokeResult -Result (Fx 'candidate-ok-aggregate.json') -Threshold @{ max_latency_ms = 1 } -NodeCount 4).exit_code | Should -Be 1
    }
    It 'fails closed (Error) when the node count is unknown but a per-node threshold exists' {
        (New-Day2SmokeResult -Result (Fx 'candidate-ok-aggregate.json') -Threshold $script:Thr -NodeCount 0).exit_code | Should -Be 2
    }
    It 'fails closed on an unreadable result and on no thresholds at all' {
        (New-Day2SmokeResult -Result (Fx 'candidate-invalid-aggregate.json') -Threshold $script:Thr -NodeCount 4).exit_code | Should -Be 2
        (New-Day2SmokeResult -Result (Fx 'candidate-ok-aggregate.json') -Threshold @{} -NodeCount 4).exit_code | Should -Be 2
    }
    It 'adds the regression check when a baseline is given (Fail on regression, Error on mismatch)' {
        (New-Day2SmokeResult -Result (Fx 'candidate-regressed-aggregate.json') -Baseline (Fx 'baseline-aggregate.json') -Threshold @{ max_latency_ms = 25 } -NodeCount 4).exit_code | Should -Be 1
        (New-Day2SmokeResult -Result (Fx 'candidate-mismatch-aggregate.json') -Baseline (Fx 'baseline-aggregate.json') -Threshold @{ max_latency_ms = 25 } -NodeCount 4).exit_code | Should -Be 2
        (New-Day2SmokeResult -Result (Fx 'candidate-ok-aggregate.json') -Baseline (Fx 'baseline-aggregate.json') -Threshold $script:Thr -NodeCount 4).exit_code | Should -Be 0
    }
}

Describe 'Invoke-Day2Smoke.ps1 exit codes and JSON' {
    It 'evaluates an existing result: exit code matches the JSON, which validates' -ForEach @(
        @{ Case = 'pass'; Result = 'candidate-ok-aggregate.json'; Expect = 0 }
        @{ Case = 'fail'; Result = 'candidate-regressed-aggregate.json'; Expect = 1 }
        @{ Case = 'error'; Result = 'candidate-invalid-aggregate.json'; Expect = 2 }
    ) {
        $out = Join-Path $TestDrive $Case
        $args1 = @('-NoProfile', '-File', $script:Script, '-ResultPath', (Fx $Result), '-OutputPath', $out, '-NodeCount', '4')
        if ($Case -eq 'fail') { $args1 += @('-BaselinePath', (Fx 'baseline-aggregate.json')) }
        & pwsh @args1 *> $null
        $LASTEXITCODE | Should -Be $Expect
        $json = Join-Path $out 'day2-smoke-result.json'
        Test-Json -Json (Get-Content $json -Raw) -SchemaFile $script:Schema | Should -BeTrue
        ((Get-Content $json -Raw) | ConvertFrom-Json).exit_code | Should -Be $Expect
    }
    It 'plan only (-WhatIf) runs nothing and exits 3 (Skipped), never 0' {
        $out = Join-Path $TestDrive 'plan'
        & pwsh -NoProfile -File $script:Script -OutputPath $out -NodeCount 4 -WhatIf *> $null
        $LASTEXITCODE | Should -Be 3
        ((Get-Content (Join-Path $out 'day2-smoke-result.json') -Raw) | ConvertFrom-Json).status | Should -Be 'Skipped'
    }
}

Describe 'Compare-VMFleetResults.ps1 exit codes' {
    BeforeAll { $script:Cmp = Join-Path $script:Root 'tools\vmfleet\scripts\Compare-VMFleetResults.ps1' }
    It '<Case> -> exit <Expect>' -ForEach @(
        @{ Case = 'within threshold'; Cand = 'candidate-ok-aggregate.json'; Expect = 0 }
        @{ Case = 'regression'; Cand = 'candidate-regressed-aggregate.json'; Expect = 1 }
        @{ Case = 'profile mismatch'; Cand = 'candidate-mismatch-aggregate.json'; Expect = 2 }
        @{ Case = 'invalid input'; Cand = 'candidate-invalid-aggregate.json'; Expect = 2 }
        @{ Case = 'same file'; Cand = 'baseline-aggregate.json'; Expect = 2 }
        @{ Case = 'missing file'; Cand = 'does-not-exist.json'; Expect = 2 }
    ) {
        & pwsh -NoProfile -File $script:Cmp -BaselinePath (Fx 'baseline-aggregate.json') -CandidatePath (Fx $Cand) *> $null
        $LASTEXITCODE | Should -Be $Expect
    }
}
