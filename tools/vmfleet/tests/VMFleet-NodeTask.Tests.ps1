# =============================================================================
# VMFleet-NodeTask.Tests.ps1 - Pester unit tests for the shared VMFleet helper
# =============================================================================
# Covers VMFleet-Common.ps1: cluster config, parameter resolution, the one-shot
# scheduled-task runner (remoting and the task are mocked) and the generated node
# wrapper (run locally in Windows PowerShell 5.1 against a local named pipe).
# Nothing here touches a cluster, a node or Azure.
# =============================================================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Fake credentials for unit tests.')]
param()

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:ScriptsPath = Join-Path $script:ProjectRoot 'tools\vmfleet\scripts'
    $script:ProfilesPath = Join-Path $script:ProjectRoot 'tools\vmfleet\config\profiles'
    . (Join-Path $script:ScriptsPath 'VMFleet-Common.ps1')
    $script:Node = '192.0.2.11'
    Import-Module powershell-yaml -ErrorAction Stop

    function script:New-TestClusterYaml {
        param([string]$Yaml)
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.yml')
        Set-Content -LiteralPath $path -Value $Yaml -Encoding utf8
        $path
    }
}

Describe 'Get-VMFleetClusterConfig' {
    It 'reads the nodes (management IPs), the Collect volume and the base VHD from the documented layout' {
        $path = New-TestClusterYaml @'
cluster:
  name: "azl-cluster-01"
nodes:
  - name: "192.0.2.11"
    hostname: "azl-node-01"
  - name: "192.0.2.12"
storage:
  collect_path: "C:\\ClusterStorage\\Collect\\"
  node_volumes:
    - "C:\\ClusterStorage\\azl-node-01"
  base_vhd_path: "C:\\ClusterStorage\\Collect\\base\\base.vhdx"
'@
        $c = Get-VMFleetClusterConfig -ClusterConfigPath $path
        $c.ClusterName | Should -Be 'azl-cluster-01'
        $c.Nodes | Should -Be @('192.0.2.11', '192.0.2.12')
        $c.PrimaryNode | Should -Be '192.0.2.11'
        $c.Hostnames[0] | Should -Be 'azl-node-01'
        $c.CollectPath | Should -Be 'C:\ClusterStorage\Collect'
        $c.NodeVolumes | Should -Be @('C:\ClusterStorage\azl-node-01')
        $c.BaseVhdPath | Should -Be 'C:\ClusterStorage\Collect\base\base.vhdx'
    }

    It 'still reads the older nested layout (cluster.nodes[].management_ip) and prefers the management IP' {
        $path = New-TestClusterYaml @'
cluster:
  name: "nested"
  nodes:
    - name: "azl-node-01"
      management_ip: "192.0.2.21"
  collect_volume_path: "C:\\ClusterStorage\\Collect"
  base_vhd_path: "C:\\ClusterStorage\\Collect\\BaseImage.vhdx"
'@
        $c = Get-VMFleetClusterConfig -ClusterConfigPath $path
        $c.Nodes | Should -Be @('192.0.2.21')
        $c.Hostnames | Should -Be @('azl-node-01')
        $c.BaseVhdPath | Should -Be 'C:\ClusterStorage\Collect\BaseImage.vhdx'
    }

    It 'defaults the Collect volume to C:\ClusterStorage\Collect' {
        $path = New-TestClusterYaml "nodes:`n  - '192.0.2.31'`n"
        (Get-VMFleetClusterConfig -ClusterConfigPath $path).CollectPath | Should -Be 'C:\ClusterStorage\Collect'
    }

    It 'says what to do when the file is missing' {
        { Get-VMFleetClusterConfig -ClusterConfigPath (Join-Path $TestDrive 'nope.yml') } | Should -Throw '*example-cluster.yml*'
    }

    It 'throws when no node is listed' {
        $path = New-TestClusterYaml "cluster:`n  name: x`n"
        { Get-VMFleetClusterConfig -ClusterConfigPath $path } | Should -Throw '*no nodes*'
    }

    It 'the shipped example parses and uses only documentation addresses' {
        $c = Get-VMFleetClusterConfig -ClusterConfigPath (Join-Path $script:ProjectRoot 'config\clusters\example-cluster.yml')
        $c.Nodes.Count | Should -BeGreaterThan 1
        foreach ($n in $c.Nodes) { $n | Should -Match '^192\.0\.2\.\d+$' }
    }

    It 'the default cluster config path is config\clusters\cluster.yml, which is git-ignored' {
        Get-VMFleetDefaultClusterConfigPath -ProjectRoot $TestDrive | Should -Be (Join-Path $TestDrive 'config\clusters\cluster.yml')
        (Get-Content -LiteralPath (Join-Path $script:ProjectRoot '.gitignore') -Raw) | Should -Match 'config/clusters/\*\.yml'
    }
}

Describe 'Resolve-VMFleetTestParameters' {
    BeforeAll {
        $script:Solution = Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'tools\vmfleet\config\vmfleet.json') -Raw | ConvertFrom-Json
    }

    It 'reads the Day2Smoke profile from profile.parameters (duration_seconds, warmup_seconds)' {
        $p = Resolve-VMFleetTestParameters -LoadProfile (Import-VMFleetProfile -ProfilePath (Join-Path $script:ProfilesPath 'day2-smoke.yml')) -SolutionConfig $script:Solution
        $p.ProfileName | Should -Be 'Day2Smoke'
        $p.DurationSeconds | Should -Be 600
        $p.WarmupSeconds | Should -Be 120
        $p.CooldownSeconds | Should -Be 30
        $p.BlockSizeKB | Should -Be 8
        $p.WriteRatio | Should -Be 30
        $p.OutstandingIO | Should -Be 8
        $p.ThreadsPerVM | Should -Be 2
        $p.Pattern | Should -Be 'r'
        $p.Mixed | Should -BeTrue
        $p.TotalSeconds | Should -Be 750
    }

    It 'reads the General profile (300 s measured, 60 s warm-up)' {
        $p = Resolve-VMFleetTestParameters -LoadProfile (Import-VMFleetProfile -ProfilePath (Join-Path $script:ProfilesPath 'general.yml')) -SolutionConfig $script:Solution
        $p.ProfileName | Should -Be 'General'
        $p.DurationSeconds | Should -Be 300
        $p.WarmupSeconds | Should -Be 60
    }

    It 'falls back to the solution JSON keys (test_duration_seconds, warmup_seconds, cooldown_seconds) without a profile' {
        $p = Resolve-VMFleetTestParameters -LoadProfile $null -SolutionConfig $script:Solution
        $p.ProfileName | Should -Be 'custom'
        $p.DurationSeconds | Should -Be $script:Solution.test_duration_seconds
        $p.WarmupSeconds | Should -Be $script:Solution.warmup_seconds
        $p.CooldownSeconds | Should -Be $script:Solution.cooldown_seconds
    }

    It 'an explicit parameter beats the profile, and a zero write ratio is honoured' {
        $loadProfile = Import-VMFleetProfile -ProfilePath (Join-Path $script:ProfilesPath 'general.yml')
        $p = Resolve-VMFleetTestParameters -LoadProfile $loadProfile -SolutionConfig $script:Solution -Override @{ DurationSeconds = 45; WriteRatio = 0; BlockSize = '64k'; RandomRatio = 0 }
        $p.DurationSeconds | Should -Be 45
        $p.WriteRatio | Should -Be 0
        $p.BlockSizeKB | Should -Be 64
        $p.Pattern | Should -Be 's'
        $p.Mixed | Should -BeFalse
    }

    It 'still reads the older profile keys duration and warmup' {
        $p = Resolve-VMFleetTestParameters -LoadProfile @{ profile = @{ name = 'Old'; parameters = @{ duration = 11; warmup = 7 } } } -SolutionConfig $script:Solution
        $p.DurationSeconds | Should -Be 11
        $p.WarmupSeconds | Should -Be 7
    }

    It 'rejects a write ratio outside 0-100' {
        { Resolve-VMFleetTestParameters -LoadProfile $null -SolutionConfig $script:Solution -Override @{ WriteRatio = 101 } } | Should -Throw '*write_ratio*'
    }

    It '<Text> is <KB> KB' -ForEach @(
        @{ Text = '8k'; KB = 8 }, @{ Text = '64K'; KB = 64 }, @{ Text = '1m'; KB = 1024 }, @{ Text = '4'; KB = 4 }
    ) {
        ConvertTo-VMFleetBlockSizeKB -BlockSize $Text | Should -Be $KB
    }

    It 'rejects a block size it cannot read' {
        { ConvertTo-VMFleetBlockSizeKB -BlockSize '8kb' } | Should -Throw
    }
}

Describe 'Report format support' {
    It 'HTML needs no tool' {
        (Get-VMFleetReportFormatSupport -Format HTML).Available | Should -BeTrue
    }

    It 'PDF is unavailable, with the reason, when asciidoctor-pdf is missing' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'asciidoctor-pdf' }
        $s = Get-VMFleetReportFormatSupport -Format PDF
        $s.Available | Should -BeFalse
        $s.Reason | Should -Match 'asciidoctor-pdf'
    }

    It 'XLSX is unavailable when the ImportExcel module is missing, available when present' {
        Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ImportExcel' }
        (Get-VMFleetReportFormatSupport -Format XLSX).Available | Should -BeFalse
        Mock Get-Module { [pscustomobject]@{ Name = 'ImportExcel' } } -ParameterFilter { $Name -eq 'ImportExcel' }
        (Get-VMFleetReportFormatSupport -Format XLSX).Available | Should -BeTrue
    }

    It 'DOCX needs both asciidoctor and pandoc' {
        Mock Get-Command { [pscustomobject]@{ Name = 'asciidoctor' } } -ParameterFilter { $Name -eq 'asciidoctor' }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pandoc' }
        $s = Get-VMFleetReportFormatSupport -Format DOCX
        $s.Available | Should -BeFalse
        $s.Reason | Should -Match 'pandoc'
        $s.Reason | Should -Not -Match 'asciidoctor'
    }
}

Describe 'Node task handle' {
    It 'is deterministic: the same run and step give the same task name and run folder' {
        $a = Get-VMFleetNodeTaskHandle -ComputerName $script:Node -RunId 'day2smoke-20261124-101500' -Step 'Test' -CollectPath 'C:\ClusterStorage\Collect\'
        $b = Get-VMFleetNodeTaskHandle -ComputerName $script:Node -RunId 'day2smoke-20261124-101500' -Step 'Test' -CollectPath 'C:\ClusterStorage\Collect'
        $a.TaskName | Should -Be $b.TaskName
        $a.TaskName | Should -Be 'LoadTools-VMFleet-Test-day2smoke20261124101500'
        $a.RunDir | Should -Be 'C:\ClusterStorage\Collect\loadtools\day2smoke20261124101500\Test'
        $a.TranscriptPath | Should -Be "$($a.RunDir)\transcript.log"
        $a.ResultPath | Should -Be "$($a.RunDir)\result.json"
        $a.TaskPath | Should -Be '\LoadTools\'
    }
}

Describe 'Start-VMFleetNodeTask' {
    BeforeAll {
        $script:Cred = [pscredential]::new('CONTOSO\labadmin', (ConvertTo-SecureString 'Node-Pass-0001!' -AsPlainText -Force))
    }
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        Mock Open-VMFleetNodeSession { [pscustomobject]@{ Id = 1; ComputerName = $ComputerName } }
        Mock Close-VMFleetNodeSession { }
        Mock Invoke-VMFleetSessionCommand { $script:Calls.Add([pscustomobject]@{ Block = $ScriptBlock.ToString(); Args = $ArgumentList; Session = $Session }) }
    }

    It 'opens one NTLM/Negotiate session with the explicit credential and never uses CredSSP' {
        $null = Start-VMFleetNodeTask -ComputerName $script:Node -Credential $script:Cred -Step Stop -RunId 'run1'
        Should -Invoke Open-VMFleetNodeSession -Times 1 -Exactly -ParameterFilter { $ComputerName -eq '192.0.2.11' -and $Credential.UserName -eq 'CONTOSO\labadmin' }
        Should -Invoke Close-VMFleetNodeSession -Times 1 -Exactly
        $script:Calls[0].Block | Should -Not -Match 'CredSSP'
        (Get-Content -LiteralPath (Join-Path $script:ScriptsPath 'VMFleet-Common.ps1') -Raw) | Should -Not -Match 'Enable-WSManCredSSP|-Authentication\s+Credssp'
    }

    It 'registers the task with the credential: logon type Password (-User/-Password), RunLevel Highest, one-shot' {
        $null = Start-VMFleetNodeTask -ComputerName $script:Node -Credential $script:Cred -Step Stop -RunId 'run1'
        $block = $script:Calls[0].Block
        $block | Should -Match 'Register-ScheduledTask'
        $block | Should -Match '-User \$UserName -Password \$UserSecret -RunLevel Highest'
        $block | Should -Match 'Start-ScheduledTask'
        $block | Should -Not -Match 'New-ScheduledTaskTrigger'
        $callArgs = $script:Calls[0].Args
        $callArgs[3] | Should -Be 'LoadTools-VMFleet-Stop-run1'
        $callArgs[4] | Should -Be '\LoadTools\'
        $callArgs[5] | Should -Be 'CONTOSO\labadmin'
        $callArgs[0] | Should -Be 'C:\ClusterStorage\Collect\loadtools\run1\Stop'
    }

    It 'writes only the generated script and the non-secret arguments to disk; the password and the secrets never reach a file' {
        $null = Start-VMFleetNodeTask -ComputerName $script:Node -Credential $script:Cred -Step Deploy -RunId 'run2' `
            -Arguments @{ VMsPerNode = 2; ConnectUser = 'CONTOSO\labadmin' } -Secrets @{ FleetAdminPassword = 'Fleet-Secret-77!' }
        $callArgs = $script:Calls[0].Args
        # WrapperText and ArgsJson are the only things written (Set-Content); the password, the secret JSON and the pipe name are not.
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Calls[0].Block, [ref]$null, [ref]$null)
        $writes = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in @('Set-Content', 'Out-File', 'Add-Content', 'New-Item') }, $true))
        foreach ($w in $writes | Where-Object { $_.GetCommandName() -eq 'Set-Content' }) { $w.Extent.Text | Should -Match 'WrapperText|ArgsJson' }
        $script:Calls[0].Block | Should -Not -Match 'Set-Content[^\r\n]*(UserSecret|SecretJson)'
        $callArgs[1] | Should -Not -Match 'Node-Pass-0001'
        $callArgs[1] | Should -Not -Match 'Fleet-Secret-77'
        $callArgs[2] | Should -Not -Match 'Fleet-Secret-77'
        $callArgs[2] | Should -Not -Match 'Node-Pass-0001'
        ($callArgs[2] | ConvertFrom-Json).VMsPerNode | Should -Be 2
        $callArgs[6] | Should -Be 'Node-Pass-0001!'
        ($callArgs[7] | ConvertFrom-Json).FleetAdminPassword | Should -Be 'Fleet-Secret-77!'
        $callArgs[8] | Should -Match '^loadtools-[0-9a-f]{32}$'
    }

    It 'uses no pipe and no secret JSON when there are no secrets' {
        $null = Start-VMFleetNodeTask -ComputerName $script:Node -Credential $script:Cred -Step Stop -RunId 'run3'
        $script:Calls[0].Args[7] | Should -Be ''
        $script:Calls[0].Args[8] | Should -Be ''
    }

    It 'the secrets go through an in-memory named pipe that only the task account may open' {
        $block = (Get-VMFleetStartBlock).ToString()
        $block | Should -Match 'NamedPipeServerStream'
        $block | Should -Match 'PipeAccessRule\(\$sid'
        $block | Should -Match 'WindowsIdentity\]::GetCurrent\(\)\.User'
    }

    It 'the node script is Windows PowerShell 5.1 syntax (powershell.exe runs it)' {
        $null = Start-VMFleetNodeTask -ComputerName $script:Node -Credential $script:Cred -Step Stop -RunId 'run4'
        $script:Calls[0].Args[10] | Should -Be 'powershell.exe'
        $script:Calls[0].Block | Should -Match 'New-ScheduledTaskAction -Execute \$NodePowerShell'
    }

    It 'rejects a step that has no node script' {
        { Start-VMFleetNodeTask -ComputerName $script:Node -Credential $script:Cred -Step Bogus -RunId 'r' } | Should -Throw
    }
}

Describe 'Open-VMFleetNodeSession' {
    It 'uses Negotiate (NTLM for an IP address) with the explicit credential, not CredSSP' {
        $cred = [pscredential]::new('CONTOSO\labadmin', (ConvertTo-SecureString 'Node-Pass-0001!' -AsPlainText -Force))
        Mock New-PSSession { [pscustomobject]@{ Id = 7 } }
        $null = Open-VMFleetNodeSession -ComputerName $script:Node -Credential $cred
        Should -Invoke New-PSSession -Times 1 -Exactly -ParameterFilter { $ComputerName -eq '192.0.2.11' -and $Authentication -eq 'Negotiate' -and $Credential.UserName -eq 'CONTOSO\labadmin' }
    }
}

Describe 'Wait-VMFleetNodeTask' {
    BeforeAll {
        $script:Cred = [pscredential]::new('CONTOSO\labadmin', (ConvertTo-SecureString 'Node-Pass-0001!' -AsPlainText -Force))
        $script:Handle = Get-VMFleetNodeTaskHandle -ComputerName $script:Node -RunId 'run9' -Step 'Test'
    }
    BeforeEach {
        $script:Cleanups = [System.Collections.Generic.List[object]]::new()
        $script:PollQueue = [System.Collections.Generic.Queue[object]]::new()
        Mock Open-VMFleetNodeSession { [pscustomobject]@{ Id = 1 } }
        Mock Close-VMFleetNodeSession { }
        Mock Start-Sleep { }
        Mock Invoke-VMFleetSessionCommand {
            if ($ScriptBlock.ToString() -match 'Unregister-ScheduledTask') { $script:Cleanups.Add($ArgumentList); return }
            $script:PollQueue.Dequeue()
        }
    }

    It 'returns the parsed result when the node wrote result.json, and unregisters the task' {
        $script:PollQueue.Enqueue(@{ State = 'Running'; LastTaskResult = 267009; ResultJson = $null; Tail = $null })
        $script:PollQueue.Enqueue(@{ State = 'Ready'; LastTaskResult = 0; ResultJson = '{"Status":"Succeeded","Output":{"VMsOk":4},"Error":null}'; Tail = $null })
        $r = Wait-VMFleetNodeTask -Handle $script:Handle -Credential $script:Cred -PollSeconds 1
        $r.Status | Should -Be 'Succeeded'
        $r.Output.VMsOk | Should -Be 4
        $script:Cleanups.Count | Should -Be 1
        $script:Cleanups[0][0] | Should -Be $script:Handle.TaskName
        $script:Cleanups[0][2] | Should -BeFalse
    }

    It 'throws the node error with the transcript path when the step failed, and still unregisters the task' {
        $script:PollQueue.Enqueue(@{ State = 'Ready'; LastTaskResult = 1; ResultJson = '{"Status":"Failed","Output":null,"Error":"Only 3 of 4 fleet VMs reached state Ok"}'; Tail = $null })
        { Wait-VMFleetNodeTask -Handle $script:Handle -Credential $script:Cred } | Should -Throw '*Only 3 of 4*transcript.log*'
        $script:Cleanups.Count | Should -Be 1
    }

    It 'throws with the transcript tail when the task ended without a result' {
        $script:PollQueue.Enqueue(@{ State = 'Ready'; LastTaskResult = 2147942402; ResultJson = $null; Tail = 'the script crashed here' })
        { Wait-VMFleetNodeTask -Handle $script:Handle -Credential $script:Cred -StartGraceSeconds 0 } | Should -Throw '*without writing a result*the script crashed here*'
        $script:Cleanups.Count | Should -Be 1
    }

    It 'stops and unregisters the task when the timeout passes' {
        $script:PollQueue.Enqueue(@{ State = 'Running'; LastTaskResult = 267009; ResultJson = $null; Tail = $null })
        { Wait-VMFleetNodeTask -Handle $script:Handle -Credential $script:Cred -TimeoutSeconds 0 } | Should -Throw '*did not finish within*'
        $script:Cleanups.Count | Should -Be 1
        $script:Cleanups[0][2] | Should -BeTrue
    }

    It 'gives up after five failed polls instead of waiting forever' {
        Mock Invoke-VMFleetSessionCommand { if ($ScriptBlock.ToString() -match 'Unregister-ScheduledTask') { return }; throw 'WinRM cannot connect' }
        { Wait-VMFleetNodeTask -Handle $script:Handle -Credential $script:Cred } | Should -Throw '*Lost contact*'
    }
}

Describe 'Generated node wrapper (run locally in Windows PowerShell 5.1)' -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
    BeforeAll {
        function script:Invoke-Wrapper {
            param([string]$Body, [hashtable]$StepArgs = @{}, [hashtable]$Secrets = @{})
            $runDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $runDir | Out-Null
            Set-Content -LiteralPath (Join-Path $runDir 'run.ps1') -Value (Get-VMFleetNodeWrapperScript -Body $Body) -Encoding utf8
            Set-Content -LiteralPath (Join-Path $runDir 'args.json') -Value ($StepArgs | ConvertTo-Json) -Encoding utf8
            $pipeName = ''
            $server = $null
            if ($Secrets.Count -gt 0) {
                $pipeName = 'loadtools-test-' + [guid]::NewGuid().ToString('N')
                $server = [System.IO.Pipes.NamedPipeServerStream]::new($pipeName, [System.IO.Pipes.PipeDirection]::Out, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
                $wait = $server.BeginWaitForConnection($null, $null)
            }
            $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $runDir 'run.ps1'), '-RunDir', $runDir)
            if ($pipeName) { $argList += @('-PipeName', $pipeName) }
            $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -PassThru -WindowStyle Hidden
            if ($server) {
                if (-not $wait.AsyncWaitHandle.WaitOne(60000)) { $proc.Kill(); throw 'the wrapper did not connect to the pipe' }
                $server.EndWaitForConnection($wait)
                $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Secrets | ConvertTo-Json -Compress))
                $server.Write($bytes, 0, $bytes.Length); $server.Flush(); $server.WaitForPipeDrain(); $server.Dispose()
            }
            if (-not $proc.WaitForExit(120000)) { $proc.Kill(); throw 'the wrapper did not finish' }
            [pscustomobject]@{
                ExitCode   = $proc.ExitCode
                Result     = Get-Content -LiteralPath (Join-Path $runDir 'result.json') -Raw | ConvertFrom-Json
                Transcript = Get-Content -LiteralPath (Join-Path $runDir 'transcript.log') -Raw
                RunDir     = $runDir
            }
        }
    }

    It 'parses as PowerShell and contains the step body' {
        $text = Get-VMFleetNodeWrapperScript -Body '$StepResult = @{ Marker = 42 }'
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
        $text | Should -Match 'Marker = 42'
        $text | Should -Match 'Start-Transcript'
        $text | Should -Match 'Set-StrictMode -Version 2\.0'
    }

    It 'runs the body, passes the arguments through Get-Arg and writes result.json and a transcript' {
        $r = Invoke-Wrapper -Body '$StepResult = @{ Echo = (Get-Arg ''Name'' ''none''); Missing = (Get-Arg ''Nope'' ''default'') }; Write-Host "hello from the body"' -StepArgs @{ Name = 'fleet' }
        $r.ExitCode | Should -Be 0
        $r.Result.Status | Should -Be 'Succeeded'
        $r.Result.Output.Echo | Should -Be 'fleet'
        $r.Result.Output.Missing | Should -Be 'default'
        $r.Transcript | Should -Match 'hello from the body'
    }

    It 'reports a failing body as Failed with exit code 1' {
        $r = Invoke-Wrapper -Body 'throw "the fleet is not ready"'
        $r.ExitCode | Should -Be 1
        $r.Result.Status | Should -Be 'Failed'
        $r.Result.Error | Should -Be 'the fleet is not ready'
    }

    It 'receives secrets over the pipe and scrubs them from the transcript and the result' {
        $secret = 'Zx9-Secret-Value-123'
        $body = '$StepResult = @{ Length = $Secrets[''FleetAdminPassword''].Length }; Write-Host "the password is $($Secrets[''FleetAdminPassword''])"; throw "failed with $($Secrets[''FleetAdminPassword''])"'
        $r = Invoke-Wrapper -Body $body -Secrets @{ FleetAdminPassword = $secret }
        $r.Result.Status | Should -Be 'Failed'
        $r.Transcript | Should -Not -Match 'Zx9-Secret-Value-123'
        $r.Transcript | Should -Match '\*{8}'
        (Get-Content -LiteralPath (Join-Path $r.RunDir 'result.json') -Raw) | Should -Not -Match 'Zx9-Secret-Value-123'
        foreach ($f in Get-ChildItem -LiteralPath $r.RunDir -File) { (Get-Content -LiteralPath $f.FullName -Raw) | Should -Not -Match 'Zx9-Secret-Value-123' -Because "$($f.Name) must not hold the secret" }
    }
}
