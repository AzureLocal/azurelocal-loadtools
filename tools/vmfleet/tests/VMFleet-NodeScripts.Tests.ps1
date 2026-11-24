# =============================================================================
# VMFleet-NodeScripts.Tests.ps1 - the node-side payloads against the VMFleet 2.1 signatures
# =============================================================================
# The payloads in tools\vmfleet\scripts\node run on a cluster node and call the
# VMFleet 2.1.0.0 cmdlets. Here they run against stubs that have the REAL parameter
# lists of VMFleet 2.1.0.0 (read from VMFleet.psm1 of the PSGallery package), so a
# wrong cmdlet name or flag fails like it would on the node. Nothing here touches a
# cluster, a node or Azure.
# =============================================================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The stubs of the VMFleet cmdlets are global functions; they record their calls in global variables the tests read.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'The stubs are generated from the VMFleet 2.1 signature table.')]
param()

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:VMFleetRoot = Join-Path $script:ProjectRoot 'tools\vmfleet'
    $script:NodeDir = Join-Path $script:VMFleetRoot 'scripts\node'
    . (Join-Path $script:VMFleetRoot 'scripts\VMFleet-Common.ps1')

    # Parameters of the cmdlets this tool calls, as declared in VMFleet 2.1.0.0 (Mandatory = required in every parameter set).
    $script:Signatures = [ordered]@{
        'Install-Fleet'           = @{ Cluster = ''; KeepBlockCache = ''; NoTools = ''; Force = '' }
        'New-Fleet'               = @{ Cluster = ''; Node = ''; BaseVHD = 'M'; VMs = ''; Groups = ''; AdminPass = 'M'; Admin = ''; ConnectPass = 'M'; ConnectUser = 'M'; StopAfter = ''; Specialize = ''; KeepVHD = '' }
        'Set-Fleet'               = @{ Cluster = ''; ProcessorCount = ''; MemoryStartupBytes = ''; MemoryMaximumBytes = ''; MemoryMinimumBytes = ''; ComputeTemplate = ''; DataDiskSize = ''; Running = '' }
        'Start-Fleet'             = @{ Cluster = ''; Group = ''; Number = ''; Percent = '' }
        'Stop-Fleet'              = @{ Cluster = ''; Group = '' }
        'Remove-Fleet'            = @{ Cluster = ''; VMs = '' }
        'Get-FleetVM'             = @{ Cluster = ''; Group = ''; ControlResponse = ''; Timeout = '' }
        'Get-FleetPath'           = @{ Cluster = ''; PathType = ''; Local = '' }
        'Get-FleetVersion'        = @{ Cluster = '' }
        'Start-FleetSweep'        = @{ Cluster = ''; AddSpec = ''; RunTemplate = ''; RunFile = ''; LabelTemplate = ''; b = 'M'; t = 'M'; o = 'M'; w = 'M'; p = ''; iops = ''; d = ''; Warm = ''; Cool = ''; pc = ''; SampleInterval = '' }
        'Get-FleetResultLog'      = @{ ResultLog = ''; KeyColumn = '' }
        'Get-FleetVolumeEstimate' = @{ Cluster = ''; CollectVolumeSize = ''; MAPMirrorPercentage = '' }
        'Measure-FleetCoreWorkload' = @{ Cluster = ''; ResultDirectory = ''; LogFile = ''; KeyColumn = ''; Warmup = ''; SkipSddcDiagInfo = ''; UseStorageQos = '' }
    }
    $script:CommonParameters = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'ProgressAction')

    # Stubs with the real parameter lists; every call is recorded, behaviour comes from $global:VMFleetStubHooks.
    $global:VMFleetStubCalls = [System.Collections.Generic.List[object]]::new()
    $global:VMFleetStubHooks = @{}
    foreach ($cmd in $script:Signatures.Keys) {
        $declared = foreach ($name in $script:Signatures[$cmd].Keys) {
            $mandatory = if ($script:Signatures[$cmd][$name] -eq 'M') { 'Mandatory = $true' } else { '' }
            $validate = if ($cmd -eq 'Start-FleetSweep' -and $name -eq 'p') { '[ValidateSet(''r'',''s'',''si'')]' } else { '' }
            "[Parameter($mandatory)]$validate`$$name"
        }
        $text = "function global:$cmd { [CmdletBinding()] param($($declared -join ', ')) " +
        "`$global:VMFleetStubCalls.Add([pscustomobject]@{ Name = '$cmd'; Bound = @{} + `$PSBoundParameters }); " +
        "if (`$global:VMFleetStubHooks.ContainsKey('$cmd')) { & `$global:VMFleetStubHooks['$cmd'] } }"
        Invoke-Expression $text
    }
    function global:Install-Module { [CmdletBinding()] param($Name, $RequiredVersion, [switch]$Force, [switch]$AllowClobber, $Scope) $global:VMFleetStubCalls.Add([pscustomobject]@{ Name = 'Install-Module'; Bound = @{} + $PSBoundParameters }) }
    function global:Get-ClusterSharedVolume { [CmdletBinding()] param() if ($global:VMFleetStubHooks.ContainsKey('Get-ClusterSharedVolume')) { & $global:VMFleetStubHooks['Get-ClusterSharedVolume'] } }

    function script:Invoke-NodeBody {
        param([string]$Name, [hashtable]$StepArgs = @{}, [hashtable]$Secrets = @{})
        $global:VMFleetStubCalls.Clear()
        $body = Get-VMFleetNodeScriptText -Name $Name
        $runner = [scriptblock]::Create(@'
param($StepArgsObject, $Secrets)
function Get-Arg { param([string]$Name, $Default = $null) $p = $StepArgsObject.PSObject.Properties[$Name]; if ($p -and $null -ne $p.Value) { return $p.Value }; return $Default }
$StepResult = $null
. {
'@ + "`n" + $body + "`n" + @'
} | Out-Null
return $StepResult
'@)
        & $runner ([pscustomobject]$StepArgs) $Secrets
    }
}

AfterAll {
    foreach ($cmd in @($script:Signatures.Keys) + 'Install-Module', 'Get-ClusterSharedVolume') { Remove-Item -Path "function:global:$cmd" -ErrorAction SilentlyContinue }
    Remove-Variable -Name VMFleetStubCalls, VMFleetStubHooks -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Node payloads: shape' {
    It '<_>.node.ps1 exists and parses' -ForEach @('Install', 'Deploy', 'Test', 'Stop', 'Collect', 'Remove') {
        $path = Join-Path $script:NodeDir "$_.node.ps1"
        Test-Path -LiteralPath $path | Should -BeTrue
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It 'every payload and the wrapper parse in Windows PowerShell 5.1 (the node runs powershell.exe)' -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $paths = @(Get-ChildItem -LiteralPath $script:NodeDir -Filter '*.node.ps1' | ForEach-Object { $_.FullName })
        $wrapper = Join-Path $TestDrive 'wrapper.ps1'
        Set-Content -LiteralPath $wrapper -Value (Get-VMFleetNodeWrapperScript -Body (Get-VMFleetNodeScriptText -Name 'Deploy')) -Encoding utf8
        $paths += $wrapper
        $list = Join-Path $TestDrive 'paths.txt'
        Set-Content -LiteralPath $list -Value $paths -Encoding utf8
        $out = & powershell.exe -NoProfile -NonInteractive -Command "`$n = 0; foreach (`$p in Get-Content -LiteralPath '$list') { `$e = `$null; [System.Management.Automation.Language.Parser]::ParseFile(`$p, [ref]`$null, [ref]`$e) | Out-Null; `$n += @(`$e).Count }; Write-Output ('PARSEERRORS=' + `$n)"
        ($out | Select-Object -Last 1) | Should -Be 'PARSEERRORS=0'
    }

    It 'no script under tools\vmfleet calls a cmdlet VMFleet 2.1.0.0 does not have (Get-Fleet, Get-FleetDataXml)' {
        $files = Get-ChildItem -LiteralPath $script:VMFleetRoot -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\tests\\' }
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $names = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
            $names | Should -Not -Contain 'Get-Fleet' -Because $f.Name
            $names | Should -Not -Contain 'Get-FleetDataXml' -Because $f.Name
        }
    }

    It 'every named parameter of a VMFleet cmdlet call is a parameter VMFleet 2.1.0.0 declares' {
        $files = Get-ChildItem -LiteralPath $script:VMFleetRoot -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\tests\\' }
        $checked = 0
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -and $script:Signatures.Contains($n.GetCommandName()) }, $true)
            foreach ($call in $calls) {
                $cmd = $call.GetCommandName()
                foreach ($element in $call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] }) {
                    $checked++
                    ($script:Signatures[$cmd].Keys + $script:CommonParameters) | Should -Contain $element.ParameterName -Because "$($f.Name) calls $cmd -$($element.ParameterName)"
                }
            }
        }
        $checked | Should -BeGreaterThan 5
    }

    It 'the pipeline phases and step scripts no longer read the vmfleet_* keys vmfleet.json does not have' {
        $files = Get-ChildItem -LiteralPath $script:VMFleetRoot -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\tests\\' }
        foreach ($f in $files) { (Get-Content -LiteralPath $f.FullName -Raw) | Should -Not -Match '\bvmfleet_(vm_count|test_duration|warmup_seconds|base_vhd_path|vm_memory_gb|vm_processors|block_size)' -Because $f.Name }
    }
}

Describe 'Install payload' {
    BeforeEach { $global:VMFleetStubHooks = @{ 'Get-FleetVersion' = { [pscustomobject]@{ Component = 'VMFleet'; Version = [version]'2.1.0.0' }; [pscustomobject]@{ Component = 'diskspd.exe'; Version = [version]'2.1.0.0' } } }; Mock Import-Module { } }

    It 'installs the pinned module version, then runs Install-Fleet with only the flags asked for' {
        $r = Invoke-NodeBody -Name Install -StepArgs @{ VMFleetVersion = '2.1.0.0'; KeepBlockCache = $true; NoTools = $false; Force = $true }
        ($global:VMFleetStubCalls | Where-Object Name -eq 'Install-Module').Bound.RequiredVersion | Should -Be '2.1.0.0'
        $fleet = $global:VMFleetStubCalls | Where-Object Name -eq 'Install-Fleet'
        $fleet.Bound.Keys | Should -Contain 'KeepBlockCache'
        $fleet.Bound.Keys | Should -Contain 'Force'
        $fleet.Bound.Keys | Should -Not -Contain 'NoTools'
        $r.Components.Count | Should -Be 2
    }

    It 'refuses an empty version instead of calling Install-Module with $null' {
        { Invoke-NodeBody -Name Install -StepArgs @{} } | Should -Throw '*VMFleetVersion is empty*'
        @($global:VMFleetStubCalls | Where-Object Name -eq 'Install-Module').Count | Should -Be 0
    }
}

Describe 'Deploy payload' {
    BeforeAll {
        $script:Vhd = Join-Path $TestDrive 'base.vhdx'
        Set-Content -LiteralPath $script:Vhd -Value 'x'
        $script:DeployArgs = @{ BaseVhdPath = $script:Vhd; VMsPerNode = 4; ExpectedVMs = 8; Admin = 'Administrator'; ConnectUser = 'CONTOSO\labadmin'; ProcessorCount = 2; MemoryStartupBytes = 2GB; WaitMinutes = 1 }
        $script:DeploySecrets = @{ FleetAdminPassword = 'vm-admin-pw'; ConnectPassword = 'connect-pw' }
    }
    BeforeEach {
        Mock Import-Module { }
        Mock Start-Sleep { }
        $global:VMFleetFleetCreated = $false
        $global:VMFleetStubHooks = @{
            'New-Fleet'   = { $global:VMFleetFleetCreated = $true }
            'Get-FleetVM' = { if ($global:VMFleetFleetCreated) { 1..8 | ForEach-Object { [pscustomobject]@{ Name = "vm-g-$_"; State = 'Ok' } } } }
        }
    }
    AfterAll { Remove-Variable -Name VMFleetFleetCreated -Scope Global -ErrorAction SilentlyContinue }

    It 'calls New-Fleet, Set-Fleet and Start-Fleet in that order with the VMFleet 2.1 flags' {
        $r = Invoke-NodeBody -Name Deploy -StepArgs $script:DeployArgs -Secrets $script:DeploySecrets
        $names = @($global:VMFleetStubCalls | Where-Object { $_.Name -in 'New-Fleet', 'Set-Fleet', 'Start-Fleet' } | ForEach-Object Name)
        $names | Should -Be @('New-Fleet', 'Set-Fleet', 'Start-Fleet')
        $new = ($global:VMFleetStubCalls | Where-Object Name -eq 'New-Fleet').Bound
        $new.BaseVHD | Should -Be $script:Vhd
        $new.VMs | Should -Be 4
        $new.Admin | Should -Be 'Administrator'
        $new.AdminPass | Should -Be 'vm-admin-pw'
        $new.ConnectUser | Should -Be 'CONTOSO\labadmin'
        $new.ConnectPass | Should -Be 'connect-pw'
        $set = ($global:VMFleetStubCalls | Where-Object Name -eq 'Set-Fleet').Bound
        $set.ProcessorCount | Should -Be 2
        $set.MemoryStartupBytes | Should -Be 2GB
        $r.VMsOk | Should -Be 8
        $r.AlreadyDeployed | Should -BeFalse
    }

    It 'does nothing when the fleet already has every VM and all are Ok' {
        $global:VMFleetFleetCreated = $true
        $r = Invoke-NodeBody -Name Deploy -StepArgs $script:DeployArgs -Secrets $script:DeploySecrets
        $r.AlreadyDeployed | Should -BeTrue
        @($global:VMFleetStubCalls | Where-Object Name -eq 'New-Fleet').Count | Should -Be 0
    }

    It 'fails when the VMs do not reach Ok in time' {
        $global:VMFleetStubHooks['Get-FleetVM'] = { 1..3 | ForEach-Object { [pscustomobject]@{ Name = "vm-g-$_"; State = 'Ok' } } }
        $args0 = $script:DeployArgs.Clone(); $args0.WaitMinutes = 0
        { Invoke-NodeBody -Name Deploy -StepArgs $args0 -Secrets $script:DeploySecrets } | Should -Throw '*Only 3 of 8*'
    }

    It 'fails clearly without the password, without a base VHD, and when the VHD does not exist' {
        { Invoke-NodeBody -Name Deploy -StepArgs $script:DeployArgs -Secrets @{ ConnectPassword = 'x' } } | Should -Throw '*password did not arrive*'
        $noVhd = $script:DeployArgs.Clone(); $noVhd.BaseVhdPath = ''
        { Invoke-NodeBody -Name Deploy -StepArgs $noVhd -Secrets $script:DeploySecrets } | Should -Throw '*BaseVhdPath is empty*'
        $gone = $script:DeployArgs.Clone(); $gone.BaseVhdPath = (Join-Path $TestDrive 'missing.vhdx')
        { Invoke-NodeBody -Name Deploy -StepArgs $gone -Secrets $script:DeploySecrets } | Should -Throw '*not found on the node*'
    }
}

Describe 'Test payload (Start-FleetSweep)' {
    BeforeEach {
        Mock Import-Module { }
        $global:VMFleetStubHooks = @{ 'Get-FleetVM' = { 1..4 | ForEach-Object { [pscustomobject]@{ Name = "vm-g-$_"; State = 'Ok' } } } }
        $script:Collect = Join-Path $TestDrive ('collect' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Collect | Out-Null
    }

    It 'runs Start-FleetSweep with -b -t -o -w -p -d -Warm -Cool -AddSpec (the Day2Smoke values) and tags the results' {
        $r = Invoke-NodeBody -Name Test -StepArgs @{ Tag = 'day2smoke20261124'; RunId = 'day2smoke-20261124'; CollectPath = $script:Collect; BlockSizeKB = 8; Threads = 2; OutstandingIO = 8; WriteRatio = 30; Pattern = 'r'; DurationSeconds = 600; WarmupSeconds = 120; CooldownSeconds = 30 }
        $sweep = ($global:VMFleetStubCalls | Where-Object Name -eq 'Start-FleetSweep').Bound
        $sweep.b | Should -Be 8
        $sweep.t | Should -Be 2
        $sweep.o | Should -Be 8
        $sweep.w | Should -Be 30
        $sweep.p | Should -Be 'r'
        $sweep.d | Should -Be 600
        $sweep.Warm | Should -Be 120
        $sweep.Cool | Should -Be 30
        $sweep.AddSpec | Should -Be 'day2smoke20261124'
        $r.Tag | Should -Be 'day2smoke20261124'
        (Get-Content -LiteralPath (Join-Path $script:Collect 'loadtools\last-test.json') -Raw | ConvertFrom-Json).Tag | Should -Be 'day2smoke20261124'
    }

    It 'refuses to run when a fleet VM is not Ok' {
        $global:VMFleetStubHooks['Get-FleetVM'] = { [pscustomobject]@{ Name = 'vm-g-1'; State = 'Ok' }; [pscustomobject]@{ Name = 'vm-g-2'; State = 'Off' } }
        { Invoke-NodeBody -Name Test -StepArgs @{ Tag = 't1' } } | Should -Throw '*fleet is not ready*'
        @($global:VMFleetStubCalls | Where-Object Name -eq 'Start-FleetSweep').Count | Should -Be 0
    }

    It 'refuses an empty tag (it keeps repeated runs apart)' {
        { Invoke-NodeBody -Name Test -StepArgs @{} } | Should -Throw '*Tag is empty*'
    }
}

Describe 'Stop payload' {
    It 'calls Stop-Fleet' {
        Mock Import-Module { }
        $global:VMFleetStubHooks = @{ 'Get-FleetVM' = { [pscustomobject]@{ Name = 'vm-g-1'; State = 'Off' } } }
        $r = Invoke-NodeBody -Name Stop
        @($global:VMFleetStubCalls | Where-Object Name -eq 'Stop-Fleet').Count | Should -Be 1
        $r.VMs | Should -Be 1
    }
}

Describe 'Collect payload (DiskSpd XML results)' {
    BeforeAll {
        function script:New-DiskSpdXml {
            param([string]$Path, [double]$Seconds, [long]$ReadCount, [long]$WriteCount, [long]$ReadBytes, [long]$WriteBytes, [double]$ReadMs, [double]$WriteMs)
            @"
<Results><System><ComputerName>vm</ComputerName></System><TimeSpan><TestTimeSeconds>$Seconds</TestTimeSeconds><ThreadCount>2</ThreadCount>
<Latency><AverageReadMilliseconds>$ReadMs</AverageReadMilliseconds><AverageWriteMilliseconds>$WriteMs</AverageWriteMilliseconds></Latency>
<Thread><Id>0</Id><Target><Path>C:\run\testfile1.dat</Path><ReadBytes>$ReadBytes</ReadBytes><WriteBytes>$WriteBytes</WriteBytes><ReadCount>$ReadCount</ReadCount><WriteCount>$WriteCount</WriteCount></Target></Thread></TimeSpan></Results>
"@ | Set-Content -LiteralPath $Path -Encoding utf8
        }
    }
    BeforeEach {
        Mock Import-Module { }
        $script:ResultDir = Join-Path $TestDrive ('result' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:ResultDir | Out-Null
        $global:VMFleetResultDir = $script:ResultDir
        $global:VMFleetStubHooks = @{ 'Get-FleetPath' = { $global:VMFleetResultDir } }
    }
    AfterAll { Remove-Variable -Name VMFleetResultDir -Scope Global -ErrorAction SilentlyContinue }

    It 'reduces the XML files of the tagged run to per-VM IOPS, bytes per second and latency; ignores other runs' {
        New-DiskSpdXml -Path (Join-Path $script:ResultDir 'result-b8t2o8w30pr-runtag1-vm-g-1.xml') -Seconds 10 -ReadCount 70000 -WriteCount 30000 -ReadBytes 573440000 -WriteBytes 245760000 -ReadMs 2 -WriteMs 4
        New-DiskSpdXml -Path (Join-Path $script:ResultDir 'result-b8t2o8w30pr-runtag1-vm-g-2.xml') -Seconds 10 -ReadCount 35000 -WriteCount 15000 -ReadBytes 286720000 -WriteBytes 122880000 -ReadMs 3 -WriteMs 5
        New-DiskSpdXml -Path (Join-Path $script:ResultDir 'result-b8t2o8w30pr-oldrun-vm-g-1.xml') -Seconds 10 -ReadCount 1 -WriteCount 1 -ReadBytes 1 -WriteBytes 1 -ReadMs 9 -WriteMs 9
        $r = Invoke-NodeBody -Name Collect -StepArgs @{ Tag = 'runtag1' }
        $r.Files | Should -Be 2
        $r.VMs.Count | Should -Be 2
        $vm1 = $r.VMs | Where-Object { $_.VMName -eq 'vm-g-1' }
        $vm1.ReadIOPS | Should -Be 7000
        $vm1.WriteIOPS | Should -Be 3000
        $vm1.ReadBytesPerSecond | Should -Be 57344000
        $vm1.ReadLatencyMs | Should -Be 2
        $vm1.WriteLatencyMs | Should -Be 4
    }

    It 'finds the tag of the last test when none is given' {
        New-DiskSpdXml -Path (Join-Path $script:ResultDir 'result-b8t2o8w30pr-lasttag-vm-g-1.xml') -Seconds 10 -ReadCount 100 -WriteCount 100 -ReadBytes 1 -WriteBytes 1 -ReadMs 1 -WriteMs 1
        $collect = Join-Path $TestDrive ('c' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $collect 'loadtools') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $collect 'loadtools\last-test.json') -Value '{"Tag":"lasttag"}'
        (Invoke-NodeBody -Name Collect -StepArgs @{ CollectPath = $collect }).Tag | Should -Be 'lasttag'
    }

    It 'fails when no result file matches, and when a result has no target data' {
        { Invoke-NodeBody -Name Collect -StepArgs @{ Tag = 'nothing' } } | Should -Throw '*No DiskSpd result files*'
        Set-Content -LiteralPath (Join-Path $script:ResultDir 'result-x-broken-vm-g-1.xml') -Value '<Results><TimeSpan><TestTimeSeconds>10</TestTimeSeconds></TimeSpan></Results>'
        { Invoke-NodeBody -Name Collect -StepArgs @{ Tag = 'broken' } } | Should -Throw '*no DiskSpd target data*'
    }
}

Describe 'Remove payload (Remove-Fleet)' {
    BeforeEach {
        Mock Import-Module { }
        $script:Csv = Join-Path $TestDrive ('csv' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Csv | Out-Null
        $global:VMFleetCsvRoot = $script:Csv
        $global:VMFleetStubHooks = @{
            'Get-ClusterSharedVolume' = { [pscustomobject]@{ SharedVolumeInfo = [pscustomobject]@{ FriendlyVolumeName = $global:VMFleetCsvRoot } } }
        }
    }
    AfterAll { Remove-Variable -Name VMFleetCsvRoot -Scope Global -ErrorAction SilentlyContinue }

    It 'stops the fleet, removes it with Remove-Fleet (every VM) and reports nothing left' {
        $r = Invoke-NodeBody -Name Remove
        ($global:VMFleetStubCalls | ForEach-Object Name) | Should -Be @('Stop-Fleet', 'Remove-Fleet', 'Get-FleetVM')
        (@($global:VMFleetStubCalls | Where-Object Name -eq 'Remove-Fleet').Bound.Keys) | Should -Not -Contain 'VMs'
        @($r.RemainingVMs).Count | Should -Be 0
        @($r.RemainingDirectories).Count | Should -Be 0
    }

    It 'reports a leftover VM and a leftover vm-* folder so the caller can fail' {
        New-Item -ItemType Directory -Path (Join-Path $script:Csv 'vm-g-node1-001') | Out-Null
        $global:VMFleetStubHooks['Get-FleetVM'] = { [pscustomobject]@{ Name = 'vm-g-node1-001'; State = 'Off' } }
        $r = Invoke-NodeBody -Name Remove
        @($r.RemainingVMs) | Should -Be @('vm-g-node1-001')
        @($r.RemainingDirectories).Count | Should -Be 1
    }

    It 'goes on with the removal when Stop-Fleet complains' {
        $global:VMFleetStubHooks['Stop-Fleet'] = { throw 'no fleet running' }
        { Invoke-NodeBody -Name Remove } | Should -Not -Throw
        @($global:VMFleetStubCalls | Where-Object Name -eq 'Remove-Fleet').Count | Should -Be 1
    }

    It 'with RemoveCollectData deletes the DiskSpd results from the result folder only' {
        $resultDir = Join-Path $TestDrive ('res' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $resultDir | Out-Null
        $global:VMFleetResultDir = $resultDir
        $global:VMFleetStubHooks['Get-FleetPath'] = { $global:VMFleetResultDir }
        Set-Content -LiteralPath (Join-Path $resultDir 'result-a.xml') -Value 'x'
        Set-Content -LiteralPath (Join-Path $resultDir 'perfctr-a.blg') -Value 'x'
        Set-Content -LiteralPath (Join-Path $resultDir 'keep.txt') -Value 'x'
        $r = Invoke-NodeBody -Name Remove -StepArgs @{ RemoveCollectData = $true }
        $r.RemovedResultFiles | Should -Be 2
        Test-Path (Join-Path $resultDir 'keep.txt') | Should -BeTrue
        Test-Path (Join-Path $resultDir 'result-a.xml') | Should -BeFalse
        Remove-Variable -Name VMFleetResultDir -Scope Global -ErrorAction SilentlyContinue
    }
}
