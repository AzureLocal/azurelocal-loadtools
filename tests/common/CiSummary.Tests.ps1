BeforeAll {
    $script:Runner = Join-Path $PSScriptRoot '..\Invoke-CiChecks.ps1'
}

Describe 'Pester CI result summary' {
    It 'reports zero failed tests when the suite passes' {
        $root = Join-Path $TestDrive 'passing'
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'Sample.Tests.ps1') -Value "Describe 'Sample' { It 'passes' { 1 | Should -Be 1 } }"
        $resultPath = Join-Path $TestDrive 'passing.json'

        & pwsh -NoProfile -File $script:Runner -Check Pester -ProjectRoot $root -ResultPath $resultPath
        $LASTEXITCODE | Should -Be 0
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $result.passed | Should -BeTrue
        $result.tests_total | Should -Be 1
        $result.tests_passed | Should -Be 1
        $result.tests_failed | Should -Be 0
    }

    It 'reports a failed assertion and a failing exit code' {
        $root = Join-Path $TestDrive 'failing'
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'Sample.Tests.ps1') -Value "Describe 'Sample' { It 'fails' { 1 | Should -Be 2 } }"
        $resultPath = Join-Path $TestDrive 'failing.json'

        & pwsh -NoProfile -File $script:Runner -Check Pester -ProjectRoot $root -ResultPath $resultPath
        $LASTEXITCODE | Should -Be 1
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $result.passed | Should -BeFalse
        $result.tests_total | Should -Be 1
        $result.tests_passed | Should -Be 0
        $result.tests_failed | Should -Be 1
    }
}
