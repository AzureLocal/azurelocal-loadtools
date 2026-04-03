# =============================================================================
# StateManager.Tests.ps1 - Pester unit tests
# =============================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\common\modules\StateManager\StateManager.psm1'
    Import-Module $modulePath -Force
}

Describe 'StateManager Module' {
    BeforeEach {
        $testStateDir = Join-Path $TestDrive 'state'
        InModuleScope StateManager {
            $script:StateDir = $using:testStateDir
            $script:HistoryDir = Join-Path $using:testStateDir 'history'
        }
    }

    Context 'New-RunState' {
        It 'Should create a new run state file' {
            $state = New-RunState -RunId 'test-001' -Solution 'VMFleet' `
                -Phases @('Install', 'Deploy', 'Test')

            $state | Should -Not -BeNullOrEmpty
            $state.run_id | Should -Be 'test-001'
            $state.solution | Should -Be 'VMFleet'
            $state.phases.Count | Should -Be 3

            $stateDir = InModuleScope StateManager { $script:StateDir }
            Test-Path (Join-Path $stateDir 'run-state.json') | Should -BeTrue
        }
    }

    Context 'Update-RunPhase' {
        It 'Should update phase status' {
            New-RunState -RunId 'test-002' -Solution 'VMFleet' `
                -Phases @('Install', 'Deploy')

            Update-RunPhase -Phase 'Install' -Status 'Running'
            $state = Get-RunState

            $state.phases.Install.status | Should -Be 'Running'
        }

        It 'Should set start_time when status is Running' {
            New-RunState -RunId 'test-003' -Solution 'VMFleet' `
                -Phases @('Install')

            Update-RunPhase -Phase 'Install' -Status 'running'
            $state = Get-RunState

            $state.phases.Install.started_at | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Test-PhaseCompleted' {
        It 'Should return true for completed phases' {
            New-RunState -RunId 'test-004' -Solution 'VMFleet' `
                -Phases @('Install')

            Update-RunPhase -Phase 'Install' -Status 'completed'

            Test-PhaseCompleted -Phase 'Install' | Should -BeTrue
        }

        It 'Should return false for pending phases' {
            New-RunState -RunId 'test-005' -Solution 'VMFleet' `
                -Phases @('Install')

            Test-PhaseCompleted -Phase 'Install' | Should -BeFalse
        }
    }
}

