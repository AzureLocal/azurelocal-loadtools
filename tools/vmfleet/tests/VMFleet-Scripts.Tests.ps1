# =============================================================================
# VMFleet-Scripts.Tests.ps1 - Pester unit tests for VMFleet pipeline scripts
# =============================================================================

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:VMFleetScriptsPath = Join-Path $script:ProjectRoot 'tools\vmfleet\scripts'
    $script:VMFleetRootPath = Join-Path $script:ProjectRoot 'tools\vmfleet'
    $script:MonitoringPath = Join-Path $script:VMFleetRootPath 'monitoring'
    $script:InfraPath = Join-Path $script:ProjectRoot 'tools\vmfleet\infrastructure'
}

Describe 'VMFleet Script Standards Compliance' {
    $testCases = @(
        @{ Name = 'Invoke-VMFleetPipeline.ps1'; Path = 'tools\vmfleet\Invoke-VMFleetPipeline.ps1' }
        @{ Name = 'Install-VMFleet.ps1'; Path = 'tools\vmfleet\scripts\Install-VMFleet.ps1' }
        @{ Name = 'Deploy-VMFleet.ps1'; Path = 'tools\vmfleet\scripts\Deploy-VMFleet.ps1' }
        @{ Name = 'Start-VMFleetTest.ps1'; Path = 'tools\vmfleet\scripts\Start-VMFleetTest.ps1' }
        @{ Name = 'Stop-VMFleetTest.ps1'; Path = 'tools\vmfleet\scripts\Stop-VMFleetTest.ps1' }
        @{ Name = 'Watch-VMFleetMonitor.ps1'; Path = 'tools\vmfleet\scripts\Watch-VMFleetMonitor.ps1' }
        @{ Name = 'Collect-VMFleetResults.ps1'; Path = 'tools\vmfleet\scripts\Collect-VMFleetResults.ps1' }
        @{ Name = 'Remove-VMFleet.ps1'; Path = 'tools\vmfleet\scripts\Remove-VMFleet.ps1' }
        @{ Name = 'Prepare-VMFleetBaseImage.ps1'; Path = 'tools\vmfleet\infrastructure\Prepare-VMFleetBaseImage.ps1' }
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
            $script:Content = Get-Content -Path $script:FullPath -Raw
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

        It 'Should have try/catch structure' {
            $script:Content | Should -Match 'try\s*\{'
            $script:Content | Should -Match 'catch\s*\{'
        }
    }
}

Describe 'VMFleet Monitoring Scripts' {
    $monitoringCases = @(
        @{ Name = 'Collect-StorageMetrics.ps1'; Path = 'tools\vmfleet\monitoring\Collect-StorageMetrics.ps1' }
        @{ Name = 'Collect-ComputeMetrics.ps1'; Path = 'tools\vmfleet\monitoring\Collect-ComputeMetrics.ps1' }
        @{ Name = 'Collect-NetworkMetrics.ps1'; Path = 'tools\vmfleet\monitoring\Collect-NetworkMetrics.ps1' }
        @{ Name = 'Push-MetricsToAzureMonitor.ps1'; Path = 'tools\vmfleet\monitoring\Push-MetricsToAzureMonitor.ps1' }
        @{ Name = 'Export-MetricsDashboard.ps1'; Path = 'tools\vmfleet\monitoring\Export-MetricsDashboard.ps1' }
    )

    Context '<Name> — Existence and Syntax' -ForEach $monitoringCases {
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
}

Describe 'VMFleet Workload Profiles' {
    BeforeAll {
        $script:ProfilesPath = Join-Path $script:ProjectRoot 'config\profiles\vmfleet'
    }

    $profileCases = @(
        @{ Name = 'general.yml' }
        @{ Name = 'peak-iops.yml' }
        @{ Name = 'sql-oltp.yml' }
        @{ Name = 'vdi.yml' }
        @{ Name = 'sequential-throughput.yml' }
    )

    Context '<Name> — Profile Validation' -ForEach $profileCases {
        BeforeAll {
            $script:ProfilePath = Join-Path $script:ProfilesPath $Name
        }

        It 'Should exist on disk' {
            Test-Path $script:ProfilePath | Should -BeTrue
        }

        It 'Should be valid YAML with profile.name key' {
            if (Get-Module -ListAvailable -Name powershell-yaml) {
                Import-Module powershell-yaml
                $profileData = Get-Content -Path $script:ProfilePath -Raw | ConvertFrom-Yaml
                $profileData.profile.name | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because 'powershell-yaml module not installed'
            }
        }

        It 'Should define required parameters' {
            if (Get-Module -ListAvailable -Name powershell-yaml) {
                Import-Module powershell-yaml
                $profileData = Get-Content -Path $script:ProfilePath -Raw | ConvertFrom-Yaml
                $params = $profileData.profile.parameters
                $params.block_size | Should -Not -BeNullOrEmpty
                $null -ne $params.write_ratio | Should -BeTrue
                $null -ne $params.random_ratio | Should -BeTrue
                $null -ne $params.outstanding_io | Should -BeTrue
                $null -ne $params.threads_per_vm | Should -BeTrue
                $null -ne $params.duration_seconds | Should -BeTrue
            }
            else {
                Set-ItResult -Skipped -Because 'powershell-yaml module not installed'
            }
        }
    }
}

Describe 'VMFleet Configuration Schema' {
    It 'Should have valid JSON schema definition' {
        $schemaPath = Join-Path $script:ProjectRoot 'config\schema\variables.schema.json'
        Test-Path $schemaPath | Should -BeTrue
        { Get-Content $schemaPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Should require custom_location_id in azure_local' {
        $schemaPath = Join-Path $script:ProjectRoot 'config\schema\variables.schema.json'
        $schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
        $required = $schema.properties.azure_local.required
        $required | Should -Contain 'custom_location_id'
    }

    It 'Should require storage_path_id in azure_local' {
        $schemaPath = Join-Path $script:ProjectRoot 'config\schema\variables.schema.json'
        $schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
        $required = $schema.properties.azure_local.required
        $required | Should -Contain 'storage_path_id'
    }
}

Describe 'VMFleet Monitoring Artifacts' {
    It 'Should have Azure Monitor workbook definition' {
        $workbookPath = Join-Path $script:ProjectRoot 'monitoring\workbooks\vmfleet-workbook.json'
        Test-Path $workbookPath | Should -BeTrue
        { Get-Content $workbookPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Should have IOPS KQL query' {
        $kqlPath = Join-Path $script:ProjectRoot 'monitoring\queries\vmfleet-iops.kql'
        Test-Path $kqlPath | Should -BeTrue
        $content = Get-Content $kqlPath -Raw
        $content | Should -Match 'VMFleetMetrics_CL'
    }

    It 'Should have latency KQL query' {
        $kqlPath = Join-Path $script:ProjectRoot 'monitoring\queries\vmfleet-latency.kql'
        Test-Path $kqlPath | Should -BeTrue
        $content = Get-Content $kqlPath -Raw
        $content | Should -Match 'percentile'
    }

    It 'Should have alert rules definition' {
        $alertsPath = Join-Path $script:ProjectRoot 'monitoring\alerts\alert-rules.yml'
        Test-Path $alertsPath | Should -BeTrue
    }
}
