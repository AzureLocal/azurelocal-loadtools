# =============================================================================
# Prepare-VMFleetBaseImage.Tests.ps1 - Pester unit tests
# =============================================================================

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\infrastructure\Prepare-VMFleetBaseImage.ps1'
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

Describe 'Prepare-VMFleetBaseImage Script' {
    Context 'Script Structure' {
        It 'Should exist on disk' {
            Test-Path $script:ScriptPath | Should -BeTrue
        }

        It 'Should parse without syntax errors' {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It 'Should require PowerShell 7.2' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match '#Requires -Version 7\.2'
        }

        It 'Should use CmdletBinding with SupportsShouldProcess' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
        }

        It 'Should set ErrorActionPreference to Stop' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match '\$ErrorActionPreference\s*=\s*''Stop'''
        }

        It 'Should dot-source Common-Functions.ps1' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'Common-Functions\.ps1'
        }

        It 'Should import Logger module' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'Logger\\Logger\.psm1'
        }

        It 'Should call Start-LogSession' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'Start-LogSession'
        }

        It 'Should call Stop-LogSession in finally block' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'finally\s*\{[^}]*Stop-LogSession'
        }

        It 'Should have try/catch/finally structure' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'try\s*\{'
            $content | Should -Match 'catch\s*\{'
            $content | Should -Match 'finally\s*\{'
        }
    }

    Context 'Parameters' {
        BeforeAll {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
            $script:Params = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
        }

        It 'Should have -ConfigPath parameter' {
            $script:Params | Should -Contain 'ConfigPath'
        }

        It 'Should take the Azure IDs as parameters (never stored in the repo) as well as from -ConfigPath' {
            foreach ($name in 'SubscriptionId', 'ResourceGroup', 'Location', 'CustomLocationId', 'StoragePathId', 'Sku') {
                $script:Params | Should -Contain $name
            }
        }

        It 'Should take the Azure scope, custom location and storage path from an infrastructure.yml given as -ClusterConfigPath, and let a parameter win' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'Import-InfrastructureConfig -InfrastructureFile \$ClusterConfigPath'
            $content | Should -Match 'if \(-not \$SubscriptionId\) \{ \$SubscriptionId = \[string\]\(Get-VMFleetConfigValue \$infrastructure ''azure_subscription_id'''
            $content | Should -Match 'if \(-not \$StoragePathId\) \{ \$StoragePathId = \[string\]\(Get-VMFleetConfigValue \$infrastructure ''storage_path_id'''
        }

        It 'Should have -ClusterConfigPath parameter' {
            $script:Params | Should -Contain 'ClusterConfigPath'
        }

        It 'Should have -ProjectRoot parameter' {
            $script:Params | Should -Contain 'ProjectRoot'
        }

        It 'Should have -Credential parameter' {
            $script:Params | Should -Contain 'Credential'
        }

        It 'Should have -ImageName parameter' {
            $script:Params | Should -Contain 'ImageName'
        }

        It 'Should have -PollIntervalSeconds parameter' {
            $script:Params | Should -Contain 'PollIntervalSeconds'
        }

        It 'Should have -TimeoutMinutes parameter' {
            $script:Params | Should -Contain 'TimeoutMinutes'
        }

        It 'Should have -Force parameter' {
            $script:Params | Should -Contain 'Force'
        }
    }

    Context 'ARM API Integration' {
        It 'Should target marketplace gallery images API' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'marketplaceGalleryImages'
        }

        It 'Should use API version 2023-09-01-preview' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match '2023-09-01-preview'
        }

        It 'Should default to a Windows Server Azure Edition SKU that Microsoft Learn lists for Azure Local' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
            $sku = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Sku' }
            $sku.DefaultValue.Value | Should -BeIn @('2025-datacenter-azure-edition-smalldisk', '2025-datacenter-azure-edition-core', '2025-datacenter-azure-edition', '2022-datacenter-azure-edition-core', '2022-datacenter-azure-edition', '2022-datacenter-azure-edition-hotpatch')
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Not -Match '2022-datacenter-core-g2'
        }

        It 'Should build the ARM URLs with ${name}?api-version (a bare $name? is read as part of the variable name)' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match '\$\{ImageName\}\?api-version'
            $content | Should -Match '\$\{StoragePathId\}\?api-version'
            $content | Should -Not -Match '\$ImageName\?'
            $content | Should -Not -Match '\$storagePathId\?'
        }

        It 'Should stop on an HTTP error from Invoke-AzRestMethod (it does not throw by itself)' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'StatusCode -ge 400'
        }

        It 'Should set hyperVGeneration to V2' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match "hyperVGeneration.*=.*'V2'"
        }

        It 'Should use ShouldProcess before PUT' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'ShouldProcess'
        }
    }

    Context 'Idempotency' {
        It 'Should check provisioningState before downloading' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'provisioningState.*Succeeded'
        }

        It 'Should support -Force to re-trigger download' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'Force\.IsPresent'
        }
    }

    Context 'Cluster Validation' {
        It 'Should call Test-ClusterConnectivity' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'Test-ClusterConnectivity'
        }

        It 'Should use Invoke-RemoteCommand for VHD verification' {
            $content = Get-Content -Path $script:ScriptPath -Raw
            $content | Should -Match 'Invoke-RemoteCommand'
        }
    }
}
