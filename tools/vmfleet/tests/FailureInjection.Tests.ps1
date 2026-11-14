# =============================================================================
# FailureInjection.Tests.ps1 - the failure-injection profile and wrappers stay opt-in
# =============================================================================

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:Scripts = Join-Path $script:ProjectRoot 'tools\vmfleet\scripts'
    $script:Profiles = Join-Path $script:ProjectRoot 'tools\vmfleet\config\profiles'
}

Describe 'Failure injection stays opt-in' {
    It 'parses <Name>' -ForEach @(@{ Name = 'Invoke-VMFleetFault.ps1' }, @{ Name = 'Undo-VMFleetFault.ps1' }) {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Scripts $Name), [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It '<Name> declares -AllowFault as a plain switch with no default and ConfirmImpact High' -ForEach @(@{ Name = 'Invoke-VMFleetFault.ps1' }, @{ Name = 'Undo-VMFleetFault.ps1' }) {
        $text = Get-Content -Path (Join-Path $script:Scripts $Name) -Raw
        $text | Should -Match '\[switch\]\$AllowFault'
        $text | Should -Not -Match '\$AllowFault\s*=\s*\$true'
        $text | Should -Match "ConfirmImpact = 'High'"
    }

    It '<Name> passes a wait to the module only when the operator gave it, and names the config file' -ForEach @(
        @{ Name = 'Invoke-VMFleetFault.ps1'; Params = @('DrainTimeoutMinutes') }
        @{ Name = 'Undo-VMFleetFault.ps1'; Params = @('ResyncTimeoutMinutes', 'PollSeconds', 'SettleObservations') }
    ) {
        $path = Join-Path $script:Scripts $Name
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $declared = @($ast.ParamBlock.Parameters)
        foreach ($p in $Params + 'SolutionConfigPath') {
            $param = @($declared | Where-Object { $_.Name.VariablePath.UserPath -eq $p })
            $param.Count | Should -Be 1 -Because "$Name declares -$p"
            $param[0].DefaultValue | Should -BeNullOrEmpty -Because "-$p takes its default from the config file, not from a literal"
        }
        $text = Get-Content -Path $path -Raw
        $text | Should -Match 'PSBoundParameters'
        $text | Should -Match 'tools\\vmfleet\\config\\vmfleet\.json'
    }

    It 'the pipeline and the phase scripts never reference the fault module' {
        $files = @(Join-Path $script:ProjectRoot 'tools\vmfleet\Invoke-VMFleetPipeline.ps1') +
        @(Get-ChildItem -Path $script:Scripts -Filter '*.ps1' | Where-Object { $_.Name -notmatch 'VMFleetFault' } | ForEach-Object FullName)
        foreach ($f in $files) {
            (Get-Content -Path $f -Raw) | Should -Not -Match 'FaultInjection|AllowFault'
        }
    }

    It 'only the failure-injection profile carries a fault section, and it injects nothing by default' {
        if (-not (Get-Module -ListAvailable -Name powershell-yaml)) { Set-ItResult -Skipped -Because 'powershell-yaml not installed'; return }
        Import-Module powershell-yaml
        foreach ($f in Get-ChildItem -Path $script:Profiles -Filter '*.yml') {
            $data = Get-Content -Path $f.FullName -Raw | ConvertFrom-Yaml
            if ($f.Name -eq 'failure-injection.yml') {
                $data.profile.opt_in | Should -BeTrue
                $data.profile.failure_injection.default_fault | Should -Be 'none'
                $data.profile.failure_injection.requires_flags | Should -Contain '-AllowFault'
            }
            else {
                $data.profile.ContainsKey('failure_injection') | Should -BeFalse
            }
        }
    }
}
