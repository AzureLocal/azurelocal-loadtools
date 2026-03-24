# =============================================================================
# Fio-Scripts.Tests.ps1 - Pester unit tests for fio pipeline scripts
# =============================================================================

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:FioScriptsPath = Join-Path $script:ProjectRoot 'tools\fio\scripts'
    $script:FioRootPath    = Join-Path $script:ProjectRoot 'tools\fio'
}

Describe 'Fio Script Standards Compliance' {
    $testCases = @(
        @{ Name = 'Install-Fio.ps1';        Path = 'tools\fio\scripts\Install-Fio.ps1' }
        @{ Name = 'Start-FioTest.ps1';      Path = 'tools\fio\scripts\Start-FioTest.ps1' }
        @{ Name = 'Collect-FioResults.ps1'; Path = 'tools\fio\scripts\Collect-FioResults.ps1' }
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

Describe 'Fio Config Profiles' {
    $profileCases = @(
        @{ Name = 'sequential-read.yml';  Path = 'tools\fio\config\profiles\sequential-read.yml' }
        @{ Name = 'sequential-write.yml'; Path = 'tools\fio\config\profiles\sequential-write.yml' }
        @{ Name = 'random-read.yml';      Path = 'tools\fio\config\profiles\random-read.yml' }
        @{ Name = 'random-write.yml';     Path = 'tools\fio\config\profiles\random-write.yml' }
        @{ Name = 'mixed-70-30.yml';      Path = 'tools\fio\config\profiles\mixed-70-30.yml' }
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

        It 'Should have a profile.parameters section' {
            $script:Profile.profile.parameters | Should -Not -BeNull
        }

        It 'Should specify block_size' {
            $script:Profile.profile.parameters.block_size | Should -Not -BeNullOrEmpty
        }

        It 'Should specify rw pattern' {
            $script:Profile.profile.parameters.rw | Should -Not -BeNullOrEmpty
        }

        It 'Should specify runtime_seconds > 0' {
            $script:Profile.profile.parameters.runtime_seconds | Should -BeGreaterThan 0
        }
    }
}

Describe 'Fio Monitoring Alert Rules' {
    BeforeAll {
        $script:AlertFile = Join-Path $script:ProjectRoot 'tools\fio\monitoring\alerts\alert-rules.yml'
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

Describe 'Fio Report Templates' {
    $templateCases = @(
        @{ Name = 'cover-page.adoc';     Path = 'tools\fio\reports\templates\cover-page.adoc' }
        @{ Name = 'report-template.adoc'; Path = 'tools\fio\reports\templates\report-template.adoc' }
    )

    Context '<Name> — Existence' -ForEach $templateCases {
        It 'Template file should exist' {
            $fullPath = Join-Path $script:ProjectRoot $Path
            Test-Path $fullPath | Should -BeTrue
        }
    }
}
