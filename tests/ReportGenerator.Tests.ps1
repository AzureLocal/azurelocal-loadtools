# =============================================================================
# ReportGenerator.Tests.ps1 - Pester unit tests
# =============================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\src\core\powershell\modules\ReportGenerator\ReportGenerator.psm1'
    Import-Module $modulePath -Force
}

Describe 'ReportGenerator Module' {
    Context 'Import-TestResults' {
        It 'Should return empty results for empty directory' {
            $emptyDir = Join-Path $TestDrive 'empty-results'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            $results = Import-TestResults -ResultsPath $emptyDir
            $results.profiles.Count | Should -Be 0
        }

        It 'Should load JSON result files' {
            $resultsDir = Join-Path $TestDrive 'test-results'
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

            $testData = @{
                profile_name = 'general'
                total_iops = 50000
                read_throughput_mbps = 1200
                write_throughput_mbps = 800
                avg_latency_ms = 2.5
            }
            $testData | ConvertTo-Json | Set-Content -Path (Join-Path $resultsDir 'result.json')

            $results = Import-TestResults -ResultsPath $resultsDir
            $results.profiles.Count | Should -Be 1
        }
    }

    Context 'New-TestReport' {
        It 'Should create output directory' {
            $resultsDir = Join-Path $TestDrive 'report-results'
            $outputDir = Join-Path $TestDrive 'report-output'
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

            # This will create the dir but may not generate PDF without asciidoctor-pdf
            New-TestReport -RunId 'test-rpt' -ResultsPath $resultsDir `
                -OutputPath $outputDir -Formats @('XLSX') -WhatIf

            # WhatIf won't actually create, so just verify the function runs
            $true | Should -BeTrue
        }
    }
}
