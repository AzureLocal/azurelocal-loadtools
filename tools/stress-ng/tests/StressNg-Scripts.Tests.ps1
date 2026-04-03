# =============================================================================
# StressNg-Scripts.Tests.ps1 - Pester unit tests for stress-ng pipeline scripts
# =============================================================================

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:StressNgScriptsPath = Join-Path $script:ProjectRoot 'tools\stress-ng\scripts'
    $script:StressNgRootPath    = Join-Path $script:ProjectRoot 'tools\stress-ng'
}

Describe 'stress-ng Script Standards Compliance' {
    $testCases = @(
        @{ Name = 'Start-StressNgTest.ps1';      Path = 'tools\stress-ng\scripts\Start-StressNgTest.ps1' }
        @{ Name = 'Collect-StressNgResults.ps1'; Path = 'tools\stress-ng\scripts\Collect-StressNgResults.ps1' }
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
            $script:Content | Should -Match '\$ErrorActionPreference\s*=\s*''Stop'''
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

Describe 'stress-ng Config Profiles' {
    $profileCases = @(
        @{ Name = 'cpu-stress.yml';    Path = 'tools\stress-ng\config\profiles\cpu-stress.yml' }
        @{ Name = 'memory-stress.yml'; Path = 'tools\stress-ng\config\profiles\memory-stress.yml' }
        @{ Name = 'io-stress.yml';     Path = 'tools\stress-ng\config\profiles\io-stress.yml' }
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

        It 'Should specify at least one stressor' {
            $script:Profile.profile.parameters.stressors.Count | Should -BeGreaterThan 0
        }

        It 'Should specify a timeout' {
            $script:Profile.profile.parameters.timeout | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Start-StressNgTest — Command Building' {
    BeforeAll {
        $script:FullPath = Join-Path $script:ProjectRoot 'tools\stress-ng\scripts\Start-StressNgTest.ps1'
        $script:Content  = Get-Content -Path $script:FullPath -Raw
    }

    It 'Should build stress-ng CLI command with stressor flags' {
        $script:Content | Should -Match 'stress-ng'
        $script:Content | Should -Match '--timeout'
    }

    It 'Should use --yaml for structured output' {
        $script:Content | Should -Match '--yaml'
    }

    It 'Should use --metrics-brief for performance metrics' {
        $script:Content | Should -Match '--metrics-brief'
    }
}

Describe 'stress-ng Monitoring Alert Rules' {
    BeforeAll {
        $script:AlertFile = Join-Path $script:ProjectRoot 'tools\stress-ng\monitoring\alerts\alert-rules.yml'
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
