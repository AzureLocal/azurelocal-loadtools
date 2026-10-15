# =============================================================================
# FaultInjection.psm1 - Azure Local Load Tools
# =============================================================================
# Opt-in failure injection for load tests: validate storage performance UNDER a
# failure condition (Learn / Azure Well-Architected Framework for Azure Local:
# "validate ... under normal and intended failure conditions").
#
# Safety rules (all enforced in code, covered by mocked Pester tests):
#   - Never part of any default profile or pipeline run.
#   - Nothing happens without -AllowFault AND a ShouldProcess confirmation
#     (ConfirmImpact High, so the operator is asked unless -Confirm:$false is given).
#   - The UNDO command is printed (and returned) BEFORE anything is changed.
#   - Refuses when the cluster is not healthy, when a repair job is running, when
#     another fault is active (fault lock), when volumes are not online, when the
#     repair reserve is missing, or when the target is not safe.
#   - A two-node NodePause leaves ONE copy of the data: refused unless
#     -AcceptReducedRedundancy says the operator accepts that.
#   - The snapshot is re-collected after the confirmation and re-checked, and a
#     snapshot passed in by a caller must be fresh (MaxSnapshotAgeSeconds).
#   - The lock file is created atomically (CreateNew); the first writer wins.
#   - One fault at a time; the lock is kept until the undo has completed and the
#     cluster stayed Healthy for several consecutive polls. An unknown outcome keeps the lock.
#   - Node names and drive serial numbers are validated before they reach a remote script block.
#   - The original drive Usage is recorded and restored, not assumed.
#
# Known limit: the lock is a local file on the operator host. It does not stop a
# second operator on another host; run faults from one designated host.
#
# NOT PROVEN ON A LIVE CLUSTER. The command-construction, refusal and lock logic
# are unit-tested with mocks; the remote cmdlet behaviour has to be proven on a
# non-production Azure Local cluster before anyone relies on it.
# =============================================================================

#Requires -Version 7.2

Set-StrictMode -Version Latest

$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:LockPath = Join-Path $script:ProjectRoot 'state\fault-lock.json'

$script:NamePattern = '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$'
$script:SerialPattern = '^[A-Za-z0-9_.:-]{1,64}$'
$script:HostPattern = '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$'

function Invoke-FaultRemote {
    <#
    .SYNOPSIS
        Single seam for every remote call, so tests can mock it and nothing real runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [PSCredential]$Credential
    )
    $params = @{ ComputerName = $ComputerName; ScriptBlock = $ScriptBlock; ErrorAction = 'Stop' }
    if ($ArgumentList) { $params['ArgumentList'] = $ArgumentList }
    if ($Credential) { $params['Credential'] = $Credential }
    Invoke-Command @params
}

function Get-FaultLock {
    <#
    .SYNOPSIS
        Returns the active fault lock, or $null when no fault is recorded.
    #>
    [CmdletBinding()]
    param()
    if (-not (Test-Path -LiteralPath $script:LockPath)) { return $null }
    Get-Content -LiteralPath $script:LockPath -Raw | ConvertFrom-Json
}

function Set-FaultLock {
    <#
    .SYNOPSIS
        Records the active fault so a second fault is refused and the undo has something to read.
    .DESCRIPTION
        Status Pending creates the file atomically (FileMode.CreateNew) and fails when it already exists,
        so two invocations cannot both pass. The other statuses overwrite the existing lock.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan,
        [Parameter(Mandatory)][ValidateSet('Pending', 'Applied', 'Undoing')][string]$Status
    )
    $dir = Split-Path -Parent $script:LockPath
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $lock = [ordered]@{
        fault_type     = $Plan.FaultType
        node           = $Plan.NodeName
        method         = $Plan.Method
        serial_number  = $Plan.DiskSerialNumber
        pnp_instance   = $Plan.PnpInstanceId
        original_usage = $Plan.OriginalUsage
        computer_name  = $Plan.ComputerName
        status         = $Status
        started_at     = (Get-Date).ToUniversalTime().ToString('o')
        undo_command   = $Plan.UndoCommand
    }
    $json = $lock | ConvertTo-Json
    if (-not $PSCmdlet.ShouldProcess($script:LockPath, 'Write fault lock')) { return }
    if ($Status -eq 'Pending') {
        try {
            $fs = [System.IO.File]::Open($script:LockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        }
        catch [System.IO.IOException] {
            throw 'REFUSED: a fault lock already exists (another fault is active or an earlier one was never undone). Nothing was changed.'
        }
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $fs.Write($bytes, 0, $bytes.Length)
        }
        finally { $fs.Dispose() }
    }
    else {
        Set-Content -LiteralPath $script:LockPath -Value $json -Encoding utf8
    }
}

function Remove-FaultLock {
    <#
    .SYNOPSIS
        Clears the fault lock after a completed undo.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ((Test-Path -LiteralPath $script:LockPath) -and $PSCmdlet.ShouldProcess($script:LockPath, 'Remove fault lock')) {
        Remove-Item -LiteralPath $script:LockPath -Force
    }
}

function New-FaultPlan {
    <#
    .SYNOPSIS
        Builds the plan for one fault, including the exact apply and undo commands as text. Changes nothing.
    .PARAMETER FaultType
        NodePause (drain the node and put its storage in maintenance mode) or DriveFault (one data drive on a node).
    .PARAMETER NodeName
        The node the fault is applied to.
    .PARAMETER DiskSerialNumber
        DriveFault only: the drive (serial number) to take out. The module never picks a drive on its own.
    .PARAMETER Method
        DriveFault only: Retire (Set-PhysicalDisk -Usage Retired, reversible, the default) or PnpDisable (Disable-PnpDevice).
    .PARAMETER ComputerName
        Cluster or node the remote commands will run against (recorded in the lock and in the undo command).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory plan object only; changes nothing.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateSet('NodePause', 'DriveFault')][string]$FaultType,
        [Parameter(Mandatory)][string]$NodeName,
        [string]$DiskSerialNumber,
        [ValidateSet('Retire', 'PnpDisable')][string]$Method = 'Retire',
        [string]$ComputerName = '<cluster-name>'
    )

    if ($NodeName -notmatch $script:NamePattern) { throw "Invalid node name '$NodeName'." }
    if ($ComputerName -ne '<cluster-name>' -and $ComputerName -notmatch $script:HostPattern) { throw "Invalid computer name '$ComputerName'." }
    if ($FaultType -eq 'DriveFault') {
        if (-not $DiskSerialNumber) { throw 'DriveFault needs -DiskSerialNumber (one named drive; the module never picks a drive on its own).' }
        if ($DiskSerialNumber -notmatch $script:SerialPattern) { throw "Invalid drive serial number '$DiskSerialNumber'." }
    }
    elseif ($DiskSerialNumber) {
        throw '-DiskSerialNumber applies to DriveFault only.'
    }

    switch ($FaultType) {
        'NodePause' {
            $apply = @(
                "Suspend-ClusterNode -Name $NodeName -Drain   # then poll DrainStatus until Completed (bounded, no -Wait)",
                "Get-StorageFaultDomain -Type StorageScaleUnit | Where-Object FriendlyName -Eq $NodeName | Enable-StorageMaintenanceMode"
            )
            $undo = @(
                "Get-StorageFaultDomain -Type StorageScaleUnit | Where-Object FriendlyName -Eq $NodeName | Disable-StorageMaintenanceMode",
                "Resume-ClusterNode -Name $NodeName -Failback Immediate"
            )
            $methodLabel = 'DrainAndStorageMaintenance'
        }
        'DriveFault' {
            if ($Method -eq 'Retire') {
                $apply = @("Set-PhysicalDisk -SerialNumber $DiskSerialNumber -Usage Retired")
                $undo = @("Set-PhysicalDisk -SerialNumber $DiskSerialNumber -Usage <original usage, recorded in the lock>")
            }
            else {
                $apply = @("Disable-PnpDevice -InstanceId <PnP id of drive $DiskSerialNumber> -Confirm:`$false")
                $undo = @("Enable-PnpDevice -InstanceId <PnP id of drive $DiskSerialNumber> -Confirm:`$false")
            }
            $methodLabel = $Method
        }
    }

    $undoCommand = "Undo-FaultInjection -ComputerName $ComputerName -AllowFault -Confirm:`$false   # runs: " + ($undo -join '; ')
    [pscustomobject]@{
        FaultType        = $FaultType
        NodeName         = $NodeName
        Method           = $methodLabel
        DiskSerialNumber = $DiskSerialNumber
        PnpInstanceId    = ''
        OriginalUsage    = ''
        ComputerName     = $ComputerName
        ApplyCommands    = $apply
        UndoCommands     = $undo
        UndoCommand      = $undoCommand
        Executed         = $false
    }
}

function New-FaultCheck {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory result object only.')]
    [CmdletBinding()]
    param([string]$Name, [bool]$Passed, [string]$Detail)
    [pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail }
}

function Test-FaultPreflight {
    <#
    .SYNOPSIS
        Read-only: decides from a health snapshot whether the cluster can take ONE fault right now.
    .DESCRIPTION
        Refuses (Passed = $false) when: the snapshot is older than MaxSnapshotAgeSeconds; another fault is active;
        any node is not Up; fewer than two nodes; the storage pool or any virtual disk is not Healthy/OK; any
        physical disk is not OK; a CSV is not Online or is in maintenance; a storage job (repair) is running;
        a Major/Critical storage fault is reported; the witness is not Online; the pool free space is below the
        repair reserve (one capacity drive per node, at most four). NodePause also needs mirrored volumes and,
        on a two-node cluster, -AcceptReducedRedundancy (the paused node leaves one copy). DriveFault needs the
        named drive Healthy on the named node and at least two healthy data drives there.
    .PARAMETER Health
        Snapshot from Get-FaultHealthSnapshot.
    .PARAMETER Plan
        Plan from New-FaultPlan.
    .PARAMETER IgnoreLock
        Used by the undo path, which is allowed to run while its own lock exists.
    .PARAMETER AcceptReducedRedundancy
        Operator accepts running a two-node cluster on a single data copy for the duration of the test.
    .PARAMETER MaxSnapshotAgeSeconds
        A snapshot older than this is refused (default 120).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Health,
        [Parameter(Mandatory)][pscustomobject]$Plan,
        [switch]$IgnoreLock,
        [switch]$AcceptReducedRedundancy,
        [ValidateRange(1, 3600)][int]$MaxSnapshotAgeSeconds = 120
    )

    $checks = [System.Collections.Generic.List[pscustomobject]]::new()

    $collected = $null
    if ($Health.PSObject.Properties['CollectedAt']) { $collected = $Health.CollectedAt -as [datetime] }
    $age = if ($collected) { [math]::Round(((Get-Date).ToUniversalTime() - $collected.ToUniversalTime()).TotalSeconds) } else { [int]::MaxValue }
    $checks.Add((New-FaultCheck 'Health snapshot is fresh' ($age -ge -5 -and $age -le $MaxSnapshotAgeSeconds) $(if ($collected) { "$age s old" } else { 'no CollectedAt timestamp' })))

    $lock = if ($IgnoreLock) { $null } else { Get-FaultLock }
    $checks.Add((New-FaultCheck 'No other fault active' ($null -eq $lock) $(if ($lock) { "$($lock.fault_type) on $($lock.node) since $($lock.started_at) - run its undo first" } else { 'fault lock clean' })))

    $nodes = @($Health.Nodes)
    $target = @($nodes | Where-Object { $_.Name -eq $Plan.NodeName })
    $checks.Add((New-FaultCheck 'Target node exists' ($target.Count -eq 1) $Plan.NodeName))
    $down = @($nodes | Where-Object { $_.State -ne 'Up' })
    $checks.Add((New-FaultCheck 'All nodes Up (and at least two nodes)' ($down.Count -eq 0 -and $nodes.Count -ge 2) ((@($nodes | ForEach-Object { "$($_.Name)=$($_.State)" })) -join ', ')))

    $pool = $Health.Pool
    $poolOk = ($null -ne $pool -and $pool.HealthStatus -eq 'Healthy' -and $pool.OperationalStatus -eq 'OK')
    $checks.Add((New-FaultCheck 'Storage pool Healthy/OK' $poolOk $(if ($pool) { "$($pool.HealthStatus)/$($pool.OperationalStatus)" } else { 'no pool found' })))

    $vdisks = @($Health.VirtualDisks)
    $badV = @($vdisks | Where-Object { $_.HealthStatus -ne 'Healthy' -or $_.OperationalStatus -ne 'OK' })
    $checks.Add((New-FaultCheck 'All virtual disks Healthy/OK' ($badV.Count -eq 0 -and $vdisks.Count -gt 0) $(if ($badV.Count -eq 0) { "$($vdisks.Count) volume(s)" } else { (@($badV | ForEach-Object { "$($_.FriendlyName)=$($_.HealthStatus)/$($_.OperationalStatus)" }) -join ', ') })))

    $csvs = @($Health.Csvs)
    $badC = @($csvs | Where-Object { $_.State -ne 'Online' -or $_.MaintenanceMode })
    $checks.Add((New-FaultCheck 'All CSVs Online and not in maintenance' ($badC.Count -eq 0 -and $csvs.Count -gt 0) $(if ($badC.Count -eq 0) { "$($csvs.Count) CSV(s)" } else { (@($badC | ForEach-Object { "$($_.Name)=$($_.State)" }) -join ', ') })))

    $jobs = @($Health.StorageJobs)
    $checks.Add((New-FaultCheck 'No storage/repair job running' ($jobs.Count -eq 0) $(if ($jobs.Count -eq 0) { 'none' } else { (@($jobs | ForEach-Object { "$($_.Name) $($_.JobState) $($_.PercentComplete)%" }) -join ', ') })))

    $faults = @($Health.Faults | Where-Object { $_.Severity -in @('Major', 'Critical', 'Fatal') })
    $checks.Add((New-FaultCheck 'No Major/Critical storage fault reported' ($faults.Count -eq 0) $(if ($faults.Count -eq 0) { 'clean' } else { (@($faults | ForEach-Object { "$($_.Severity): $($_.FaultType)" }) -join '; ') })))

    $witnessOk = ($null -ne $Health.Quorum -and $Health.Quorum.WitnessState -eq 'Online')
    $checks.Add((New-FaultCheck 'Witness Online' $witnessOk $(if ($Health.Quorum) { "$($Health.Quorum.WitnessState)" } else { 'unknown' })))

    $allDisks = @($Health.PhysicalDisks)
    $badOp = @($allDisks | Where-Object { $_.HealthStatus -ne 'Healthy' -or ($_.PSObject.Properties['OperationalStatus'] -and $_.OperationalStatus -ne 'OK') })
    $checks.Add((New-FaultCheck 'Every physical disk Healthy/OK (none in maintenance, lost or retired)' ($badOp.Count -eq 0 -and $allDisks.Count -gt 0) "$($allDisks.Count - $badOp.Count)/$($allDisks.Count) healthy"))

    $reserveNeeded = [math]::Min($nodes.Count, 4) * [double]$Health.MaxCapacityDriveBytes
    $free = [double]$Health.PoolFreeBytes
    $checks.Add((New-FaultCheck 'Pool free space covers the repair reserve (one capacity drive per node, max 4)' ($reserveNeeded -gt 0 -and $free -ge $reserveNeeded) ('free {0:N0} GB, need {1:N0} GB' -f ($free / 1GB), ($reserveNeeded / 1GB))))

    switch ($Plan.FaultType) {
        'NodePause' {
            $mirrored = @($vdisks | Where-Object { $_.ResiliencySettingName -eq 'Mirror' })
            $checks.Add((New-FaultCheck 'Volumes are mirrored' ($mirrored.Count -eq $vdisks.Count -and $vdisks.Count -gt 0) "$($mirrored.Count)/$($vdisks.Count) Mirror"))
            $twoNode = ($nodes.Count -le 2)
            $checks.Add((New-FaultCheck 'Two-node pause leaves ONE data copy: operator accepted it (-AcceptReducedRedundancy)' ((-not $twoNode) -or [bool]$AcceptReducedRedundancy) $(if ($twoNode) { 'two-node cluster' } else { "$($nodes.Count) nodes" })))
        }
        'DriveFault' {
            $nodeDisks = @($allDisks | Where-Object { $_.Node -eq $Plan.NodeName -and $_.Usage -in @('Auto-Select', 'AutoSelect', 'Data') })
            $healthy = @($nodeDisks | Where-Object { $_.HealthStatus -eq 'Healthy' })
            $checks.Add((New-FaultCheck 'Target node has at least two healthy data drives, all healthy' ($healthy.Count -ge 2 -and $healthy.Count -eq $nodeDisks.Count) "$($healthy.Count)/$($nodeDisks.Count) healthy on $($Plan.NodeName)"))
            $named = @($nodeDisks | Where-Object { $_.SerialNumber -eq $Plan.DiskSerialNumber -and $_.HealthStatus -eq 'Healthy' })
            $checks.Add((New-FaultCheck 'Named drive exists on the target node, is a data drive and Healthy' ($named.Count -eq 1) "serial $($Plan.DiskSerialNumber)"))
            $mirrored = @($vdisks | Where-Object { $_.ResiliencySettingName -eq 'Mirror' })
            $checks.Add((New-FaultCheck 'Volumes are mirrored (one drive loss tolerated)' ($mirrored.Count -eq $vdisks.Count -and $vdisks.Count -gt 0) "$($mirrored.Count)/$($vdisks.Count) Mirror"))
        }
    }

    [pscustomobject]@{
        Passed = (@($checks | Where-Object { -not $_.Passed }).Count -eq 0)
        Checks = $checks.ToArray()
    }
}

function Get-FaultHealthSnapshot {
    <#
    .SYNOPSIS
        Collects the read-only health snapshot used by the preflight (remote, Get-/Debug- cmdlets only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [PSCredential]$Credential
    )
    Invoke-FaultRemote -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
        $nodes = @(Get-ClusterNode | ForEach-Object { [pscustomobject]@{ Name = $_.Name; State = "$($_.State)" } })
        $poolObj = Get-StoragePool -IsPrimordial $false | Select-Object -First 1
        $pool = if ($poolObj) { [pscustomobject]@{ FriendlyName = $poolObj.FriendlyName; HealthStatus = "$($poolObj.HealthStatus)"; OperationalStatus = "$($poolObj.OperationalStatus)" } }
        $free = if ($poolObj) { [double]($poolObj.Size - $poolObj.AllocatedSize) } else { 0 }
        $vdisks = @(Get-VirtualDisk | ForEach-Object { [pscustomobject]@{ FriendlyName = $_.FriendlyName; HealthStatus = "$($_.HealthStatus)"; OperationalStatus = "$($_.OperationalStatus)"; ResiliencySettingName = "$($_.ResiliencySettingName)" } })
        $csvs = @(Get-ClusterSharedVolume | ForEach-Object { [pscustomobject]@{ Name = $_.Name; State = "$($_.State)"; MaintenanceMode = [bool]$_.SharedVolumeInfo.MaintenanceMode } })
        $jobs = @(Get-StorageJob | Where-Object { $_.JobState -ne 'Completed' } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; JobState = "$($_.JobState)"; PercentComplete = $_.PercentComplete } })
        $faults = @(Get-StorageSubSystem -FriendlyName 'Clustered*' | Debug-StorageSubSystem | ForEach-Object { [pscustomobject]@{ Severity = "$($_.PerceivedSeverity)"; FaultType = "$($_.FaultType)" } })
        $maxCap = 0
        $disks = foreach ($sn in Get-StorageNode) {
            foreach ($pd in ($sn | Get-PhysicalDisk -PhysicallyConnected -ErrorAction SilentlyContinue)) {
                if ("$($pd.Usage)" -in @('Auto-Select', 'AutoSelect', 'Data') -and $pd.Size -gt $maxCap) { $maxCap = [double]$pd.Size }
                [pscustomobject]@{ Node = ($sn.Name -split '\.')[0]; FriendlyName = $pd.FriendlyName; SerialNumber = $pd.SerialNumber; HealthStatus = "$($pd.HealthStatus)"; OperationalStatus = "$($pd.OperationalStatus)"; Usage = "$($pd.Usage)"; MediaType = "$($pd.MediaType)" }
            }
        }
        $q = Get-ClusterQuorum
        $witness = if ($q.QuorumResource) { [pscustomobject]@{ WitnessName = $q.QuorumResource.Name; WitnessState = "$($q.QuorumResource.State)" } } else { [pscustomobject]@{ WitnessName = ''; WitnessState = 'None' } }
        [pscustomobject]@{
            CollectedAt = (Get-Date).ToUniversalTime().ToString('o'); Nodes = $nodes; Pool = $pool; PoolFreeBytes = $free; MaxCapacityDriveBytes = $maxCap
            VirtualDisks = $vdisks; Csvs = $csvs; StorageJobs = $jobs; Faults = $faults; PhysicalDisks = @($disks); Quorum = $witness
        }
    }
}

function Invoke-FaultInjection {
    <#
    .SYNOPSIS
        Applies ONE fault to the cluster. Opt-in only: needs -AllowFault and a confirmation.
    .DESCRIPTION
        Order of events: (1) print and return the UNDO command; (2) refuse without -AllowFault (plan only);
        (3) take a health snapshot and refuse when the preflight fails; (4) ShouldProcess confirmation
        (ConfirmImpact High); (5) re-collect the snapshot and re-check (not when a caller supplied -Health);
        (6) create the fault lock atomically; (7) apply; (8) record Applied. If the outcome of step 7 is
        unknown the lock is kept and the error names the undo command.
    .PARAMETER Plan
        From New-FaultPlan.
    .PARAMETER ComputerName
        Cluster or node to run the remote commands against.
    .PARAMETER AllowFault
        Explicit opt-in. Without it the function only prints what it would do and changes nothing.
    .PARAMETER AcceptReducedRedundancy
        Required for a NodePause on a two-node cluster (one data copy remains while paused).
    .PARAMETER Health
        A pre-collected snapshot (tests / reuse). It must be fresh; stale snapshots are refused.
    .PARAMETER DrainTimeoutMinutes
        NodePause: how long to wait for the drain to complete before giving up (the lock is kept).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan,
        [Parameter(Mandatory)][string]$ComputerName,
        [PSCredential]$Credential,
        [switch]$AllowFault,
        [switch]$AcceptReducedRedundancy,
        [object]$Health,
        [ValidateRange(1, 120)][int]$DrainTimeoutMinutes = 15
    )

    if ($ComputerName -notmatch $script:HostPattern) { throw "Invalid computer name '$ComputerName'." }
    # The undo command always names the real target.
    $Plan.ComputerName = $ComputerName
    $Plan.UndoCommand = $Plan.UndoCommand -replace '<cluster-name>', $ComputerName
    Write-Information "UNDO FIRST: $($Plan.UndoCommand)" -InformationAction Continue

    if (-not $AllowFault) {
        Write-Information ("PLAN ONLY (no -AllowFault): {0} on {1}: {2}" -f $Plan.FaultType, $Plan.NodeName, ($Plan.ApplyCommands -join '; ')) -InformationAction Continue
        return $Plan
    }

    $suppliedHealth = ($null -ne $Health)
    if (-not $suppliedHealth) { $Health = Get-FaultHealthSnapshot -ComputerName $ComputerName -Credential $Credential }
    $pre = Test-FaultPreflight -Health $Health -Plan $Plan -AcceptReducedRedundancy:$AcceptReducedRedundancy
    $Plan | Add-Member -NotePropertyName Preflight -NotePropertyValue $pre -Force
    if (-not $pre.Passed) {
        $why = (@($pre.Checks | Where-Object { -not $_.Passed } | ForEach-Object { "$($_.Name) [$($_.Detail)]" })) -join '; '
        throw "REFUSED: the cluster cannot take this fault right now: $why. Nothing was changed."
    }

    if (-not $PSCmdlet.ShouldProcess("$($Plan.NodeName) ($($Plan.FaultType))", ($Plan.ApplyCommands -join '; '))) {
        return $Plan
    }

    if (-not $suppliedHealth) {
        # The operator may have taken minutes to confirm: look again.
        $Health = Get-FaultHealthSnapshot -ComputerName $ComputerName -Credential $Credential
        $pre = Test-FaultPreflight -Health $Health -Plan $Plan -AcceptReducedRedundancy:$AcceptReducedRedundancy
        if (-not $pre.Passed) {
            $why = (@($pre.Checks | Where-Object { -not $_.Passed } | ForEach-Object { "$($_.Name) [$($_.Detail)]" })) -join '; '
            throw "REFUSED after confirmation: the cluster changed while waiting: $why. Nothing was changed."
        }
    }

    if ($Plan.FaultType -eq 'DriveFault') {
        $disk = @($Health.PhysicalDisks | Where-Object { $_.Node -eq $Plan.NodeName -and $_.SerialNumber -eq $Plan.DiskSerialNumber }) | Select-Object -First 1
        $usage = ([string]$disk.Usage) -replace '^Auto-Select$', 'AutoSelect'
        $Plan.OriginalUsage = if ($usage -in @('AutoSelect', 'ManualSelect', 'HotSpare')) { $usage } else { 'AutoSelect' }
    }

    Set-FaultLock -Plan $Plan -Status Pending -Confirm:$false
    try {
        $outcome = Invoke-FaultRemote -ComputerName $ComputerName -Credential $Credential -ArgumentList @($Plan.FaultType, $Plan.NodeName, $Plan.Method, $Plan.DiskSerialNumber, $DrainTimeoutMinutes) -ScriptBlock {
            param($FaultType, $Node, $How, $Serial, $DrainMinutes)
            $ErrorActionPreference = 'Stop'
            if ($FaultType -eq 'NodePause') {
                # No -Wait: it has no timeout. Start the drain, then poll against a deadline.
                Suspend-ClusterNode -Name $Node -Drain | Out-Null
                $deadline = (Get-Date).AddMinutes($DrainMinutes)
                do {
                    $n = Get-ClusterNode -Name $Node
                    $done = ("$($n.State)" -eq 'Paused' -and "$($n.DrainStatus)" -eq 'Completed')
                    if (-not $done) { Start-Sleep -Seconds 10 }
                } while (-not $done -and (Get-Date) -lt $deadline)
                if (-not $done) { throw "Drain of $Node did not complete within $DrainMinutes minutes (state $($n.State), drain $($n.DrainStatus)). Storage maintenance mode was NOT entered." }
                $su = Get-StorageFaultDomain -Type StorageScaleUnit | Where-Object FriendlyName -Eq $Node
                $su | Enable-StorageMaintenanceMode
                $su = Get-StorageFaultDomain -Type StorageScaleUnit | Where-Object FriendlyName -Eq $Node
                if (-not (@($su.OperationalStatus) -contains 'In Maintenance Mode')) { throw "Storage maintenance mode for $Node is not reported after enabling it." }
                return [pscustomobject]@{ Applied = $true; Reason = ''; PnpInstanceId = '' }
            }
            $pd = Get-PhysicalDisk -SerialNumber $Serial
            if (@($pd).Count -ne 1) { throw "Drive serial '$Serial' matched $(@($pd).Count) physical disks." }
            if ($How -eq 'Retire') {
                Set-PhysicalDisk -InputObject $pd -Usage Retired
                return [pscustomobject]@{ Applied = $true; Reason = ''; PnpInstanceId = '' }
            }
            $all = @(Get-PnpDevice -Class DiskDrive -PresentOnly)
            $pnp = @($all | Where-Object { $_.InstanceId -like "*$Serial*" })
            if ($pnp.Count -ne 1) {
                return [pscustomobject]@{ Applied = $false; Reason = "Could not map drive serial '$Serial' to exactly one PnP device ($($pnp.Count) matches). Use -Method Retire."; PnpInstanceId = '' }
            }
            Disable-PnpDevice -InstanceId $pnp[0].InstanceId -Confirm:$false
            [pscustomobject]@{ Applied = $true; Reason = ''; PnpInstanceId = $pnp[0].InstanceId }
        }
    }
    catch {
        throw ("The fault outcome is UNKNOWN ({0}). The fault lock is KEPT. Check the cluster, then run: {1}" -f (($_.Exception.Message -replace '\s+', ' ')), $Plan.UndoCommand)
    }

    if (-not $outcome.Applied) {
        Remove-FaultLock -Confirm:$false
        throw "REFUSED: $($outcome.Reason) Nothing was changed."
    }

    $Plan.PnpInstanceId = [string]$outcome.PnpInstanceId
    Set-FaultLock -Plan $Plan -Status Applied -Confirm:$false
    $Plan.Executed = $true
    Write-Information "Fault applied. Undo: $($Plan.UndoCommand)" -InformationAction Continue
    $Plan
}

function Undo-FaultInjection {
    <#
    .SYNOPSIS
        Reverses the active fault, waits for the repair, and clears the lock only after the cluster stayed Healthy.
    .DESCRIPTION
        Refuses when the lock was written for a different ComputerName. After the reversal it polls the health
        snapshot every PollSeconds; the lock is cleared only after SettleObservations consecutive healthy polls
        (no storage job, all virtual disks Healthy/OK, all nodes Up, no CSV in maintenance). A poll that sees any
        job or unhealthy state resets the count, because repair jobs start asynchronously after the reversal.
    .PARAMETER ComputerName
        Cluster or node to run the remote commands against (must match the lock).
    .PARAMETER AllowFault
        Required, same opt-in as the injection (undo changes the cluster too).
    .PARAMETER ResyncTimeoutMinutes
        How long to wait for the cluster to settle (0 = check once).
    .PARAMETER PollSeconds
        Polling interval.
    .PARAMETER SettleObservations
        Consecutive healthy polls required (default 3).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [PSCredential]$Credential,
        [switch]$AllowFault,
        [ValidateRange(0, 600)][double]$ResyncTimeoutMinutes = 30,
        [ValidateRange(1, 300)][int]$PollSeconds = 15,
        [ValidateRange(1, 20)][int]$SettleObservations = 3
    )

    $lock = Get-FaultLock
    if ($null -eq $lock) {
        Write-Information 'No fault lock: nothing to undo.' -InformationAction Continue
        return [pscustomobject]@{ Undone = $false; Reason = 'NoLock'; Healthy = $null }
    }
    if (-not $AllowFault) {
        Write-Information "PLAN ONLY (no -AllowFault): would undo $($lock.fault_type) on $($lock.node)." -InformationAction Continue
        return [pscustomobject]@{ Undone = $false; Reason = 'PlanOnly'; Healthy = $null }
    }
    if ($lock.node -notmatch $script:NamePattern) { throw 'The fault lock holds an invalid node name; refusing to continue. Inspect state/fault-lock.json.' }
    if ($lock.serial_number -and $lock.serial_number -notmatch $script:SerialPattern) { throw 'The fault lock holds an invalid drive serial; refusing to continue.' }
    if ($lock.computer_name -and $lock.computer_name -ne $ComputerName) { throw "REFUSED: the fault lock was written for '$($lock.computer_name)', not '$ComputerName'. Undo it against the same target." }

    if (-not $PSCmdlet.ShouldProcess("$($lock.node) ($($lock.fault_type))", 'Undo fault injection')) {
        return [pscustomobject]@{ Undone = $false; Reason = 'NotConfirmed'; Healthy = $null }
    }

    $plan = [pscustomobject]@{
        FaultType = $lock.fault_type; NodeName = $lock.node; Method = $lock.method
        DiskSerialNumber = $lock.serial_number; PnpInstanceId = $lock.pnp_instance; OriginalUsage = $lock.original_usage
        ComputerName = $lock.computer_name; UndoCommand = $lock.undo_command
    }
    Set-FaultLock -Plan $plan -Status Undoing -Confirm:$false

    $usage = if ($lock.original_usage) { [string]$lock.original_usage } else { 'AutoSelect' }
    Invoke-FaultRemote -ComputerName $ComputerName -Credential $Credential -ArgumentList @($lock.fault_type, $lock.node, $lock.method, $lock.serial_number, $lock.pnp_instance, $usage) -ScriptBlock {
        param($FaultType, $Node, $How, $Serial, $PnpId, $Usage)
        $ErrorActionPreference = 'Stop'
        if ($FaultType -eq 'NodePause') {
            Get-StorageFaultDomain -Type StorageScaleUnit | Where-Object FriendlyName -Eq $Node | Disable-StorageMaintenanceMode
            if ("$((Get-ClusterNode -Name $Node).State)" -eq 'Paused') { Resume-ClusterNode -Name $Node -Failback Immediate | Out-Null }
            return
        }
        if ($How -eq 'Retire') {
            Set-PhysicalDisk -InputObject (Get-PhysicalDisk -SerialNumber $Serial) -Usage $Usage
            return
        }
        if (-not $PnpId) {
            $PnpId = (@(Get-PnpDevice -Class DiskDrive | Where-Object { $_.InstanceId -like "*$Serial*" }) | Select-Object -First 1).InstanceId
        }
        Enable-PnpDevice -InstanceId $PnpId -Confirm:$false
    } | Out-Null

    $deadline = (Get-Date).AddMinutes($ResyncTimeoutMinutes)
    $streak = 0
    do {
        $h = Get-FaultHealthSnapshot -ComputerName $ComputerName -Credential $Credential
        $busy = @($h.StorageJobs).Count -gt 0
        $badV = @(@($h.VirtualDisks) | Where-Object { $_.HealthStatus -ne 'Healthy' -or $_.OperationalStatus -ne 'OK' })
        $nodesUp = @(@($h.Nodes) | Where-Object { $_.State -ne 'Up' }).Count -eq 0
        $csvOk = @(@($h.Csvs) | Where-Object { $_.State -ne 'Online' -or $_.MaintenanceMode }).Count -eq 0
        if ((-not $busy) -and ($badV.Count -eq 0) -and $nodesUp -and $csvOk) { $streak++ } else { $streak = 0 }
        if ($streak -lt $SettleObservations -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds $PollSeconds }
    } while ($streak -lt $SettleObservations -and (Get-Date) -lt $deadline)

    $healthy = ($streak -ge $SettleObservations)
    if ($healthy) {
        Remove-FaultLock -Confirm:$false
    }
    else {
        Write-Warning 'Undo ran but the cluster has not settled (a repair is running or volumes are not Healthy). The fault lock is KEPT; re-run the undo to wait again.'
    }
    [pscustomobject]@{ Undone = $healthy; Reason = $(if ($healthy) { 'Healthy' } else { 'RepairNotFinished' }); Healthy = $healthy }
}

Export-ModuleMember -Function @(
    'Get-FaultLock'
    'New-FaultPlan'
    'Test-FaultPreflight'
    'Get-FaultHealthSnapshot'
    'Invoke-FaultInjection'
    'Undo-FaultInjection'
)
