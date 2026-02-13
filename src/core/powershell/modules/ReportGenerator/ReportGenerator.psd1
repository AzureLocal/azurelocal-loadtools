@{
    RootModule        = 'ReportGenerator.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'f4e27c3a-8b19-4d5e-a6c1-9f3d7e2b8a45'
    Author            = 'Azure Local Load Tools'
    Description       = 'Test report generation in PDF, DOCX, and XLSX formats.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'New-TestReport'
        'Import-TestResults'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData = @{
        PSData = @{
            Tags       = @('AzureLocal', 'LoadTest', 'Reports')
            ProjectUri = 'https://github.com/AzureLocal/azurelocal-loadtools'
        }
    }
}
