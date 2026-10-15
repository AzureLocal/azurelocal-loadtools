@{
    RootModule        = 'FaultInjection.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a1f0c5d2-7b3e-4c88-9e41-5d2a6b7c8e90'
    Author            = 'AzureLocal'
    CompanyName       = 'AzureLocal'
    Copyright         = '(c) 2026 AzureLocal. MIT License.'
    Description       = 'Opt-in failure injection (node pause, drive fault) with preflight refusal, undo-first printing and a fault lock, for load tests under failure conditions.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Get-FaultLock'
        'New-FaultPlan'
        'Test-FaultPreflight'
        'Get-FaultHealthSnapshot'
        'Invoke-FaultInjection'
        'Undo-FaultInjection'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('AzureLocal', 'LoadTesting', 'FaultInjection')
            ProjectUri = 'https://github.com/AzureLocal/azurelocal-loadtools'
        }
    }
}
