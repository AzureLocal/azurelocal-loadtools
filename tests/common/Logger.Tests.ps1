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

    Context 'Tool script call shape (no prompt)' {
        It 'Accepts -LogRootPath and -Severity Information, and Stop-LogSession without -SessionId closes the last session' {
            $logRoot = Join-Path $TestDrive 'logs6'
            $sessionId = Start-LogSession -Component 'ScriptShape' -LogRootPath $logRoot
            Write-Log -Message 'Info message' -Severity Information -SessionId $sessionId
            $entry = Get-Content -Path (Get-ChildItem -Path $logRoot -Filter '*.jsonl' -Recurse)[0].FullName -Tail 1 | ConvertFrom-Json
            $entry.severity | Should -Be 'INFO'
            Stop-LogSession
            Get-LogSession -SessionId $sessionId | Should -BeNullOrEmpty
        }

        It 'Stop-LogSession has no mandatory parameter' {
            (Get-Command Stop-LogSession).Parameters['SessionId'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
                Should -BeNullOrEmpty
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
