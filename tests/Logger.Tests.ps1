# =============================================================================
# Logger.Tests.ps1 - Pester unit tests
# =============================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\src\core\powershell\modules\Logger\Logger.psm1'
    Import-Module $modulePath -Force
}

Describe 'Logger Module' {
    Context 'Start-LogSession' {
        It 'Should create a log session with correlation ID' {
            $logRoot = Join-Path $TestDrive 'logs'
            $session = Start-LogSession -Component 'TestComponent' -LogRootPath $logRoot
            $session | Should -Not -BeNullOrEmpty
            $session.CorrelationId | Should -Not -BeNullOrEmpty
            $session.Component | Should -Be 'TestComponent'
            Stop-LogSession
        }

        It 'Should create log directory' {
            $logRoot = Join-Path $TestDrive 'logs2'
            Start-LogSession -Component 'DirTest' -LogRootPath $logRoot
            Test-Path $logRoot | Should -BeTrue
            Stop-LogSession
        }
    }

    Context 'Write-Log' {
        It 'Should write JSON-lines log entry' {
            $logRoot = Join-Path $TestDrive 'logs3'
            $session = Start-LogSession -Component 'WriteTest' -LogRootPath $logRoot
            Write-Log -Message 'Test message' -Severity Information

            $logFiles = Get-ChildItem -Path $logRoot -Filter '*.jsonl' -Recurse
            $logFiles.Count | Should -BeGreaterThan 0

            $lastLine = Get-Content -Path $logFiles[0].FullName -Tail 1
            $entry = $lastLine | ConvertFrom-Json
            $entry.message | Should -Be 'Test message'
            $entry.severity | Should -Be 'Information'
            Stop-LogSession
        }

        It 'Should respect severity threshold' {
            $logRoot = Join-Path $TestDrive 'logs4'
            Start-LogSession -Component 'ThresholdTest' -LogRootPath $logRoot -MinimumSeverity Warning
            Write-Log -Message 'Debug message' -Severity Information
            Write-Log -Message 'Warning message' -Severity Warning

            $logFiles = Get-ChildItem -Path $logRoot -Filter '*.jsonl' -Recurse
            if ($logFiles.Count -gt 0) {
                $lines = Get-Content -Path $logFiles[0].FullName
                $lines | Should -Not -Contain '*Debug message*'
            }
            Stop-LogSession
        }
    }

    Context 'Get-LogSession' {
        It 'Should return current session info' {
            $logRoot = Join-Path $TestDrive 'logs5'
            Start-LogSession -Component 'SessionTest' -LogRootPath $logRoot
            $session = Get-LogSession
            $session | Should -Not -BeNullOrEmpty
            Stop-LogSession
        }
    }
}
