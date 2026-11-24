# =============================================================================
# VMFleet-StepScripts.Tests.ps1 - the VMFleet step scripts and the pipeline, end to end on fakes
# =============================================================================
# Each step script (Install, Deploy, Start, Stop, Collect, Remove) and the pipeline run
# from a sandbox copy of the repository whose VMFleet-Common.ps1 ends with fakes for the
# remoting layer (Test-ClusterConnectivity, Invoke-VMFleetNodeTask, Start-/Wait-VMFleetNodeTask).
# The fakes record every call, so the tests assert what each step asks the node to do.
# Nothing here touches a cluster, a node or Azure.
# =============================================================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The stubs of the VMFleet cmdlets are global functions; they record their calls in global variables the tests read.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Fake credentials for unit tests.')]
param()

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:Sandbox = Join-Path $TestDrive 'repo'
    New-Item -ItemType Directory -Path (Join-Path $script:Sandbox 'tools\vmfleet') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'common') -Destination $script:Sandbox -Recurse
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'tools\vmfleet\scripts') -Destination (Join-Path $script:Sandbox 'tools\vmfleet') -Recurse
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'tools\vmfleet\config') -Destination (Join-Path $script:Sandbox 'tools\vmfleet') -Recurse
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'tools\vmfleet\Invoke-VMFleetPipeline.ps1') -Destination (Join-Path $script:Sandbox 'tools\vmfleet')

    # Monitoring collectors are replaced by do-nothing scripts (the real ones open remoting sessions).
    $mon = Join-Path $script:Sandbox 'tools\vmfleet\monitoring'
    New-Item -ItemType Directory -Path $mon -Force | Out-Null
    foreach ($name in 'Collect-StorageMetrics', 'Collect-NetworkMetrics', 'Collect-ComputeMetrics', 'Export-MetricsDashboard', 'Push-MetricsToAzureMonitor') {
        Set-Content -LiteralPath (Join-Path $mon "$name.ps1") -Encoding utf8 -Value 'param($ClusterConfigPath, $ProjectRoot, $Credential, $OutputPath, $DurationSeconds, $MetricsPath, $RunId, $Format, $SolutionConfigPath)'
    }

    Add-Content -LiteralPath (Join-Path $script:Sandbox 'tools\vmfleet\scripts\VMFleet-Common.ps1') -Encoding utf8 -Value @'

# ---- test fakes (appended in the sandbox copy only) ----
function Test-ClusterConnectivity {
    param($NodeNames, $Credential, $TimeoutSeconds)
    $global:LtCalls.Add([pscustomobject]@{ Fn = 'Test-ClusterConnectivity'; Nodes = $NodeNames; User = $Credential.UserName })
    foreach ($n in $NodeNames) { [pscustomobject]@{ Node = $n; Reachable = $true; Detail = 'OK' } }
}
function Get-LtFakeOutput {
    param($Step)
    if ($global:LtResults.ContainsKey($Step)) { return $global:LtResults[$Step] }
    switch ($Step) {
        'Install' { [pscustomobject]@{ Components = @([pscustomobject]@{ Component = 'VMFleet'; Version = '2.1.0.0' }) } }
        'Deploy' { [pscustomobject]@{ VMsOk = 4; VMsExpected = 4; AlreadyDeployed = $false } }
        'Collect' {
            [pscustomobject]@{ VMs = @(
                    [pscustomobject]@{ VMName = 'vm-g-1'; ReadIOPS = 7000; WriteIOPS = 3000; ReadBytesPerSecond = 57344000; WriteBytesPerSecond = 24576000; ReadLatencyMs = 2; WriteLatencyMs = 4 },
                    [pscustomobject]@{ VMName = 'vm-g-2'; ReadIOPS = 3500; WriteIOPS = 1500; ReadBytesPerSecond = 28672000; WriteBytesPerSecond = 12288000; ReadLatencyMs = 3; WriteLatencyMs = 5 }
                ) }
        }
        'Remove' { [pscustomobject]@{ RemainingVMs = @(); RemainingDirectories = @(); RemovedResultFiles = 0 } }
        default { [pscustomobject]@{} }
    }
}
function Invoke-VMFleetNodeTask {
    param($ComputerName, $Credential, $Step, $RunId, $Arguments, $Secrets, $CollectPath, $TimeoutSeconds, $PollSeconds)
    $global:LtCalls.Add([pscustomobject]@{ Fn = 'Invoke-VMFleetNodeTask'; Computer = $ComputerName; User = $Credential.UserName; Step = $Step; RunId = $RunId; Arguments = $Arguments; Secrets = $Secrets; CollectPath = $CollectPath; Timeout = $TimeoutSeconds })
    [pscustomobject]@{ Status = 'Succeeded'; Output = (Get-LtFakeOutput $Step); TranscriptPath = "$CollectPath\loadtools\$RunId\$Step\transcript.log" }
}
function Start-VMFleetNodeTask {
    param($ComputerName, $Credential, $Step, $RunId, $Arguments, $Secrets, $CollectPath)
    $global:LtCalls.Add([pscustomobject]@{ Fn = 'Start-VMFleetNodeTask'; Computer = $ComputerName; Step = $Step; RunId = $RunId; Arguments = $Arguments; CollectPath = $CollectPath })
    Get-VMFleetNodeTaskHandle -ComputerName $ComputerName -RunId $RunId -Step $Step -CollectPath $CollectPath
}
function Wait-VMFleetNodeTask {
    param($Handle, $Credential, $TimeoutSeconds, $PollSeconds)
    $global:LtCalls.Add([pscustomobject]@{ Fn = 'Wait-VMFleetNodeTask'; Step = $Handle.Step; Task = $Handle.TaskName; Timeout = $TimeoutSeconds })
    [pscustomobject]@{ Status = 'Succeeded'; Output = (Get-LtFakeOutput $Handle.Step) }
}
'@

    $script:Cluster = Join-Path $TestDrive 'cluster.yml'
    Set-Content -LiteralPath $script:Cluster -Encoding utf8 -Value @'
cluster:
  name: "azl-cluster-01"
nodes:
  - name: "192.0.2.11"
  - name: "192.0.2.12"
storage:
  collect_path: "C:\\ClusterStorage\\Collect"
  base_vhd_path: "C:\\ClusterStorage\\Collect\\base\\vmfleet-base.vhdx"
'@
    $script:Day2Profile = Join-Path $script:RepoRoot 'tools\vmfleet\config\profiles\day2-smoke.yml'
    $script:GeneralProfile = Join-Path $script:RepoRoot 'tools\vmfleet\config\profiles\general.yml'
    $script:Cred = [pscredential]::new('CONTOSO\labadmin', (ConvertTo-SecureString 'Node-Pass-0001!' -AsPlainText -Force))
    $script:FleetCred = [pscredential]::new('Administrator', (ConvertTo-SecureString 'Fleet-Pass-0002!' -AsPlainText -Force))
    $script:Scripts = Join-Path $script:Sandbox 'tools\vmfleet\scripts'
    $script:Common = @{ ProjectRoot = $script:Sandbox; ClusterConfigPath = $script:Cluster; Credential = $script:Cred }
}

AfterAll {
    Remove-Variable -Name LtCalls, LtResults -Scope Global -ErrorAction SilentlyContinue
}

Describe 'VMFleet step scripts' {
    BeforeEach {
        $global:LtCalls = [System.Collections.Generic.List[object]]::new()
        $global:LtResults = @{}
    }

    Context 'Install-VMFleet.ps1' {
        It 'runs the Install step on the FIRST node by IP with the cluster credential and the version from vmfleet.json' {
            & (Join-Path $script:Scripts 'Install-VMFleet.ps1') @script:Common -RunId 'inst1'
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Computer | Should -Be '192.0.2.11'
            $call.Step | Should -Be 'Install'
            $call.User | Should -Be 'CONTOSO\labadmin'
            $call.RunId | Should -Be 'inst1'
            $call.CollectPath | Should -Be 'C:\ClusterStorage\Collect'
            $call.Arguments.VMFleetVersion | Should -Be '2.1.0.0'
            $call.Arguments.KeepBlockCache | Should -BeFalse
            ($global:LtCalls | Where-Object { $_.Fn -eq 'Test-ClusterConnectivity' }).Nodes | Should -Be @('192.0.2.11', '192.0.2.12')
        }

        It 'a version parameter overrides vmfleet.json, and the switches are forwarded' {
            & (Join-Path $script:Scripts 'Install-VMFleet.ps1') @script:Common -VMFleetVersion '2.0.0.0' -KeepBlockCache -NoTools
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Arguments.VMFleetVersion | Should -Be '2.0.0.0'
            $call.Arguments.KeepBlockCache | Should -BeTrue
            $call.Arguments.NoTools | Should -BeTrue
        }

        It 'does nothing under -WhatIf' {
            & (Join-Path $script:Scripts 'Install-VMFleet.ps1') @script:Common -WhatIf
            @($global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }).Count | Should -Be 0
        }

        It 'stops with a clear message when the cluster YAML is missing' {
            { & (Join-Path $script:Scripts 'Install-VMFleet.ps1') -ProjectRoot $script:Sandbox -Credential $script:Cred -ClusterConfigPath (Join-Path $TestDrive 'nope.yml') } | Should -Throw '*example-cluster.yml*'
        }
    }

    Context 'Deploy-VMFleet.ps1' {
        It 'reads the sizing from the registry names in vmfleet.json (not vmfleet_*) and passes VMs PER NODE' {
            & (Join-Path $script:Scripts 'Deploy-VMFleet.ps1') @script:Common -RunId 'dep1' -FleetAdminCredential $script:FleetCred
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Step | Should -Be 'Deploy'
            $call.Arguments.VMsPerNode | Should -Be 10
            $call.Arguments.ExpectedVMs | Should -Be 20
            $call.Arguments.ProcessorCount | Should -Be 2
            $call.Arguments.MemoryStartupBytes | Should -Be 2GB
            $call.Arguments.BaseVhdPath | Should -Be 'C:\ClusterStorage\Collect\base\vmfleet-base.vhdx'
            $call.Arguments.Admin | Should -Be 'Administrator'
        }

        It 'the base VHD parameter and the VM count override the config' {
            & (Join-Path $script:Scripts 'Deploy-VMFleet.ps1') @script:Common -FleetAdminCredential $script:FleetCred -VMCount 3 -BaseVHDPath 'C:\ClusterStorage\Collect\other.vhdx' -VMMemoryGB 4 -VMProcessorCount 1
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Arguments.VMsPerNode | Should -Be 3
            $call.Arguments.ExpectedVMs | Should -Be 6
            $call.Arguments.BaseVhdPath | Should -Be 'C:\ClusterStorage\Collect\other.vhdx'
            $call.Arguments.MemoryStartupBytes | Should -Be 4GB
            $call.Arguments.ProcessorCount | Should -Be 1
        }

        It 'sends the passwords only as secrets; the connect account defaults to the cluster credential' {
            & (Join-Path $script:Scripts 'Deploy-VMFleet.ps1') @script:Common -FleetAdminCredential $script:FleetCred
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Secrets.FleetAdminPassword | Should -Be 'Fleet-Pass-0002!'
            $call.Secrets.ConnectPassword | Should -Be 'Node-Pass-0001!'
            $call.Arguments.ConnectUser | Should -Be 'CONTOSO\labadmin'
            ($call.Arguments | ConvertTo-Json) | Should -Not -Match 'Pass-000'
        }

        It 'a separate connect credential is used when given, and a domain admin name becomes the local account name' {
            $connect = [pscredential]::new('CONTOSO\svc-fleet', (ConvertTo-SecureString 'Connect-Pass-3!' -AsPlainText -Force))
            $admin = [pscredential]::new('CONTOSO\localadm', (ConvertTo-SecureString 'Fleet-Pass-0002!' -AsPlainText -Force))
            & (Join-Path $script:Scripts 'Deploy-VMFleet.ps1') @script:Common -FleetAdminCredential $admin -FleetConnectCredential $connect
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Arguments.ConnectUser | Should -Be 'CONTOSO\svc-fleet'
            $call.Secrets.ConnectPassword | Should -Be 'Connect-Pass-3!'
            $call.Arguments.Admin | Should -Be 'localadm'
        }

        It 'refuses to deploy without a fleet admin credential (no default password)' {
            { & (Join-Path $script:Scripts 'Deploy-VMFleet.ps1') @script:Common } | Should -Throw '*FleetAdminCredential is required*'
            @($global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }).Count | Should -Be 0
        }

        It 'refuses to deploy without a base VHD' {
            $noVhd = Join-Path $TestDrive 'novhd.yml'
            Set-Content -LiteralPath $noVhd -Value "nodes:`n  - '192.0.2.11'`n"
            { & (Join-Path $script:Scripts 'Deploy-VMFleet.ps1') -ProjectRoot $script:Sandbox -ClusterConfigPath $noVhd -Credential $script:Cred -FleetAdminCredential $script:FleetCred } | Should -Throw '*No base VHD*'
        }
    }

    Context 'Start-VMFleetTest.ps1' {
        It 'Day2Smoke: the profile.parameters values (600 s measured, 120 s warm-up) reach the node, tagged with the run id' {
            $meta = & (Join-Path $script:Scripts 'Start-VMFleetTest.ps1') @script:Common -ProfilePath $script:Day2Profile -RunId 'day2smoke-20261124-101500'
            $start = $global:LtCalls | Where-Object { $_.Fn -eq 'Start-VMFleetNodeTask' }
            $start.Step | Should -Be 'Test'
            $start.Computer | Should -Be '192.0.2.11'
            $start.Arguments.DurationSeconds | Should -Be 600
            $start.Arguments.WarmupSeconds | Should -Be 120
            $start.Arguments.CooldownSeconds | Should -Be 30
            $start.Arguments.BlockSizeKB | Should -Be 8
            $start.Arguments.WriteRatio | Should -Be 30
            $start.Arguments.OutstandingIO | Should -Be 8
            $start.Arguments.Threads | Should -Be 2
            $start.Arguments.Pattern | Should -Be 'r'
            $start.Arguments.Tag | Should -Be 'day2smoke20261124101500'
            $start.Arguments.CollectPath | Should -Be 'C:\ClusterStorage\Collect'
            $meta.ProfileName | Should -Be 'Day2Smoke'
            $meta.Duration | Should -Be 600
            $meta.TotalSeconds | Should -Be 750
            # default: wait for the sweep
            @($global:LtCalls | Where-Object { $_.Fn -eq 'Wait-VMFleetNodeTask' }).Count | Should -Be 1
            ($global:LtCalls | Where-Object { $_.Fn -eq 'Wait-VMFleetNodeTask' }).Timeout | Should -BeGreaterThan 750
        }

        It 'General profile: 300 s measured, 60 s warm-up' {
            $null = & (Join-Path $script:Scripts 'Start-VMFleetTest.ps1') @script:Common -ProfilePath $script:GeneralProfile -RunId 'gen1'
            $start = $global:LtCalls | Where-Object { $_.Fn -eq 'Start-VMFleetNodeTask' }
            $start.Arguments.DurationSeconds | Should -Be 300
            $start.Arguments.WarmupSeconds | Should -Be 60
        }

        It '-NoWait returns the task handle without waiting; explicit parameters beat the profile' {
            $meta = & (Join-Path $script:Scripts 'Start-VMFleetTest.ps1') @script:Common -ProfilePath $script:Day2Profile -RunId 'nw1' -NoWait -DurationSeconds 60 -WriteRatio 0 -BlockSize 64k
            @($global:LtCalls | Where-Object { $_.Fn -eq 'Wait-VMFleetNodeTask' }).Count | Should -Be 0
            $meta.TaskHandle.TaskName | Should -Be 'LoadTools-VMFleet-Test-nw1'
            $start = $global:LtCalls | Where-Object { $_.Fn -eq 'Start-VMFleetNodeTask' }
            $start.Arguments.DurationSeconds | Should -Be 60
            $start.Arguments.WriteRatio | Should -Be 0
            $start.Arguments.BlockSizeKB | Should -Be 64
        }

        It 'under -WhatIf nothing is started' {
            $null = & (Join-Path $script:Scripts 'Start-VMFleetTest.ps1') @script:Common -ProfilePath $script:Day2Profile -WhatIf
            @($global:LtCalls | Where-Object { $_.Fn -in 'Start-VMFleetNodeTask', 'Invoke-VMFleetNodeTask' }).Count | Should -Be 0
        }

        It 'a missing profile file is an error, not a silent fallback' {
            { & (Join-Path $script:Scripts 'Start-VMFleetTest.ps1') @script:Common -ProfilePath (Join-Path $TestDrive 'nope.yml') } | Should -Throw '*Profile not found*'
        }
    }

    Context 'Stop-VMFleetTest.ps1 and Remove-VMFleet.ps1' {
        It 'Stop runs the Stop step on the first node' {
            & (Join-Path $script:Scripts 'Stop-VMFleetTest.ps1') @script:Common -RunId 'stop1'
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Step | Should -Be 'Stop'
            $call.Computer | Should -Be '192.0.2.11'
        }

        It 'Remove runs the Remove step (Remove-Fleet) and succeeds when nothing is left' {
            & (Join-Path $script:Scripts 'Remove-VMFleet.ps1') @script:Common -RunId 'rm1' -Confirm:$false
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Step | Should -Be 'Remove'
            $call.Arguments.RemoveCollectData | Should -BeFalse
        }

        It 'Remove -RemoveCollectData (and its old name -RemoveVHDs) asks for the result files to go too' {
            & (Join-Path $script:Scripts 'Remove-VMFleet.ps1') @script:Common -RemoveVHDs -Confirm:$false
            ($global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }).Arguments.RemoveCollectData | Should -BeTrue
        }

        It 'Remove fails when a VM or a folder is left, naming them' {
            $global:LtResults['Remove'] = [pscustomobject]@{ RemainingVMs = @('vm-g-node1-001'); RemainingDirectories = @('C:\ClusterStorage\azl-node-01\vm-g-node1-001'); RemovedResultFiles = 0 }
            { & (Join-Path $script:Scripts 'Remove-VMFleet.ps1') @script:Common -Confirm:$false } | Should -Throw '*Cleanup is incomplete*vm-g-node1-001*'
        }

        It 'Remove does nothing under -WhatIf' {
            & (Join-Path $script:Scripts 'Remove-VMFleet.ps1') @script:Common -WhatIf
            @($global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }).Count | Should -Be 0
        }
    }

    Context 'Collect-VMFleetResults.ps1' {
        It 'turns the per-VM DiskSpd reductions into the aggregate and per-VM JSON the gate and the report read' {
            $out = Join-Path $TestDrive 'collect-out'
            $meta = @{ ProfileName = 'Day2Smoke'; Duration = 600; TaskHandle = [pscustomobject]@{ TaskName = 'x' } }
            $r = & (Join-Path $script:Scripts 'Collect-VMFleetResults.ps1') @script:Common -RunId 'col1' -OutputPath $out -TestMetadata $meta
            $call = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }
            $call.Step | Should -Be 'Collect'
            $call.Arguments.Tag | Should -Be 'col1'
            $agg = Get-Content -LiteralPath (Join-Path $out 'col1-aggregate.json') -Raw | ConvertFrom-Json
            $agg.vm_count | Should -Be 2
            $agg.total_read_iops | Should -Be 10500
            $agg.total_write_iops | Should -Be 4500
            $agg.total_iops | Should -Be 15000
            $agg.profile_name | Should -Be 'Day2Smoke'
            # read latency weighted by reads/s: (2*7000 + 3*3500) / 10500 = 2.333
            $agg.avg_read_latency_ms | Should -Be 2.333
            $agg.total_read_throughput_mbps | Should -Be 82.03
            $agg.total_throughput_mbps | Should -BeGreaterThan 100
            $agg.test_parameters.Duration | Should -Be 600
            ($agg.test_parameters.PSObject.Properties.Name) | Should -Not -Contain 'TaskHandle'
            (Get-Content -LiteralPath (Join-Path $out 'col1-per-vm.json') -Raw | ConvertFrom-Json).Count | Should -Be 2
            $r.Aggregate.total_iops | Should -Be 15000
        }

        It 'without a run id it asks the node for the tag of the last test (empty tag)' {
            $null = & (Join-Path $script:Scripts 'Collect-VMFleetResults.ps1') @script:Common -OutputPath (Join-Path $TestDrive 'collect-out2')
            ($global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' }).Arguments.Tag | Should -Be ''
        }

        It 'fails when the node returns no VM results' {
            $global:LtResults['Collect'] = [pscustomobject]@{ VMs = @() }
            { & (Join-Path $script:Scripts 'Collect-VMFleetResults.ps1') @script:Common -RunId 'col3' -OutputPath (Join-Path $TestDrive 'collect-out3') } | Should -Throw '*no per-VM results*'
        }
    }

    Context 'Invoke-VMFleetPipeline.ps1 (all phases on fakes)' {
        BeforeAll {
            $script:Pipeline = Join-Path $script:Sandbox 'tools\vmfleet\Invoke-VMFleetPipeline.ps1'
        }

        It 'runs PreCheck, Install, Deploy, StartTest, Monitor, StopTest, Collect, Report and Cleanup with the config forwarded' {
            & $script:Pipeline -ProjectRoot $script:Sandbox -ClusterConfigPath $script:Cluster -ProfilePath $script:Day2Profile -Credential $script:Cred -FleetAdminCredential $script:FleetCred -RunId 'pipe1' -VMCount 2 6>$null

            $steps = @($global:LtCalls | Where-Object { $_.Fn -in 'Invoke-VMFleetNodeTask', 'Start-VMFleetNodeTask', 'Wait-VMFleetNodeTask' } | ForEach-Object { "$($_.Fn -replace '-VMFleetNodeTask', '')/$($_.Step)" })
            $steps | Should -Be @('Invoke/Install', 'Invoke/Deploy', 'Start/Test', 'Wait/Test', 'Invoke/Stop', 'Invoke/Collect', 'Invoke/Remove')

            $install = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' -and $_.Step -eq 'Install' }
            $install.Arguments.VMFleetVersion | Should -Be '2.1.0.0'
            $deploy = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' -and $_.Step -eq 'Deploy' }
            $deploy.Arguments.VMsPerNode | Should -Be 2
            $deploy.Arguments.BaseVhdPath | Should -Be 'C:\ClusterStorage\Collect\base\vmfleet-base.vhdx'
            $deploy.Arguments.ExpectedVMs | Should -Be 4
            $deploy.Secrets.FleetAdminPassword | Should -Be 'Fleet-Pass-0002!'

            $start = $global:LtCalls | Where-Object { $_.Fn -eq 'Start-VMFleetNodeTask' }
            $start.Arguments.DurationSeconds | Should -Be 600
            $start.Arguments.WarmupSeconds | Should -Be 120
            $start.Arguments.Tag | Should -Be 'pipe1'

            # The Monitor phase waits for the sweep itself (duration + warm-up + cool-down + slack), not a fixed 30 s.
            $wait = $global:LtCalls | Where-Object { $_.Fn -eq 'Wait-VMFleetNodeTask' }
            $wait.Task | Should -Be 'LoadTools-VMFleet-Test-pipe1'
            $wait.Timeout | Should -Be (750 + 1800)

            $remove = $global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' -and $_.Step -eq 'Remove' }
            $remove | Should -Not -BeNullOrEmpty

            # Default report format: HTML (+ CSV), no extra tool needed.
            $reports = Join-Path $script:Sandbox 'reports\pipe1'
            (Get-ChildItem -LiteralPath $reports -Filter '*.html' -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
            Test-Path -LiteralPath (Join-Path $reports 'pipe1-aggregate.json') | Should -BeTrue
        }

        It 'skips a report format whose tool is missing instead of failing the run' -Skip:((Get-Command asciidoctor-pdf -ErrorAction SilentlyContinue) -or (Get-Module -ListAvailable -Name ImportExcel)) {
            & $script:Pipeline -ProjectRoot $script:Sandbox -ClusterConfigPath $script:Cluster -ProfilePath $script:Day2Profile -Credential $script:Cred -FleetAdminCredential $script:FleetCred -RunId 'pipe2' -ReportFormats HTML, PDF, XLSX -SkipCleanup 6>$null
            (Get-ChildItem -LiteralPath (Join-Path $script:Sandbox 'reports\pipe2') -Filter '*.html').Count | Should -BeGreaterThan 0
            @($global:LtCalls | Where-Object { $_.Fn -eq 'Invoke-VMFleetNodeTask' -and $_.Step -eq 'Remove' }).Count | Should -Be 0
        }

        It 'stops at Deploy without a fleet admin credential and says so' {
            { & $script:Pipeline -ProjectRoot $script:Sandbox -ClusterConfigPath $script:Cluster -ProfilePath $script:Day2Profile -Credential $script:Cred -RunId 'pipe3' 6>$null } | Should -Throw '*FleetAdminCredential is required*'
        }

        It 'defaults to HTML reports, has -VMCount, -BaseVHDPath and -VMFleetVersion, and no longer reads vmfleet_* keys' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot 'tools\vmfleet\Invoke-VMFleetPipeline.ps1'), [ref]$null, [ref]$null)
            $names = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
            $names | Should -Contain 'VMCount'
            $names | Should -Contain 'BaseVHDPath'
            $names | Should -Contain 'VMFleetVersion'
            $names | Should -Contain 'FleetConnectCredential'
            $report = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ReportFormats' }
            $report.DefaultValue.Extent.Text | Should -Be "@('HTML')"
            (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tools\vmfleet\Invoke-VMFleetPipeline.ps1') -Raw) | Should -Not -Match 'vmfleet_test_duration|vmfleet_warmup_seconds|Wait-WithProgress'
        }
    }
}
