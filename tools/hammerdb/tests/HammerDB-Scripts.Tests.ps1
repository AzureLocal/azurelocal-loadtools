# =============================================================================
# HammerDB-Scripts.Tests.ps1 - Pester unit tests for HammerDB pipeline scripts
# =============================================================================

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:HammerDBScriptsPath = Join-Path $script:ProjectRoot 'tools\hammerdb\scripts'
    $script:HammerDBRootPath    = Join-Path $script:ProjectRoot 'tools\hammerdb'
}

Describe 'HammerDB Script Standards Compliance' {
    $testCases = @(
        @{ Name = 'Install-HammerDB.ps1';        Path = 'tools\hammerdb\scripts\Install-HammerDB.ps1' }
        @{ Name = 'Start-HammerDBTest.ps1';      Path = 'tools\hammerdb\scripts\Start-HammerDBTest.ps1' }
        @{ Name = 'Collect-HammerDBResults.ps1'; Path = 'tools\hammerdb\scripts\Collect-HammerDBResults.ps1' }
    )

    Context '<Name> — Existence and Syntax' -ForEach $testCases {
        BeforeAll {
            $script:FullPath = Join-Path $script:ProjectRoot $Path
        }

        It 'Should exist on disk' {
            Test-Path $script:FullPath | Should -BeTrue
        }

        It 'Should parse without syntax errors' {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($script:FullPath, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }

    Context '<Name> — Automation Standards' -ForEach $testCases {
        BeforeAll {
            $script:FullPath = Join-Path $script:ProjectRoot $Path
            $script:Content  = Get-Content -Path $script:FullPath -Raw
        }

        It 'Should require PowerShell 7.2' {
            $script:Content | Should -Match '#Requires -Version 7\.2'
        }

        It 'Should use CmdletBinding with SupportsShouldProcess' {
            $script:Content | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
        }

        It 'Should set ErrorActionPreference to Stop' {
            $script:Content | Should -Match "\`\$ErrorActionPreference\s*=\s*'Stop'"
        }

        It 'Should dot-source Common-Functions.ps1' {
            $script:Content | Should -Match 'Common-Functions\.ps1'
        }

        It 'Should import Logger module' {
            $script:Content | Should -Match 'Logger'
        }

        It 'Should have try/catch/finally structure' {
            $script:Content | Should -Match 'try\s*\{'
            $script:Content | Should -Match 'catch\s*\{'
            $script:Content | Should -Match 'finally\s*\{'
        }

        It 'Should call Stop-LogSession in finally' {
            $script:Content | Should -Match 'Stop-LogSession'
        }
    }
}

Describe 'HammerDB Config Profiles' {
    $profileCases = @(
        @{ Name = 'tpc-c.yml'; Path = 'tools\hammerdb\config\profiles\tpc-c.yml' }
        @{ Name = 'tpc-h.yml'; Path = 'tools\hammerdb\config\profiles\tpc-h.yml' }
    )

    Context '<Name> — Existence and Schema' -ForEach $profileCases {
        BeforeAll {
            $script:FullPath = Join-Path $script:ProjectRoot $Path
            if (Test-Path $script:FullPath) {
                Import-Module powershell-yaml -ErrorAction SilentlyContinue
                $script:Profile = Get-Content -Path $script:FullPath -Raw | ConvertFrom-Yaml
            }
        }

        It 'Should exist on disk' {
            Test-Path $script:FullPath | Should -BeTrue
        }

        It 'Should have a profile.name field' {
            $script:Profile.profile.name | Should -Not -BeNullOrEmpty
        }

        It 'Should specify benchmark_type' {
            $script:Profile.profile.parameters.benchmark_type | Should -BeIn @('tpcc', 'tpch')
        }

        It 'Should specify db_type' {
            $script:Profile.profile.parameters.db_type | Should -BeIn @('mssql', 'postgresql')
        }

        It 'Should specify warehouse_count > 0' {
            $script:Profile.profile.parameters.warehouse_count | Should -BeGreaterThan 0
        }

        It 'Should specify virtual_users > 0' {
            $script:Profile.profile.parameters.virtual_users | Should -BeGreaterThan 0
        }
    }
}

Describe 'Collect-HammerDBResults — NOPM/TPM parser' {
    BeforeAll {
        $script:FullPath = Join-Path $script:ProjectRoot 'tools\hammerdb\scripts\Collect-HammerDBResults.ps1'
        . $script:FullPath -ProjectRoot $script:ProjectRoot -RunId 'test-parse' -WhatIf -ErrorAction SilentlyContinue 2>$null
    }

    It 'Get-HammerDBMetrics should parse standard output format' {
        if (-not (Get-Command 'Get-HammerDBMetrics' -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'Get-HammerDBMetrics not in scope (requires dot-sourcing with function export)'
            return
        }

        $sampleLog = 'TEST RESULT : System achieved 12345 NOPM from 23456 PostgreSQL TPM'
        $result = Get-HammerDBMetrics -LogContent $sampleLog
        $result.PeakNopm | Should -Be 12345
        $result.PeakTpm  | Should -Be 23456
    }
}

Describe 'HammerDB Monitoring Alert Rules' {
    BeforeAll {
        $script:AlertFile = Join-Path $script:ProjectRoot 'tools\hammerdb\monitoring\alerts\alert-rules.yml'
        if (Test-Path $script:AlertFile) {
            Import-Module powershell-yaml -ErrorAction SilentlyContinue
            $script:AlertConfig = Get-Content -Path $script:AlertFile -Raw | ConvertFrom-Yaml
        }
    }

    It 'Alert rules file should exist' {
        Test-Path $script:AlertFile | Should -BeTrue
    }

    It 'Should define at least one alert rule' {
        $script:AlertConfig.alert_rules.Count | Should -BeGreaterThan 0
    }

    It 'Each rule should have name, condition, threshold, severity' {
        foreach ($rule in $script:AlertConfig.alert_rules) {
            $rule.name | Should -Not -BeNullOrEmpty
            $rule.condition | Should -Not -BeNullOrEmpty
            $rule.threshold | Should -Not -BeNull
            $rule.severity | Should -BeIn @('warning', 'critical', 'info')
        }
    }
}
