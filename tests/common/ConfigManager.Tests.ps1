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
            } else {
                Set-ItResult -Skipped -Because 'variables.yml not found'
            }
        }

        It 'Should throw on non-existent config file' {
            { Import-MasterConfig -MasterConfigPath 'nonexistent.yml' } | Should -Throw
        }

        It 'Should throw on a bad path even when another config is already cached' {
            $configPath = Join-Path $PSScriptRoot '..\..\config\variables\variables.yml'
            Import-MasterConfig -MasterConfigPath $configPath -Force | Out-Null
            { Import-MasterConfig -MasterConfigPath 'nonexistent.yml' } | Should -Throw
        }

        It 'Should resolve the project root to the repository root' {
            $root = InModuleScope ConfigManager { $script:ProjectRoot }
            Test-Path (Join-Path $root 'common\modules\ConfigManager') | Should -BeTrue
        }

        It 'Should cache repeated loads' {
            $configPath = Join-Path $PSScriptRoot '..\..\config\variables\variables.yml'
            if (Test-Path $configPath) {
                $null = Import-MasterConfig -MasterConfigPath $configPath
                $second = Import-MasterConfig -MasterConfigPath $configPath
                $second | Should -Not -BeNullOrEmpty
            } else {
                Set-ItResult -Skipped -Because 'variables.yml not found'
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
            } else {
                Set-ItResult -Skipped -Because 'variables.yml not found'
            }
        }
    }

    Context 'Cluster facts from infrastructure.yml' {
        BeforeAll {
            $script:ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
            $script:InfraFile = Join-Path $script:ProjectRoot 'tests\fixtures\infrastructure.loadtools.example.yml'
        }

        It 'Should keep the cluster facts out of variables.yml, which holds the test settings only' {
            $path = Join-Path $script:ProjectRoot 'config\variables\variables.yml'
            $config = Import-MasterConfig -MasterConfigPath $path -Force
            $names = @($config.variables | ForEach-Object { $_.name })
            foreach ($fact in 'cluster_name', 'cluster_domain', 'cluster_nodes', 'csv_path', 'keyvault_name') {
                $names | Should -Not -Contain $fact -Because "$fact comes from infrastructure.yml"
            }
            (Test-MasterConfig -MasterConfigPath $path).IsValid | Should -BeTrue
        }

        It 'Should read the cluster, nodes, domain, volume, Azure scope and Key Vault from the file' {
            $v = (Import-InfrastructureConfig -InfrastructureFile $script:InfraFile).Values
            $v.cluster_name | Should -Be 'iic-azl-01'
            $v.cluster_nodes | Should -Be @('iic-azl-n01', 'iic-azl-n02')
            $v.cluster_domain | Should -Be 'improbability.cloud'
            $v.csv_path | Should -Be 'C:\ClusterStorage\vol-workloads-01'
            $v.azure_tenant_id | Should -Be '00000000-0000-0000-0000-000000000000'
            $v.azure_subscription_id | Should -Be '00000000-0000-0000-0000-000000000001'
            $v.azure_resource_group | Should -Be 'rg-iic-azl-01'
            $v.azure_location | Should -Be 'eastus'
            $v.keyvault_name | Should -Be 'kv-iic-mgmt-01' -Because 'the vault with purpose management wins over the first one'
            $v.azure_custom_location_id | Should -Be '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-iic-azl-01/providers/Microsoft.ExtendedLocation/customLocations/cl-iic-azl-01'
            $v.storage_path_id | Should -Be '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-iic-azl-01/providers/Microsoft.AzureStackHCI/storageContainers/sp-workloads-01'
        }

        It 'Should fall back to the first volume and the first vault, and leave the domain empty without Active Directory' {
            $file = Join-Path $TestDrive 'no-paths.yml'
            Set-Content -LiteralPath $file -Value ("_metadata:", "  schema_version: '5.6.30'", "cluster:", "  name: iic-azl-01", "nodes:", "  - name: iic-azl-n01", "key_vaults:", "  - name: kv-iic-backup-01", "    purpose: backup", "storage:", "  volumes:", "    - name: vol-a")
            $v = (Import-InfrastructureConfig -InfrastructureFile $file).Values
            $v.csv_path | Should -Be 'C:\ClusterStorage\vol-a'
            $v.keyvault_name | Should -Be 'kv-iic-backup-01'
            $v.cluster_domain | Should -Be ''
        }

        It 'Should refuse a file that is not schema 5, or has no cluster or nodes, and say which' {
            $old = Join-Path $TestDrive 'old.yml'; Set-Content -LiteralPath $old -Value "cluster:`n  name: x`nnodes:`n  - name: n1"
            { Import-InfrastructureConfig -InfrastructureFile $old } | Should -Throw '*not an infrastructure.yml of schema 5*'
            $empty = Join-Path $TestDrive 'empty.yml'; Set-Content -LiteralPath $empty -Value "_metadata:`n  schema_version: '5.6.0'"
            { Import-InfrastructureConfig -InfrastructureFile $empty } | Should -Throw '*no cluster.name and nodes[[]].name*'
            { Import-InfrastructureConfig -InfrastructureFile (Join-Path $TestDrive 'missing.yml') } | Should -Throw '*not found*'
        }

        It 'Should give the tool scripts the shape they read (cluster.name, nodes[].name, storage.csv_path) from the file' {
            $c = Import-ClusterConfig -Path $script:InfraFile
            $c.cluster.name | Should -Be 'iic-azl-01'
            @($c.nodes | ForEach-Object { $_.name }) | Should -Be @('iic-azl-n01', 'iic-azl-n02')
            $c.storage.csv_path | Should -Be 'C:\ClusterStorage\vol-workloads-01'
            $c.cluster.domain | Should -Be 'improbability.cloud'
        }

        It 'Should still read a per-cluster file of the earlier layout, with a warning to use infrastructure.yml' {
            $file = Join-Path $TestDrive 'iic-cluster01.yml'
            Set-Content -LiteralPath $file -Value "cluster:`n  name: iic-cluster01`nnodes:`n  - name: iic-node01"
            $c = Import-ClusterConfig -Path $file -WarningVariable warned -WarningAction SilentlyContinue
            $c.cluster.name | Should -Be 'iic-cluster01'
            "$warned" | Should -BeLike '*infrastructure.yml*'
        }

        It 'Should write the cluster facts to the solution JSON from the infrastructure file, to the solutions that use them' {
            $vmfleet = Join-Path $TestDrive 'vmfleet.json'
            $iperf = Join-Path $TestDrive 'iperf.json'
            $master = Join-Path $script:ProjectRoot 'config\variables\variables.yml'
            $null = Export-SolutionConfig -Solution vmfleet -MasterConfigPath $master -OutputPath $vmfleet -InfrastructureFile $script:InfraFile
            $null = Export-SolutionConfig -Solution iperf -MasterConfigPath $master -OutputPath $iperf -InfrastructureFile $script:InfraFile
            $a = Get-Content $vmfleet -Raw | ConvertFrom-Json
            $a.cluster_name | Should -Be 'iic-azl-01'
            $a.cluster_nodes | Should -Be @('iic-azl-n01', 'iic-azl-n02')
            $a.csv_path | Should -Be 'C:\ClusterStorage\vol-workloads-01'
            $a.keyvault_name | Should -Be 'kv-iic-mgmt-01'
            $a.azure_subscription_id | Should -Be '00000000-0000-0000-0000-000000000001'
            $b = Get-Content $iperf -Raw | ConvertFrom-Json
            $b.cluster_name | Should -Be 'iic-azl-01'
            $b.PSObject.Properties.Name | Should -Not -Contain 'csv_path' -Because 'iperf does not use the cluster shared volume'
        }

        It 'Should resolve the same values through Initialize-Environment -InfrastructureFile' {
            $init = Join-Path $script:ProjectRoot 'common\helpers\Initialize-Environment.ps1'
            $root = Join-Path $TestDrive 'repo'
            $null = New-Item -ItemType Directory -Path $root -Force
            Copy-Item -Path (Join-Path $script:ProjectRoot 'common') -Destination $root -Recurse
            Copy-Item -Path (Join-Path $script:ProjectRoot 'config') -Destination $root -Recurse
            try {
                $result = & $init -ProjectRoot $root -InfrastructureFile $script:InfraFile -SkipPrerequisiteCheck 6>$null
                $thrown = { & $init -ProjectRoot $root -InfrastructureFile (Join-Path $TestDrive 'nope.yml') -SkipPrerequisiteCheck 6>$null }
                $thrown | Should -Throw '*Infrastructure file not found*'
            }
            finally {
                # Initialize-Environment loads the modules of the copy; put this repository's ConfigManager back.
                Get-Module ConfigManager | Remove-Module -Force
                Import-Module (Join-Path $script:ProjectRoot 'common\modules\ConfigManager\ConfigManager.psm1') -Force
            }
            $expected = (Import-InfrastructureConfig -InfrastructureFile $script:InfraFile).Values
            $result.cluster_name | Should -Be $expected.cluster_name
            $result.cluster_nodes | Should -Be $expected.cluster_nodes
            $result.csv_path | Should -Be $expected.csv_path
            $result.keyvault_name | Should -Be 'kv-iic-mgmt-01'
            $result.azure_resource_group | Should -Be 'rg-iic-azl-01'
        }
    }

    Context 'Get-ConfigValue' {
        It 'Should return explicit override value first' {
            $result = Get-ConfigValue -Name 'anyvar' -Override 'explicit' -DefaultValue 'default'
            $result | Should -Be 'explicit'
        }

        It 'Should fall back to default when no config and no override' {
            Mock Import-MasterConfig -ModuleName ConfigManager { return [PSCustomObject]@{ variables = @() } }
            $result = Get-ConfigValue -Name 'nonexistent-xyz-9999' -DefaultValue 'fallback'
            $result | Should -Be 'fallback'
        }

        It 'Should fall back to default value' {
            Mock Import-MasterConfig -ModuleName ConfigManager { return [PSCustomObject]@{ variables = @() } }
            $result = Get-ConfigValue -Name 'nonexistent-abc-9999' -Override $null -DefaultValue 'default'
            $result | Should -Be 'default'
        }
    }
}
