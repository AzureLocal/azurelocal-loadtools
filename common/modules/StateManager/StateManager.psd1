@{
    RootModule        = 'StateManager.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c3d4e5f6-a7b8-9012-cdef-123456789012'
    Author            = 'AzureLocal'
    CompanyName       = 'AzureLocal'
    Copyright         = '(c) 2026 AzureLocal. MIT License.'
    Description       = 'Run state tracking, checkpoints, and resume capability for Azure Local Load Tools.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'New-RunState'
        'Get-RunState'
        'Update-RunPhase'
        'Test-PhaseCompleted'
        'Complete-Run'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{
        PSData = @{
            Tags       = @('AzureLocal', 'LoadTesting', 'StateManagement')
            ProjectUri = 'https://github.com/AzureLocal/azurelocal-loadtools'
        }
    }
}
