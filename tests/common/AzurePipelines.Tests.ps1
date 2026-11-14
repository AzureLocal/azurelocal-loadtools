#Requires -Version 7.0
# The Azure DevOps pipelines name no project-specific value as a literal: the VMFleet run takes its variable group from a
# pipeline input, so each Azure DevOps project sets its own group name.
BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop
    $script:VmFleetPipeline = Join-Path $PSScriptRoot '..\..\.azuredevops\azure-pipelines-vmfleet.yml'
    $script:Pipeline = ConvertFrom-Yaml (Get-Content -LiteralPath $script:VmFleetPipeline -Raw) -Ordered
}

Describe 'Azure DevOps VMFleet pipeline' {
    It 'has the input variableGroup, a string with a default' {
        $p = @($script:Pipeline.parameters | Where-Object { $_.name -eq 'variableGroup' })
        $p.Count | Should -Be 1
        $p[0].type | Should -Be 'string'
        $p[0].default | Should -Not -BeNullOrEmpty
    }

    It 'names its variable group only through that input' {
        $groups = @($script:Pipeline.variables | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('group') } | ForEach-Object { [string]$_.group })
        $groups | Should -Be @('${{ parameters.variableGroup }}')
    }
}
