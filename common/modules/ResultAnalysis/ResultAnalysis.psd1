@{
    RootModule        = 'ResultAnalysis.psm1'
    ModuleVersion     = '0.1.0' # x-release-please-version
    GUID              = 'b7c2e4a9-3d51-4f06-8a1e-9c0d2f6e7a13'
    Author            = 'AzureLocal'
    CompanyName       = 'AzureLocal'
    Copyright         = '(c) 2026 AzureLocal. MIT License.'
    Description       = 'Offline result normalisation, HTML + CSV report, baseline comparison with a regression threshold exit code, and trend.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Get-ResultMetricDefinition'
        'ConvertTo-NormalizedResult'
        'Test-ResultComparable'
        'Compare-LoadTestResult'
        'Get-ResultTrend'
        'New-ResultReport'
        'New-Day2SmokeResult'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('AzureLocal', 'LoadTesting', 'Reporting')
            ProjectUri = 'https://github.com/AzureLocal/azurelocal-loadtools'
        }
    }
}
