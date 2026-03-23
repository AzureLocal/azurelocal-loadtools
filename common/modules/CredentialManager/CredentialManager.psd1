@{
    RootModule        = 'CredentialManager.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'd4e5f6a7-b8c9-0123-defa-234567890123'
    Author            = 'AzureLocal'
    CompanyName       = 'AzureLocal'
    Copyright         = '(c) 2026 AzureLocal. MIT License.'
    Description       = 'Credential management for Azure Local Load Tools. Supports Azure Key Vault, interactive prompt, and parameter injection.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Get-ManagedCredential'
        'Get-ManagedSecret'
        'Import-VaultConfig'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{
        PSData = @{
            Tags       = @('AzureLocal', 'LoadTesting', 'Credentials', 'KeyVault')
            ProjectUri = 'https://github.com/AzureLocal/azurelocal-loadtools'
        }
    }
}
