# =============================================================================
# Iperf-Scripts.Tests.ps1 - Pester unit tests for iPerf3 pipeline scripts
# =============================================================================

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:IperfScriptsPath = Join-Path $script:ProjectRoot 'tools\iperf\scripts'
    $script:IperfRootPath    = Join-Path $script:ProjectRoot 'tools\iperf'
}

Describe 'Iperf Script Standards Compliance' {
    $testCases = @(
        @{ Name = 'Start-IperfTest.ps1';      Path = 'tools\iperf\scripts\Start-IperfTest.ps1' }
        @{ Name = 'Collect-IperfResults.ps1'; Path = 'tools\iperf\scripts\Collect-IperfResults.ps1' }
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

Describe 'iPerf3 Config Profiles' {
    $profileCases = @(
        @{ Name = 'tcp-throughput.yml'; Path = 'tools\iperf\config\profiles\tcp-throughput.yml' }
        @{ Name = 'udp-latency.yml';    Path = 'tools\iperf\config\profiles\udp-latency.yml' }
        @{ Name = 'mesh.yml';           Path = 'tools\iperf\config\profiles\mesh.yml' }
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

        It 'Should specify protocol TCP or UDP' {
            $script:Profile.profile.parameters.protocol | Should -BeIn @('TCP', 'UDP')
        }

        It 'Should specify duration_seconds > 0' {
            $script:Profile.profile.parameters.duration_seconds | Should -BeGreaterThan 0
        }

        It 'Should specify server_port' {
            $script:Profile.profile.parameters.server_port | Should -BeGreaterThan 0
        }
    }
}

Describe 'Start-IperfTest — Protocol Handling' {
    BeforeAll {
        $script:FullPath = Join-Path $script:ProjectRoot 'tools\iperf\scripts\Start-IperfTest.ps1'
        $script:Content  = Get-Content -Path $script:FullPath -Raw
    }

    It 'Should handle UDP protocol with bandwidth flag' {
        $script:Content | Should -Match '-u'
    }

    It 'Should support mesh test flag' {
        $script:Content | Should -Match 'mesh'
    }

    It 'Should manage server lifecycle (start and stop)' {
        $script:Content | Should -Match 'iperf3 -s'
        $script:Content | Should -Match 'pkill'
    }
}

Describe 'iPerf3 Monitoring Alert Rules' {
    BeforeAll {
        $script:AlertFile = Join-Path $script:ProjectRoot 'tools\iperf\monitoring\alerts\alert-rules.yml'
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
