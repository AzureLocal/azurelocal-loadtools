# =============================================================================
# VMFleet-Common.ps1 - Azure Local Load Tools
# =============================================================================
# Shared helper for every VMFleet step (install, deploy, test, stop, collect,
# remove). Dot-source it after common\helpers\Common-Functions.ps1.
#
# Why it exists
#   The management host that runs Load Tools is usually NOT domain-joined. It
#   reaches each cluster node by its management IP over WinRM (HTTP 5985, NTLM,
#   the IPs in TrustedHosts) with an explicit domain credential. The VMFleet
#   module must run ON a cluster node: its cmdlets default to -Cluster '.' and
#   call Get-ClusterNode, CSV paths and remoting to the other nodes. Inside an
#   NTLM remoting session that second hop fails, and CredSSP is deliberately not
#   used. So every step runs as a ONE-SHOT SCHEDULED TASK on the first node:
#
#     1. Open one remoting session to the node (explicit credential).
#     2. Write a generated script, its (non-secret) arguments and a run folder
#        to the Collect volume (C:\ClusterStorage\Collect\loadtools\<run>\<step>).
#     3. Register a task with that credential (logon type Password, RunLevel
#        Highest), start it, unregister it again when it is done.
#     4. The task runs the script locally on the node, writes a transcript and
#        result.json into the run folder; this host polls the task and reads
#        result.json over the same kind of session.
#
#   Secrets (the fleet VM password) are never written to disk or to a log: they
#   travel through the encrypted remoting channel into an in-memory named pipe
#   that only the task account can read, and the node script scrubs them from
#   its transcript and result.
#
# The node-side payloads (tools\vmfleet\scripts\node\*.node.ps1) run in
# Windows PowerShell 5.1 on the node, because the VMFleet module and the
# FailoverClusters module require it.
# =============================================================================

#Requires -Version 7.2

Set-StrictMode -Version Latest

function Get-VMFleetDefaultCollectPath { 'C:\ClusterStorage\Collect' }

function Get-VMFleetTaskFolder { '\LoadTools\' }

function Write-VMFleetLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][ValidateSet('Information', 'Warning', 'Error')][string]$Severity = 'Information'
    )
    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Severity $Severity
    } else {
        Write-Verbose $Message
    }
}

function Get-VMFleetConfigValue {
    <#
    .SYNOPSIS
        Reads one key from a hashtable, ordered dictionary or PSCustomObject; returns $Default when it is absent
        (safe under Set-StrictMode).
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowNull()][object]$Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name) -and $null -ne $InputObject[$Name]) { return $InputObject[$Name] }
        return $Default
    }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function Get-VMFleetDefaultClusterConfigPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path $ProjectRoot 'config\clusters\cluster.yml'
}

function Get-VMFleetClusterConfig {
    <#
    .SYNOPSIS
        Reads the cluster YAML and returns what the VMFleet steps need.
    .DESCRIPTION
        Layout (see config\clusters\example-cluster.yml):

          cluster:
            name: azl-cluster-01          # for reports only
          nodes:
            - name: 192.0.2.11            # the remoting target: the node's management IP
              hostname: azl-node-01       # optional, display only
          storage:
            collect_path: C:\ClusterStorage\Collect
            node_volumes: [C:\ClusterStorage\azl-node-01, ...]
            base_vhd_path: C:\ClusterStorage\Collect\base\base.vhdx

        A node entry may also be a bare string (the IP). The older nested layout
        (cluster.nodes[].management_ip, cluster.collect_volume_path) is still read.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ClusterConfigPath)

    if (-not (Test-Path -LiteralPath $ClusterConfigPath)) {
        throw "Cluster config not found: $ClusterConfigPath. Copy config\clusters\example-cluster.yml to config\clusters\cluster.yml (or pass -ClusterConfigPath) and edit it."
    }
    Import-Module powershell-yaml -ErrorAction Stop
    $raw = Get-Content -LiteralPath $ClusterConfigPath -Raw | ConvertFrom-Yaml
    if ($null -eq $raw) { throw "Cluster config is empty: $ClusterConfigPath" }

    $cluster = Get-VMFleetConfigValue $raw 'cluster'
    $storage = Get-VMFleetConfigValue $raw 'storage'

    $entries = @(Get-VMFleetConfigValue $raw 'nodes' @())
    if ($entries.Count -eq 0 -and $null -ne $cluster) { $entries = @(Get-VMFleetConfigValue $cluster 'nodes' @()) }
    if ($entries.Count -eq 0) { throw "Cluster config has no nodes: $ClusterConfigPath. List the nodes under 'nodes:' with their management IP in 'name'." }

    $targets = [System.Collections.Generic.List[string]]::new()
    $hostnames = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $entries) {
        if ($entry -is [string]) {
            $target = $entry; $hostname = $entry
        } else {
            $name = [string](Get-VMFleetConfigValue $entry 'name' '')
            $target = [string](Get-VMFleetConfigValue $entry 'management_ip' $name)
            $hostname = [string](Get-VMFleetConfigValue $entry 'hostname' $name)
        }
        if ([string]::IsNullOrWhiteSpace($target)) { throw "A node entry in $ClusterConfigPath has no name or management_ip." }
        $targets.Add($target.Trim())
        $hostnames.Add($hostname.Trim())
    }

    $collect = Get-VMFleetConfigValue $storage 'collect_path'
    if (-not $collect) { $collect = Get-VMFleetConfigValue $storage 'collect_volume_path' }
    if (-not $collect) { $collect = Get-VMFleetConfigValue $cluster 'collect_volume_path' }
    if (-not $collect) { $collect = (Get-VMFleetDefaultCollectPath) }

    $baseVhd = Get-VMFleetConfigValue $storage 'base_vhd_path'
    if (-not $baseVhd) { $baseVhd = Get-VMFleetConfigValue $cluster 'base_vhd_path' }

    $nodeVolumes = @(Get-VMFleetConfigValue $storage 'node_volumes' @() | ForEach-Object { [string]$_ })

    [pscustomobject]@{
        ClusterName  = [string](Get-VMFleetConfigValue $cluster 'name' (Get-VMFleetConfigValue $raw 'cluster_name' 'unknown'))
        Nodes        = $targets.ToArray()
        Hostnames    = $hostnames.ToArray()
        PrimaryNode  = $targets[0]
        CollectPath  = ([string]$collect).TrimEnd('\')
        NodeVolumes  = $nodeVolumes
        BaseVhdPath  = [string]$baseVhd
    }
}

function ConvertTo-VMFleetSafeName {
    <#
    .SYNOPSIS
        Letters and digits only: safe in a task name, a folder name and a DiskSpd result file name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter()][int]$MaxLength = 40)
    $safe = ($Name -replace '[^A-Za-z0-9]', '')
    if (-not $safe) { throw "Name '$Name' has no letters or digits." }
    if ($safe.Length -gt $MaxLength) { $safe = $safe.Substring($safe.Length - $MaxLength) }
    $safe
}

function ConvertTo-VMFleetBlockSizeKB {
    <#
    .SYNOPSIS
        '8k' -> 8, '64K' -> 64, '1m' -> 1024, '4' -> 4. Start-FleetSweep -b takes KB.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object]$BlockSize)
    $text = ([string]$BlockSize).Trim().ToLowerInvariant()
    if ($text -notmatch '^(?<n>\d+)(?<u>[km]?)$') { throw "Block size '$BlockSize' is not valid. Use a number with an optional k or m suffix, for example 8k." }
    $n = [int]$Matches['n']
    if ($Matches['u'] -eq 'm') { $n = $n * 1024 }
    if ($n -lt 1) { throw "Block size '$BlockSize' must be at least 1 KB." }
    $n
}

function Select-VMFleetTestValue {
    <#
    .SYNOPSIS
        One test parameter: explicit override > profile.parameters > solution JSON > default.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Override,
        [Parameter(Mandatory)][string]$OverrideKey,
        [Parameter()][AllowNull()][object]$ProfileParameters,
        [Parameter(Mandatory)][string[]]$ProfileKeys,
        [Parameter()][AllowNull()][object]$SolutionConfig,
        [Parameter(Mandatory)][string[]]$SolutionKeys,
        [Parameter(Mandatory)][object]$Default,
        # 0 is a real value (write ratio, cool-down); for the others 0 means "not given".
        [Parameter()][switch]$AllowZero
    )
    if ($Override.ContainsKey($OverrideKey) -and $null -ne $Override[$OverrideKey]) {
        $text = "$($Override[$OverrideKey])"
        if ($text -ne '' -and ($AllowZero -or $text -ne '0')) { return $Override[$OverrideKey] }
    }
    foreach ($k in $ProfileKeys) {
        $v = Get-VMFleetConfigValue $ProfileParameters $k
        if ($null -ne $v) { return $v }
    }
    foreach ($k in $SolutionKeys) {
        $v = Get-VMFleetConfigValue $SolutionConfig $k
        if ($null -ne $v) { return $v }
    }
    return $Default
}

function Resolve-VMFleetTestParameters {
    <#
    .SYNOPSIS
        Resolves the DiskSpd sweep parameters: explicit value > profile (profile.parameters) > solution JSON > default.
    .DESCRIPTION
        The profile YAML nests its values under profile.parameters and names them duration_seconds,
        warmup_seconds and cooldown_seconds; the older names duration / warmup are still read.
        VMFleet's sweep takes a random OR sequential pattern, not a mix: random_ratio >= 50 selects 'r'
        (random), below 50 selects 's' (sequential), and Mixed is True when the profile asked for a mix.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$LoadProfile,
        [Parameter()][AllowNull()][object]$SolutionConfig,
        [Parameter()][hashtable]$Override = @{}
    )

    $profileRoot = Get-VMFleetConfigValue $LoadProfile 'profile'
    if ($null -eq $profileRoot) { $profileRoot = $LoadProfile }
    $pp = Get-VMFleetConfigValue $profileRoot 'parameters'

    $common = @{ Override = $Override; ProfileParameters = $pp; SolutionConfig = $SolutionConfig }
    $block = Select-VMFleetTestValue @common -OverrideKey 'BlockSize' -ProfileKeys @('block_size') -SolutionKeys @('block_size') -Default '8k'
    $write = [int](Select-VMFleetTestValue @common -OverrideKey 'WriteRatio' -ProfileKeys @('write_ratio') -SolutionKeys @('write_ratio') -Default 30 -AllowZero)
    $random = [int](Select-VMFleetTestValue @common -OverrideKey 'RandomRatio' -ProfileKeys @('random_ratio') -SolutionKeys @('random_ratio') -Default 70 -AllowZero)
    $oio = [int](Select-VMFleetTestValue @common -OverrideKey 'OutstandingIO' -ProfileKeys @('outstanding_io') -SolutionKeys @('outstanding_io') -Default 8)
    $threads = [int](Select-VMFleetTestValue @common -OverrideKey 'ThreadsPerVM' -ProfileKeys @('threads_per_vm') -SolutionKeys @('threads_per_vm') -Default 2)
    $duration = [int](Select-VMFleetTestValue @common -OverrideKey 'DurationSeconds' -ProfileKeys @('duration_seconds', 'duration') -SolutionKeys @('test_duration_seconds') -Default 300)
    $warmup = [int](Select-VMFleetTestValue @common -OverrideKey 'WarmupSeconds' -ProfileKeys @('warmup_seconds', 'warmup') -SolutionKeys @('warmup_seconds') -Default 60 -AllowZero)
    $cooldown = [int](Select-VMFleetTestValue @common -OverrideKey 'CooldownSeconds' -ProfileKeys @('cooldown_seconds', 'cooldown') -SolutionKeys @('cooldown_seconds') -Default 30 -AllowZero)

    if ($write -lt 0 -or $write -gt 100) { throw "write_ratio $write is outside 0-100." }
    if ($random -lt 0 -or $random -gt 100) { throw "random_ratio $random is outside 0-100." }
    if ($duration -lt 1) { throw 'duration_seconds must be at least 1.' }
    if ($warmup -lt 0 -or $cooldown -lt 0) { throw 'warmup_seconds and cooldown_seconds cannot be negative.' }

    [pscustomobject]@{
        ProfileName     = [string](Get-VMFleetConfigValue $profileRoot 'name' 'custom')
        BlockSizeKB     = ConvertTo-VMFleetBlockSizeKB $block
        WriteRatio      = $write
        RandomRatio     = $random
        Pattern         = $(if ($random -ge 50) { 'r' } else { 's' })
        Mixed           = ($random -gt 0 -and $random -lt 100)
        OutstandingIO   = $oio
        ThreadsPerVM    = $threads
        DurationSeconds = $duration
        WarmupSeconds   = $warmup
        CooldownSeconds = $cooldown
        TotalSeconds    = $duration + $warmup + $cooldown
    }
}

function Import-VMFleetProfile {
    [CmdletBinding()]
    param([Parameter()][string]$ProfilePath)
    if (-not $ProfilePath) { return $null }
    if (-not (Test-Path -LiteralPath $ProfilePath)) { throw "Profile not found: $ProfilePath" }
    Import-Module powershell-yaml -ErrorAction Stop
    Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Yaml
}

function Get-VMFleetReportFormatSupport {
    <#
    .SYNOPSIS
        Tells whether the tool a report format needs is installed (PDF: asciidoctor-pdf, DOCX: asciidoctor and
        pandoc, XLSX: the ImportExcel module). HTML needs nothing.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('HTML', 'PDF', 'DOCX', 'XLSX')][string]$Format)

    $missing = switch ($Format) {
        'HTML' { @() }
        'PDF' { @(if (-not (Get-Command -Name 'asciidoctor-pdf' -ErrorAction SilentlyContinue)) { 'asciidoctor-pdf (gem install asciidoctor-pdf)' }) }
        'DOCX' {
            @(
                if (-not (Get-Command -Name 'asciidoctor' -ErrorAction SilentlyContinue)) { 'asciidoctor (gem install asciidoctor)' }
                if (-not (Get-Command -Name 'pandoc' -ErrorAction SilentlyContinue)) { 'pandoc' }
            )
        }
        'XLSX' { @(if (-not (Get-Module -ListAvailable -Name ImportExcel)) { 'the ImportExcel module (Install-Module ImportExcel)' }) }
    }
    $missing = @($missing)
    [pscustomobject]@{
        Format    = $Format
        Available = ($missing.Count -eq 0)
        Reason    = $(if ($missing.Count -eq 0) { '' } else { 'missing ' + ($missing -join ' and ') })
    }
}

function Get-VMFleetNodeScriptText {
    <#
    .SYNOPSIS
        Returns the text of a node-side payload (tools\vmfleet\scripts\node\<Name>.node.ps1).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Install', 'Deploy', 'Test', 'Stop', 'Collect', 'Remove')][string]$Name)
    $path = Join-Path (Join-Path $PSScriptRoot 'node') "$Name.node.ps1"
    if (-not (Test-Path -LiteralPath $path)) { throw "Node script not found: $path" }
    Get-Content -LiteralPath $path -Raw
}

function Get-VMFleetNodeWrapperScript {
    <#
    .SYNOPSIS
        Builds the script the scheduled task runs on the node (Windows PowerShell 5.1): reads the arguments and
        the in-memory secrets, runs the step body, writes the transcript and result.json, scrubs secrets.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Body)

    $template = @'
param(
    [Parameter(Mandatory = $true)][string]$RunDir,
    [Parameter()][string]$PipeName = ''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$resultPath = Join-Path $RunDir 'result.json'
$transcriptPath = Join-Path $RunDir 'transcript.log'
$Secrets = @{}
$StepArgs = $null
$StepResult = $null
$taskResult = [ordered]@{ Status = 'Failed'; Started = (Get-Date).ToUniversalTime().ToString('o'); Finished = $null; Output = $null; Error = $null }

function Get-Arg {
    param([string]$Name, $Default = $null)
    $p = $StepArgs.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Protect-Text {
    param([string]$Text)
    foreach ($s in @($Secrets.Values)) {
        if ($s) {
            $Text = $Text.Replace([string]$s, '********')
            $escaped = ([string]$s).Replace('\', '\\').Replace('"', '\"')
            if ($escaped -ne [string]$s) { $Text = $Text.Replace($escaped, '********') }
        }
    }
    return $Text
}

try { Start-Transcript -Path $transcriptPath -Force | Out-Null } catch { Write-Host "Transcript not started: $($_.Exception.Message)" }
try {
    if ($PipeName) {
        $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::In)
        try {
            $client.Connect(60000)
            $reader = New-Object System.IO.StreamReader($client)
            $secretJson = $reader.ReadToEnd()
        } finally {
            $client.Dispose()
        }
        $secretObject = $secretJson | ConvertFrom-Json
        foreach ($p in $secretObject.PSObject.Properties) { $Secrets[$p.Name] = [string]$p.Value }
    }
    $StepArgs = Get-Content -LiteralPath (Join-Path $RunDir 'args.json') -Raw | ConvertFrom-Json

    . {
#__LOADTOOLS_BODY__
    } | Out-Host

    $taskResult.Output = $StepResult
    $taskResult.Status = 'Succeeded'
} catch {
    $taskResult.Error = Protect-Text ([string]$_.Exception.Message)
    Write-Host ('STEP FAILED: ' + $taskResult.Error)
} finally {
    $taskResult.Finished = (Get-Date).ToUniversalTime().ToString('o')
    try { Stop-Transcript | Out-Null } catch { Write-Host "Stop-Transcript: $($_.Exception.Message)" }
    if (Test-Path -LiteralPath $transcriptPath) {
        $text = Get-Content -LiteralPath $transcriptPath -Raw
        if ($text) { Set-Content -LiteralPath $transcriptPath -Value (Protect-Text $text) -Encoding UTF8 }
    }
    $json = Protect-Text ($taskResult | ConvertTo-Json -Depth 8)
    Set-Content -LiteralPath ($resultPath + '.tmp') -Value $json -Encoding UTF8
    Move-Item -LiteralPath ($resultPath + '.tmp') -Destination $resultPath -Force
}
if ($taskResult.Status -ne 'Succeeded') { exit 1 }
exit 0
'@
    $template.Replace('#__LOADTOOLS_BODY__', $Body)
}

# --- script blocks that run ON the node, inside the remoting session (Windows PowerShell 5.1) ---

function Get-VMFleetStartBlock {
    {
        param($RunDir, $WrapperText, $ArgsJson, $TaskName, $TaskPath, $UserName, $UserSecret, $SecretJson, $PipeName, $PipeTimeoutSeconds, $NodePowerShell)
        $ErrorActionPreference = 'Stop'
        if (-not (Test-Path -LiteralPath $RunDir)) { New-Item -ItemType Directory -Path $RunDir -Force | Out-Null }
        foreach ($old in 'result.json', 'result.json.tmp', 'transcript.log') {
            Remove-Item -LiteralPath (Join-Path $RunDir $old) -Force -ErrorAction SilentlyContinue
        }
        $wrapperPath = Join-Path $RunDir 'run.ps1'
        Set-Content -LiteralPath $wrapperPath -Value $WrapperText -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $RunDir 'args.json') -Value $ArgsJson -Encoding UTF8

        $argument = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RunDir "{1}"' -f $wrapperPath, $RunDir
        if ($PipeName) { $argument += (' -PipeName "{0}"' -f $PipeName) }
        $action = New-ScheduledTaskAction -Execute $NodePowerShell -Argument $argument
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 12)

        # -User with -Password registers the task with logon type Password; RunLevel Highest = elevated token.
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action -Settings $settings -User $UserName -Password $UserSecret -RunLevel Highest -Force | Out-Null
        $UserSecret = $null

        $server = $null
        try {
            if ($PipeName) {
                # In-memory hand-over of the secrets: only the task account may connect to this pipe.
                $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
                $pipeSecurity = New-Object System.IO.Pipes.PipeSecurity
                $rule = New-Object System.IO.Pipes.PipeAccessRule($sid, [System.IO.Pipes.PipeAccessRights]::ReadWrite, [System.Security.AccessControl.AccessControlType]::Allow)
                $pipeSecurity.AddAccessRule($rule)
                $server = New-Object System.IO.Pipes.NamedPipeServerStream($PipeName, [System.IO.Pipes.PipeDirection]::Out, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, 0, 0, $pipeSecurity)
            }
            Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
            if ($server) {
                $wait = $server.BeginWaitForConnection($null, $null)
                if (-not $wait.AsyncWaitHandle.WaitOne([int]$PipeTimeoutSeconds * 1000)) {
                    throw 'The node task did not connect to receive its secrets in time.'
                }
                $server.EndWaitForConnection($wait)
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($SecretJson)
                $server.Write($bytes, 0, $bytes.Length)
                $server.Flush()
                $server.WaitForPipeDrain()
            }
        } catch {
            Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            throw
        } finally {
            if ($server) { $server.Dispose() }
        }
    }
}

function Get-VMFleetPollBlock {
    {
        param($TaskName, $TaskPath, $RunDir)
        $state = @{ State = 'Missing'; LastTaskResult = $null; ResultJson = $null; Tail = $null }
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        if ($task) {
            $state.State = [string]$task.State
            $state.LastTaskResult = (Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath).LastTaskResult
        }
        $resultFile = Join-Path $RunDir 'result.json'
        if (Test-Path -LiteralPath $resultFile) { $state.ResultJson = Get-Content -LiteralPath $resultFile -Raw }
        $transcriptFile = Join-Path $RunDir 'transcript.log'
        if (Test-Path -LiteralPath $transcriptFile) { $state.Tail = (Get-Content -LiteralPath $transcriptFile -Tail 30) -join "`n" }
        $state
    }
}

function Get-VMFleetCleanupBlock {
    {
        param($TaskName, $TaskPath, $StopFirst)
        if ($StopFirst) { Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue }
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Open-VMFleetNodeSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][pscredential]$Credential
    )
    # Negotiate falls back to NTLM for an IP address; the IP must be in TrustedHosts.
    New-PSSession -ComputerName $ComputerName -Credential $Credential -Authentication Negotiate -ErrorAction Stop
}

function Invoke-VMFleetSessionCommand {
    # Thin wrapper around Invoke-Command -Session so the tests can replace it (a mocked Invoke-Command would demand a real PSSession).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter()][object[]]$ArgumentList
    )
    Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
}

function Close-VMFleetNodeSession {
    [CmdletBinding()]
    param([Parameter()][object]$Session)
    if ($Session) { Remove-PSSession -Session $Session -ErrorAction SilentlyContinue }
}

function Get-VMFleetNodeTaskHandle {
    <#
    .SYNOPSIS
        Builds the (deterministic) handle of a node task from the run id and step, so a later process can wait for it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Step,
        [Parameter()][string]$CollectPath = (Get-VMFleetDefaultCollectPath)
    )
    $safeRun = ConvertTo-VMFleetSafeName -Name $RunId
    $safeStep = ConvertTo-VMFleetSafeName -Name $Step
    $runDir = '{0}\loadtools\{1}\{2}' -f $CollectPath.TrimEnd('\'), $safeRun, $safeStep
    [pscustomobject]@{
        ComputerName   = $ComputerName
        Step           = $safeStep
        TaskName       = "LoadTools-VMFleet-$safeStep-$safeRun"
        TaskPath       = (Get-VMFleetTaskFolder)
        RunDir         = $runDir
        TranscriptPath = "$runDir\transcript.log"
        ResultPath     = "$runDir\result.json"
    }
}

function Start-VMFleetNodeTask {
    <#
    .SYNOPSIS
        Registers and starts a one-shot task on a node that runs a generated script locally. Returns the handle.
    .PARAMETER Step
        Name of the node payload: Install, Deploy, Test, Stop, Collect or Remove.
    .PARAMETER Arguments
        Non-secret arguments; the payload reads them with Get-Arg. Written to args.json on the node.
    .PARAMETER Secrets
        Secret values; delivered through an in-memory named pipe, never written to disk.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Every caller gates the call with ShouldProcess (-WhatIf/-Confirm) before it starts a task.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][ValidateSet('Install', 'Deploy', 'Test', 'Stop', 'Collect', 'Remove')][string]$Step,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter()][hashtable]$Arguments = @{},
        [Parameter()][hashtable]$Secrets = @{},
        [Parameter()][string]$CollectPath = (Get-VMFleetDefaultCollectPath),
        [Parameter()][int]$PipeTimeoutSeconds = 120,
        [Parameter()][string]$NodePowerShell = 'powershell.exe'
    )

    $handle = Get-VMFleetNodeTaskHandle -ComputerName $ComputerName -RunId $RunId -Step $Step -CollectPath $CollectPath
    $wrapper = Get-VMFleetNodeWrapperScript -Body (Get-VMFleetNodeScriptText -Name $Step)
    $argsJson = $Arguments | ConvertTo-Json -Depth 6
    if ($Secrets.Count -gt 0) {
        $pipeName = 'loadtools-' + [guid]::NewGuid().ToString('N')
        $secretJson = $Secrets | ConvertTo-Json -Compress
    } else {
        $pipeName = ''
        $secretJson = ''
    }

    $session = $null
    try {
        Write-VMFleetLog "Starting node task $($handle.TaskName) on $ComputerName (run folder $($handle.RunDir))"
        $session = Open-VMFleetNodeSession -ComputerName $ComputerName -Credential $Credential
        $plain = $Credential.GetNetworkCredential().Password
        Invoke-VMFleetSessionCommand -Session $session -ScriptBlock (Get-VMFleetStartBlock) -ArgumentList @(
            $handle.RunDir, $wrapper, $argsJson, $handle.TaskName, $handle.TaskPath,
            $Credential.UserName, $plain, $secretJson, $pipeName, $PipeTimeoutSeconds, $NodePowerShell
        ) | Out-Null
        $plain = $null
    } finally {
        $secretJson = $null
        if ($session) { Close-VMFleetNodeSession -Session $session }
    }
    $handle | Add-Member -NotePropertyName StartedUtc -NotePropertyValue ([datetime]::UtcNow) -PassThru
}

function Wait-VMFleetNodeTask {
    <#
    .SYNOPSIS
        Polls a node task until it writes result.json, returns the parsed result and always unregisters the task.
    .DESCRIPTION
        Throws when the step failed (with the error and the transcript path), when the task ended without a result,
        or when -TimeoutSeconds passes (the task is stopped and unregistered).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Handle,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter()][int]$TimeoutSeconds = 3600,
        [Parameter()][int]$PollSeconds = 15,
        [Parameter()][int]$StartGraceSeconds = 60
    )

    $session = $null
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $failures = 0
    $stopOnCleanup = $false
    $poll = $null
    try {
        while ($true) {
            try {
                if (-not $session) { $session = Open-VMFleetNodeSession -ComputerName $Handle.ComputerName -Credential $Credential }
                $poll = Invoke-VMFleetSessionCommand -Session $session -ScriptBlock (Get-VMFleetPollBlock) -ArgumentList @($Handle.TaskName, $Handle.TaskPath, $Handle.RunDir)
                $failures = 0
            } catch {
                $failures++
                if ($session) { Close-VMFleetNodeSession -Session $session; $session = $null }
                if ($failures -ge 5) { throw "Lost contact with $($Handle.ComputerName) while waiting for $($Handle.TaskName): $($_.Exception.Message)" }
                Write-VMFleetLog "Poll of $($Handle.TaskName) failed ($failures/5): $($_.Exception.Message)" -Severity Warning
                Start-Sleep -Seconds $PollSeconds
                continue
            }

            if ($poll.ResultJson) { break }

            if ($poll.State -notin @('Running', 'Queued') -and $stopwatch.Elapsed.TotalSeconds -gt $StartGraceSeconds) {
                $tail = if ($poll.Tail) { "`nLast transcript lines:`n$($poll.Tail)" } else { '' }
                throw "Node task $($Handle.TaskName) on $($Handle.ComputerName) ended (state $($poll.State), last result $($poll.LastTaskResult)) without writing a result. Transcript: $($Handle.TranscriptPath)$tail"
            }
            if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $stopOnCleanup = $true
                throw "Node task $($Handle.TaskName) on $($Handle.ComputerName) did not finish within $TimeoutSeconds seconds and was stopped. Transcript: $($Handle.TranscriptPath)"
            }
            Start-Sleep -Seconds $PollSeconds
        }

        $result = $poll.ResultJson | ConvertFrom-Json
        if ($result.Status -ne 'Succeeded') {
            throw "VMFleet step $($Handle.Step) failed on $($Handle.ComputerName): $($result.Error) (transcript: $($Handle.TranscriptPath))"
        }
        Write-VMFleetLog "Node task $($Handle.TaskName) succeeded"
        $result | Add-Member -NotePropertyName TranscriptPath -NotePropertyValue $Handle.TranscriptPath -PassThru
    } finally {
        try {
            if (-not $session) { $session = Open-VMFleetNodeSession -ComputerName $Handle.ComputerName -Credential $Credential }
            Invoke-VMFleetSessionCommand -Session $session -ScriptBlock (Get-VMFleetCleanupBlock) -ArgumentList @($Handle.TaskName, $Handle.TaskPath, $stopOnCleanup) | Out-Null
        } catch {
            Write-VMFleetLog "Could not unregister task $($Handle.TaskName) on $($Handle.ComputerName): $($_.Exception.Message). Remove it with Unregister-ScheduledTask." -Severity Warning
        }
        if ($session) { Close-VMFleetNodeSession -Session $session }
    }
}

function Invoke-VMFleetNodeTask {
    <#
    .SYNOPSIS
        Runs one VMFleet step on a node as a one-shot scheduled task and returns its result (Start + Wait).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][ValidateSet('Install', 'Deploy', 'Test', 'Stop', 'Collect', 'Remove')][string]$Step,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter()][hashtable]$Arguments = @{},
        [Parameter()][hashtable]$Secrets = @{},
        [Parameter()][string]$CollectPath = (Get-VMFleetDefaultCollectPath),
        [Parameter()][int]$TimeoutSeconds = 3600,
        [Parameter()][int]$PollSeconds = 15
    )
    $handle = Start-VMFleetNodeTask -ComputerName $ComputerName -Credential $Credential -Step $Step -RunId $RunId -Arguments $Arguments -Secrets $Secrets -CollectPath $CollectPath
    Wait-VMFleetNodeTask -Handle $handle -Credential $Credential -TimeoutSeconds $TimeoutSeconds -PollSeconds $PollSeconds
}

function Get-VMFleetCredentialOrExit {
    <#
    .SYNOPSIS
        Returns -Credential, or the managed cluster_admin credential (CLUSTER_ADMIN_USERNAME / CLUSTER_ADMIN_PASSWORD
        or Key Vault). Never prompts: when no credential is available it logs the reason and exits with code 2.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][pscredential]$Credential,
        [Parameter(Mandatory)][string]$ProjectRoot
    )
    if ($Credential) { return $Credential }
    Import-Module (Join-Path $ProjectRoot 'common\modules\CredentialManager\CredentialManager.psm1') -Force
    try {
        return Get-ManagedCredential -Name 'cluster_admin' -ProjectRoot $ProjectRoot
    } catch {
        Write-VMFleetLog -Message $_.Exception.Message -Severity Error
        exit 2
    }
}
