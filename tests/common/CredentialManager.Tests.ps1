# =============================================================================
# CredentialManager.Tests.ps1 - Pester unit tests
# =============================================================================
# No test reaches Azure: Key Vault reads go through Invoke-VaultSecretRead,
# which every Key Vault test mocks. Get-Credential and Read-Host are mocked to
# throw, so any prompt would fail the test.
# =============================================================================

BeforeAll {
    $script:ModuleFile = Join-Path $PSScriptRoot '..\..\common\modules\CredentialManager\CredentialManager.psm1'
    Import-Module $script:ModuleFile -Force

    # Environment variables the tests set or clear; restored in AfterAll.
    $script:EnvNames = @(
        'CLUSTER_ADMIN_USERNAME', 'CLUSTER_ADMIN_PASSWORD',
        'IIC_TEST_ADMIN_USERNAME', 'IIC_TEST_ADMIN_PASSWORD',
        'IIC_TEST_KEY', 'IIC_CUSTOM_KEY'
    )
    $script:SavedEnv = @{}
    foreach ($n in $script:EnvNames) { $script:SavedEnv[$n] = [System.Environment]::GetEnvironmentVariable($n) }

    function script:New-TestCredential {
        param([string]$User = 'iic\svc-loadtools')
        $secure = [System.Security.SecureString]::new()
        foreach ($ch in 'example-only'.ToCharArray()) { $secure.AppendChar($ch) }
        [PSCredential]::new($User, $secure)
    }
}

AfterAll {
    foreach ($n in $script:EnvNames) { [System.Environment]::SetEnvironmentVariable($n, $script:SavedEnv[$n]) }
    Remove-Module CredentialManager -Force -ErrorAction SilentlyContinue
}

Describe 'CredentialManager Module' {
    BeforeEach {
        foreach ($n in $script:EnvNames) { [System.Environment]::SetEnvironmentVariable($n, $null) }
        # An empty project root: no keyvault-config.yml unless a test writes one.
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $script:Root 'config\credentials') -Force
        Mock Get-Credential -ModuleName CredentialManager { throw 'Get-Credential was called (prompt)' }
        Mock Read-Host -ModuleName CredentialManager { throw 'Read-Host was called (prompt)' }
        Mock Invoke-VaultSecretRead -ModuleName CredentialManager { throw "Key Vault must not be read in this test ($SecretName)" }
    }

    Context 'No interactive source' {
        It '<Function> -Source does not accept Interactive' -ForEach @(
            @{ Function = 'Get-ManagedCredential' }
            @{ Function = 'Get-ManagedSecret' }
        ) {
            $valid = (Get-Command $Function).Parameters['Source'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object { $_.ValidValues }
            $valid | Should -Not -Contain 'Interactive'
            $valid | Should -Be @('Auto', 'KeyVault', 'Environment', 'Parameter')
        }

        It 'Get-ManagedCredential -Source Interactive is rejected' {
            { Get-ManagedCredential -Name 'cluster_admin' -Source Interactive } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Get-ManagedCredential'
        }

        It 'Get-ManagedSecret -Source Interactive is rejected' {
            { Get-ManagedSecret -Name 'iic_test_key' -Source Interactive } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Get-ManagedSecret'
        }

        It 'Defaults to Auto and has no -Prompt parameter' {
            (Get-Command Get-ManagedCredential).Parameters.ContainsKey('Prompt') | Should -BeFalse
            $default = (Get-Command Get-ManagedCredential).ScriptBlock.Ast.Body.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'Source' } |
                ForEach-Object { $_.DefaultValue.Value }
            $default | Should -Be 'Auto'
        }

        It 'The module source contains no prompt command' {
            $text = Get-Content -LiteralPath $script:ModuleFile -Raw
            $text | Should -Not -Match 'Read-Host|Get-Credential|PromptForCredential|\$Host\.UI\.Prompt'
        }
    }

    Context 'Parameter source' {
        It 'Returns the credential the caller passes (Auto)' {
            $cred = New-TestCredential
            $result = Get-ManagedCredential -Name 'cluster_admin' -Credential $cred -ProjectRoot $script:Root
            $result.UserName | Should -Be 'iic\svc-loadtools'
        }

        It 'Accepts the -CredentialName alias the tool scripts use' {
            $result = Get-ManagedCredential -CredentialName 'cluster_admin' -Credential (New-TestCredential) -ProjectRoot $script:Root
            $result.UserName | Should -Be 'iic\svc-loadtools'
        }

        It '-Source Parameter without -Credential stops with a message' {
            { Get-ManagedCredential -Name 'cluster_admin' -Source Parameter -ProjectRoot $script:Root } |
                Should -Throw "*Pass -Credential*"
        }

        It 'Get-ManagedSecret returns -Value (Auto), also via -SecretName' {
            Get-ManagedSecret -SecretName 'iic_test_key' -Value 'example-value' -ProjectRoot $script:Root | Should -Be 'example-value'
        }
    }

    Context 'Environment source' {
        It 'Builds the credential from <NAME>_USERNAME and <NAME>_PASSWORD' {
            [System.Environment]::SetEnvironmentVariable('IIC_TEST_ADMIN_USERNAME', 'iic\svc-env')
            [System.Environment]::SetEnvironmentVariable('IIC_TEST_ADMIN_PASSWORD', 'example-only')
            $result = Get-ManagedCredential -Name 'iic_test_admin' -ProjectRoot $script:Root
            $result.UserName | Should -Be 'iic\svc-env'
            $result.GetNetworkCredential().Password | Should -Be 'example-only'
        }

        It 'A password without a user name stops with the variable names' {
            [System.Environment]::SetEnvironmentVariable('IIC_TEST_ADMIN_PASSWORD', 'example-only')
            { Get-ManagedCredential -Name 'iic_test_admin' -ProjectRoot $script:Root } |
                Should -Throw '*IIC_TEST_ADMIN_USERNAME*'
        }

        It 'Get-ManagedSecret reads the upper-case variable' {
            [System.Environment]::SetEnvironmentVariable('IIC_TEST_KEY', 'env-value')
            Get-ManagedSecret -Name 'iic_test_key' -ProjectRoot $script:Root | Should -Be 'env-value'
        }

        It 'Get-ManagedSecret reads -EnvironmentVariable when given' {
            [System.Environment]::SetEnvironmentVariable('IIC_CUSTOM_KEY', 'custom-value')
            Get-ManagedSecret -Name 'iic_test_key' -EnvironmentVariable 'IIC_CUSTOM_KEY' -ProjectRoot $script:Root | Should -Be 'custom-value'
        }

        It 'The environment wins over Key Vault in Auto' {
            Set-Content -LiteralPath (Join-Path $script:Root 'config\credentials\keyvault-config.yml') -Value @'
keyvault:
  name: "kv-iic-loadtools"
  secrets:
    iic_test_key: "iic-test-key"
'@
            [System.Environment]::SetEnvironmentVariable('IIC_TEST_KEY', 'env-value')
            Get-ManagedSecret -Name 'iic_test_key' -ProjectRoot $script:Root | Should -Be 'env-value'
            Should -Invoke Invoke-VaultSecretRead -ModuleName CredentialManager -Times 0 -Exactly
        }
    }

    Context 'Key Vault source' {
        BeforeEach {
            Set-Content -LiteralPath (Join-Path $script:Root 'config\credentials\keyvault-config.yml') -Value @'
keyvault:
  name: "kv-iic-loadtools"
  resource_group: "rg-iic-loadtools"
  secrets:
    cluster_admin_password: "hci-cluster-admin-pwd"
    cluster_admin_username: "hci-cluster-admin-user"
    log_analytics_key: "log-analytics-key"
'@
            Mock Invoke-VaultSecretRead -ModuleName CredentialManager {
                switch ($SecretName) {
                    'hci-cluster-admin-pwd' { 'example-only' }
                    'hci-cluster-admin-user' { 'iic\svc-vault' }
                    'log-analytics-key' { 'example-key' }
                    default { throw "unexpected secret $SecretName" }
                }
            }
        }

        It 'Auto reads <name>_password and <name>_username from the mapped vault' {
            $result = Get-ManagedCredential -Name 'cluster_admin' -ProjectRoot $script:Root
            $result.UserName | Should -Be 'iic\svc-vault'
            $result.GetNetworkCredential().Password | Should -Be 'example-only'
            Should -Invoke Invoke-VaultSecretRead -ModuleName CredentialManager -Times 1 -Exactly -ParameterFilter {
                $VaultName -eq 'kv-iic-loadtools' -and $SecretName -eq 'hci-cluster-admin-pwd'
            }
        }

        It '-Source KeyVault with -VaultConfigPath works' {
            $path = Join-Path $script:Root 'config\credentials\keyvault-config.yml'
            $result = Get-ManagedCredential -Name 'cluster_admin' -Source KeyVault -VaultConfigPath $path
            $result.UserName | Should -Be 'iic\svc-vault'
        }

        It 'Get-ManagedSecret reads the mapped secret' {
            Get-ManagedSecret -Name 'log_analytics_key' -ProjectRoot $script:Root | Should -Be 'example-key'
        }

        It '-Source KeyVault without a mapping stops with a message' {
            { Get-ManagedSecret -Name 'iic_test_key' -Source KeyVault -ProjectRoot $script:Root } |
                Should -Throw "*map it under keyvault.secrets*"
        }

        It 'A vault password without a user name mapping stops; no account name is assumed' {
            Set-Content -LiteralPath (Join-Path $script:Root 'config\credentials\keyvault-config.yml') -Value @'
keyvault:
  name: "kv-iic-loadtools"
  secrets:
    cluster_admin_password: "hci-cluster-admin-pwd"
'@
            { Get-ManagedCredential -Name 'cluster_admin' -ProjectRoot $script:Root } |
                Should -Throw "*No user name for credential 'cluster_admin'*cluster_admin_username*"
        }

        It 'An environment password without a user name falls through to Key Vault in Auto' {
            [System.Environment]::SetEnvironmentVariable('CLUSTER_ADMIN_PASSWORD', 'env-only')
            try {
                $result = Get-ManagedCredential -Name 'cluster_admin' -ProjectRoot $script:Root
                $result.UserName | Should -Be 'iic\svc-vault'
                $result.GetNetworkCredential().Password | Should -Be 'example-only'
            }
            finally { [System.Environment]::SetEnvironmentVariable('CLUSTER_ADMIN_PASSWORD', $null) }
        }
    }

    Context 'Nothing available' {
        It 'Get-ManagedCredential throws a message naming the parameter, the variables and the Key Vault mapping' {
            $err = $null
            try { Get-ManagedCredential -Name 'cluster_admin' -ProjectRoot $script:Root } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $msg = $err.Exception.Message
            $msg | Should -BeLike "No credential found for 'cluster_admin'*"
            $msg | Should -BeLike '*-Credential*'
            $msg | Should -BeLike '*CLUSTER_ADMIN_USERNAME*CLUSTER_ADMIN_PASSWORD*'
            $msg | Should -BeLike "*cluster_admin_password*keyvault-config.yml*"
            Should -Invoke Get-Credential -ModuleName CredentialManager -Times 0 -Exactly
            Should -Invoke Invoke-VaultSecretRead -ModuleName CredentialManager -Times 0 -Exactly
        }

        It 'Get-ManagedSecret throws a message naming the variable and the Key Vault mapping' {
            { Get-ManagedSecret -Name 'linux_ssh_username' -ProjectRoot $script:Root } |
                Should -Throw "No value found for secret 'linux_ssh_username'*LINUX_SSH_USERNAME*keyvault.secrets*"
            Should -Invoke Read-Host -ModuleName CredentialManager -Times 0 -Exactly
        }

        It 'A keyvault-config.yml without the mapping still stops with the message' {
            Set-Content -LiteralPath (Join-Path $script:Root 'config\credentials\keyvault-config.yml') -Value @'
keyvault:
  name: "kv-iic-loadtools"
  secrets:
    other_secret: "other"
'@
            { Get-ManagedCredential -Name 'cluster_admin' -ProjectRoot $script:Root } |
                Should -Throw "No credential found for 'cluster_admin'*"
        }
    }
}
