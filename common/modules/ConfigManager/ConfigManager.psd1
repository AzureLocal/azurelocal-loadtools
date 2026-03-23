@{
    RootModule        = 'ConfigManager.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'AzureLocal'
    CompanyName       = 'AzureLocal'
    Copyright         = '(c) 2026 AzureLocal. MIT License.'
    Description       = 'Configuration management for Azure Local Load Tools. Reads master environment YAML, filters by solution tags, generates solution-specific JSON configs.'
    PowerShellVersion = '7.2'
    RequiredModules   = @('powershell-yaml')
    FunctionsToExport = @(
        'Import-MasterConfig'
        'Export-SolutionConfig'
        'Export-AllSolutionConfigs'
        'Get-ConfigValue'
        'Test-MasterConfig'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{
        PSData = @{
            Tags       = @('AzureLocal', 'LoadTesting', 'Configuration')
            ProjectUri = 'https://github.com/AzureLocal/azurelocal-loadtools'
        }
    }
}
