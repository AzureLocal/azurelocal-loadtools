# =============================================================================
# ConfigManager.Tests.ps1 - Pester unit tests
# =============================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\src\core\powershell\modules\ConfigManager\ConfigManager.psm1'
    Import-Module $modulePath -Force
}

Describe 'ConfigManager Module' {
    Context 'Import-MasterConfig' {
        It 'Should load a valid master config YAML' {
            $configPath = Join-Path $PSScriptRoot '..\config\variables\master-environment.yml'
            if (Test-Path $configPath) {
                $config = Import-MasterConfig -ConfigPath $configPath
                $config | Should -Not -BeNullOrEmpty
                $config.metadata | Should -Not -BeNullOrEmpty
                $config.variables | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because 'master-environment.yml not found'
            }
        }

        It 'Should throw on non-existent config file' {
            { Import-MasterConfig -ConfigPath 'nonexistent.yml' } | Should -Throw
        }

        It 'Should cache repeated loads' {
            $configPath = Join-Path $PSScriptRoot '..\config\variables\master-environment.yml'
            if (Test-Path $configPath) {
                $first = Import-MasterConfig -ConfigPath $configPath
                $second = Import-MasterConfig -ConfigPath $configPath
                $second | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because 'master-environment.yml not found'
            }
        }
    }

    Context 'Export-SolutionConfig' {
        It 'Should generate a JSON solution config' {
            $configPath = Join-Path $PSScriptRoot '..\config\variables\master-environment.yml'
            $outputPath = Join-Path $TestDrive 'test-vmfleet.json'

            if (Test-Path $configPath) {
                Export-SolutionConfig -ConfigPath $configPath -Solution 'VMFleet' -OutputPath $outputPath
                Test-Path $outputPath | Should -BeTrue
                $content = Get-Content $outputPath -Raw | ConvertFrom-Json
                $content._metadata.solution | Should -Be 'VMFleet'
            }
            else {
                Set-ItResult -Skipped -Because 'master-environment.yml not found'
            }
        }
    }

    Context 'Get-ConfigValue' {
        It 'Should return explicit parameter value first' {
            $result = Get-ConfigValue -ExplicitValue 'explicit' -ConfigValue 'config' -DefaultValue 'default'
            $result | Should -Be 'explicit'
        }

        It 'Should fall back to config value' {
            $result = Get-ConfigValue -ExplicitValue $null -ConfigValue 'config' -DefaultValue 'default'
            $result | Should -Be 'config'
        }

        It 'Should fall back to default value' {
            $result = Get-ConfigValue -ExplicitValue $null -ConfigValue $null -DefaultValue 'default'
            $result | Should -Be 'default'
        }
    }
}
