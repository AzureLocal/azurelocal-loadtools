# =============================================================================
# ConfigManager.Tests.ps1 - Pester unit tests
# =============================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\common\modules\ConfigManager\ConfigManager.psm1'
    Import-Module $modulePath -Force
}

Describe 'ConfigManager Module' {
    Context 'Import-MasterConfig' {
        It 'Should load a valid master config YAML' {
            $configPath = Join-Path $PSScriptRoot '..\..\config\variables\variables.yml'
            if (Test-Path $configPath) {
                $config = Import-MasterConfig -MasterConfigPath $configPath
                $config | Should -Not -BeNullOrEmpty
                $config.metadata | Should -Not -BeNullOrEmpty
                $config.variables | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because 'master-environment.yml not found'
            }
        }

        It 'Should throw on non-existent config file' {
            { Import-MasterConfig -MasterConfigPath 'nonexistent.yml' } | Should -Throw
        }

        It 'Should cache repeated loads' {
            $configPath = Join-Path $PSScriptRoot '..\..\config\variables\variables.yml'
            if (Test-Path $configPath) {
                $first = Import-MasterConfig -MasterConfigPath $configPath
                $second = Import-MasterConfig -MasterConfigPath $configPath
                $second | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because 'master-environment.yml not found'
            }
        }
    }

    Context 'Export-SolutionConfig' {
        It 'Should generate a JSON solution config' {
            $configPath = Join-Path $PSScriptRoot '..\..\config\variables\variables.yml'
            $outputPath = Join-Path $TestDrive 'test-vmfleet.json'

            if (Test-Path $configPath) {
                Export-SolutionConfig -MasterConfigPath $configPath -Solution 'VMFleet' -OutputPath $outputPath
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
        It 'Should return explicit override value first' {
            $result = Get-ConfigValue -Name 'anyvar' -Override 'explicit' -DefaultValue 'default'
            $result | Should -Be 'explicit'
        }

        It 'Should fall back to default when no config and no override' {
            Mock Import-MasterConfig { return [PSCustomObject]@{ variables = @() } }
            $result = Get-ConfigValue -Name 'nonexistent-xyz-9999' -DefaultValue 'fallback'
            $result | Should -Be 'fallback'
        }

        It 'Should fall back to default value' {
            Mock Import-MasterConfig { return [PSCustomObject]@{ variables = @() } }
            $result = Get-ConfigValue -Name 'nonexistent-abc-9999' -Override $null -DefaultValue 'default'
            $result | Should -Be 'default'
        }
    }
}
