@{
    RootModule        = 'MonitoringManager.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'e5f6a7b8-c9d0-1234-efab-345678901234'
    Author            = 'AzureLocal'
    CompanyName       = 'AzureLocal'
    Copyright         = '(c) 2026 AzureLocal. MIT License.'
    Description       = 'Performance monitoring for Azure Local Load Tools. Collects PerfMon counters with optional Azure Monitor push.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Start-MetricCollection'
        'Stop-MetricCollection'
        'Get-MetricSummary'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{
        PSData = @{
            Tags       = @('AzureLocal', 'LoadTesting', 'Monitoring', 'PerfMon')
            ProjectUri = 'https://github.com/AzureLocal/azurelocal-loadtools'
        }
    }
}
