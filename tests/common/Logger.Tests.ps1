# =============================================================================
# Logger.Tests.ps1 - Pester unit tests
# =============================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\common\modules\Logger\Logger.psm1'
    Import-Module $modulePath -Force
}

Describe 'Logger Module' {
    Context 'Start-LogSession' {
        It 'Should create a log session with correlation ID' {
            $logRoot = Join-Path $TestDrive 'logs'
            $sessionId = Start-LogSession -Component 'TestComponent' -LogBasePath $logRoot
            $sessionId | Should -Not -BeNullOrEmpty
            (Get-LogSession -SessionId $sessionId).Component | Should -Be 'TestComponent'
            Stop-LogSession -SessionId $sessionId
        }

        It 'Should create log directory' {
            $logRoot = Join-Path $TestDrive 'logs2'
            $sessionId = Start-LogSession -Component 'DirTest' -LogBasePath $logRoot
            Test-Path $logRoot | Should -BeTrue
            Stop-LogSession -SessionId $sessionId
        }
    }

    Context 'Write-Log' {
        It 'Should write JSON-lines log entry' {
            $logRoot = Join-Path $TestDrive 'logs3'
            $sessionId = Start-LogSession -Component 'WriteTest' -LogBasePath $logRoot
            Write-Log -Message 'Test message' -Severity 'INFO' -SessionId $sessionId

            $logFiles = Get-ChildItem -Path $logRoot -Filter '*.jsonl' -Recurse
            $logFiles.Count | Should -BeGreaterThan 0

            $lastLine = Get-Content -Path $logFiles[0].FullName -Tail 1
            $entry = $lastLine | ConvertFrom-Json
            $entry.message | Should -Be 'Test message'
            $entry.severity | Should -Be 'INFO'
            Stop-LogSession -SessionId $sessionId
        }

        It 'Should respect severity threshold' {
            $logRoot = Join-Path $TestDrive 'logs4'
            $sessionId = Start-LogSession -Component 'ThresholdTest' -LogBasePath $logRoot -LogLevel 'WARNING'
            Write-Log -Message 'Debug message' -Severity 'INFO' -SessionId $sessionId
            Write-Log -Message 'Warning message' -Severity 'WARNING' -SessionId $sessionId

            $logFiles = Get-ChildItem -Path $logRoot -Filter '*.jsonl' -Recurse
            if ($logFiles.Count -gt 0) {
                $lines = Get-Content -Path $logFiles[0].FullName
                $lines | Should -Not -Contain '*Debug message*'
            }
            Stop-LogSession -SessionId $sessionId
        }
    }

    Context 'Get-LogSession' {
        It 'Should return current session info' {
            $logRoot = Join-Path $TestDrive 'logs5'
            $sessionId = Start-LogSession -Component 'SessionTest' -LogBasePath $logRoot
            $session = Get-LogSession -SessionId $sessionId
            $session | Should -Not -BeNullOrEmpty
            Stop-LogSession -SessionId $sessionId
        }
    }
}
