#Requires -Version 7.0
# The pipelines name no project-specific value as a literal: the VMFleet run takes its variable group and its agent pool
# from pipeline inputs, so each Azure DevOps project and organization sets its own names. A hosted-image label, the
# GitHub Pages environment and a job timeout stay in the files only with a comment that says why.
BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:PipelineFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $root '.azuredevops') -Filter '*.yml' -File
        Get-Item -LiteralPath (Join-Path $root 'azure-pipelines.yml')
        Get-ChildItem -LiteralPath (Join-Path $root '.github\workflows') -Filter '*.yml' -File
    ) | ForEach-Object { @{ Path = $_.FullName; Name = $_.Name } }
}

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop
    $script:VmFleetPipeline = Join-Path $PSScriptRoot '..\..\.azuredevops\azure-pipelines-vmfleet.yml'
    $script:Pipeline = ConvertFrom-Yaml (Get-Content -LiteralPath $script:VmFleetPipeline -Raw) -Ordered
    # Vendor labels of hosted images, used only by jobs that read nothing of a deployment.
    $script:HostedLabels = @('windows-latest', 'ubuntu-latest')

    # Every value under a given key, anywhere in a parsed YAML document.
    function script:Find-YamlKey {
        param($Node, [string]$Key)
        if ($Node -is [System.Collections.IDictionary]) {
            foreach ($k in @($Node.Keys)) {
                if ($k -eq $Key) { , $Node[$k] }
                Find-YamlKey -Node $Node[$k] -Key $Key
            }
        }
        elseif ($Node -is [System.Collections.IList]) {
            foreach ($item in $Node) { Find-YamlKey -Node $item -Key $Key }
        }
    }

    # True when the first line matching the pattern carries a comment, or one of the three lines above it is a comment.
    function script:Test-CommentAbove {
        param([string]$Path, [string]$Pattern)
        $lines = @(Get-Content -LiteralPath $Path)
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $Pattern) {
                if ($lines[$i] -match '#') { return $true }
                $from = [math]::Max(0, $i - 3)
                return (@($lines[$from..($i - 1)] | Where-Object { $_ -match '^\s*#' }).Count -gt 0)
            }
        }
        $false
    }
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

    It 'has the input agentPool, a string with no default (the run form asks for it)' {
        $p = @($script:Pipeline.parameters | Where-Object { $_.name -eq 'agentPool' })
        $p.Count | Should -Be 1
        $p[0].type | Should -Be 'string'
        $p[0].Contains('default') | Should -BeFalse
    }

    It 'takes the pool of its job only from agentPool, with no pipeline-level pool' {
        $script:Pipeline.Contains('pool') | Should -BeFalse
        $pools = @(Find-YamlKey -Node $script:Pipeline -Key 'pool')
        $pools.Count | Should -Be 1
        $pools[0].name | Should -Be '${{ parameters.agentPool }}'
    }

    It 'takes the job timeout from the input jobTimeoutMinutes (a number, default 120, its reason in a comment)' {
        $p = @($script:Pipeline.parameters | Where-Object { $_.name -eq 'jobTimeoutMinutes' })
        $p.Count | Should -Be 1
        $p[0].type | Should -Be 'number'
        $p[0].default | Should -Be 120
        @(Find-YamlKey -Node $script:Pipeline -Key 'timeoutInMinutes') | Should -Be @('${{ parameters.jobTimeoutMinutes }}')
        Test-CommentAbove -Path $script:VmFleetPipeline -Pattern 'name:\s*jobTimeoutMinutes' | Should -BeTrue
    }
}

Describe 'Pipeline file <Name>' -ForEach $script:PipelineFiles {
    BeforeAll {
        $script:Doc = ConvertFrom-Yaml (Get-Content -LiteralPath $Path -Raw) -Ordered
    }

    It 'types no agent pool name; a hosted image is a vendor label with a comment' {
        foreach ($pool in @(Find-YamlKey -Node $script:Doc -Key 'pool')) {
            if ($pool -is [string]) { $pool | Should -Match '^\$\{\{\s*parameters\.' }
            elseif ($pool.Contains('vmImage')) {
                $pool.vmImage | Should -BeIn $script:HostedLabels
                Test-CommentAbove -Path $Path -Pattern 'vmImage:' | Should -BeTrue
            }
            else { $pool.name | Should -Match '^\$\{\{\s*parameters\.' }
        }
    }

    It 'types no variable group name' {
        foreach ($vars in @(Find-YamlKey -Node $script:Doc -Key 'variables' | Where-Object { $_ -is [System.Collections.IList] })) {
            foreach ($entry in @($vars | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('group') })) {
                [string]$entry.group | Should -Match '^\$\{\{\s*parameters\.'
            }
        }
    }

    It 'uses only hosted runner labels, each with a comment' {
        foreach ($label in @(Find-YamlKey -Node $script:Doc -Key 'runs-on')) {
            $label | Should -BeIn $script:HostedLabels
        }
        if ((Get-Content -LiteralPath $Path -Raw) -match 'runs-on:') {
            Test-CommentAbove -Path $Path -Pattern 'runs-on:' | Should -BeTrue
        }
    }

    It 'names no environment but the GitHub Pages one, with a comment' {
        foreach ($env in @(Find-YamlKey -Node $script:Doc -Key 'environment')) {
            $name = if ($env -is [System.Collections.IDictionary]) { $env.name } else { $env }
            $name | Should -Be 'github-pages'
            Test-CommentAbove -Path $Path -Pattern '^\s*environment:' | Should -BeTrue
        }
    }
}
