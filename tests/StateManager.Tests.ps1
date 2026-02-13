# =============================================================================
# StateManager.Tests.ps1 - Pester unit tests
# =============================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\src\core\powershell\modules\StateManager\StateManager.psm1'
    Import-Module $modulePath -Force
}

Describe 'StateManager Module' {
    Context 'New-RunState' {
        It 'Should create a new run state file' {
            $stateDir = Join-Path $TestDrive 'state'
            $state = New-RunState -RunId 'test-001' -Solution 'VMFleet' `
                -Phases @('Install', 'Deploy', 'Test') -StateDirectory $stateDir

            $state | Should -Not -BeNullOrEmpty
            $state.run_id | Should -Be 'test-001'
            $state.solution | Should -Be 'VMFleet'
            $state.phases.Count | Should -Be 3

            Test-Path (Join-Path $stateDir 'test-001.json') | Should -BeTrue
        }
    }

    Context 'Update-RunPhase' {
        It 'Should update phase status' {
            $stateDir = Join-Path $TestDrive 'state2'
            New-RunState -RunId 'test-002' -Solution 'VMFleet' `
                -Phases @('Install', 'Deploy') -StateDirectory $stateDir

            Update-RunPhase -RunId 'test-002' -Phase 'Install' -Status 'Running' -StateDirectory $stateDir
            $state = Get-RunState -StateDirectory $stateDir

            ($state.phases | Where-Object { $_.name -eq 'Install' }).status | Should -Be 'Running'
        }

        It 'Should set start_time when status is Running' {
            $stateDir = Join-Path $TestDrive 'state3'
            New-RunState -RunId 'test-003' -Solution 'VMFleet' `
                -Phases @('Install') -StateDirectory $stateDir

            Update-RunPhase -RunId 'test-003' -Phase 'Install' -Status 'Running' -StateDirectory $stateDir
            $state = Get-RunState -StateDirectory $stateDir

            ($state.phases | Where-Object { $_.name -eq 'Install' }).start_time | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Test-PhaseCompleted' {
        It 'Should return true for completed phases' {
            $stateDir = Join-Path $TestDrive 'state4'
            New-RunState -RunId 'test-004' -Solution 'VMFleet' `
                -Phases @('Install') -StateDirectory $stateDir

            Update-RunPhase -RunId 'test-004' -Phase 'Install' -Status 'Completed' -StateDirectory $stateDir

            Test-PhaseCompleted -RunId 'test-004' -Phase 'Install' -StateDirectory $stateDir | Should -BeTrue
        }

        It 'Should return false for pending phases' {
            $stateDir = Join-Path $TestDrive 'state5'
            New-RunState -RunId 'test-005' -Solution 'VMFleet' `
                -Phases @('Install') -StateDirectory $stateDir

            Test-PhaseCompleted -RunId 'test-005' -Phase 'Install' -StateDirectory $stateDir | Should -BeFalse
        }
    }
}
