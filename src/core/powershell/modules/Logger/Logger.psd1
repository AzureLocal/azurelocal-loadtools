@{
    RootModule        = 'Logger.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
    Author            = 'AzureLocal'
    CompanyName       = 'AzureLocal'
    Copyright         = '(c) 2026 AzureLocal. MIT License.'
    Description       = 'Structured JSON-lines logging for Azure Local Load Tools with correlation IDs and per-component log separation.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Start-LogSession'
        'Write-Log'
        'Stop-LogSession'
        'Get-LogSession'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{
        PSData = @{
            Tags       = @('AzureLocal', 'LoadTesting', 'Logging')
            ProjectUri = 'https://github.com/AzureLocal/azurelocal-loadtools'
        }
    }
}
