# =============================================================================
# FaultInjection.Tests.ps1 - Pester unit tests (mocks only, nothing touches a cluster)
# =============================================================================

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\..\common\modules\FaultInjection\FaultInjection.psm1'
    Import-Module $script:ModulePath -Force
    $script:Target = 'clu01'
    $script:Other = 'other01'
    $script:BadHost = 'clu01; calc'

    function script:New-Health {
        param([hashtable]$Override = @{})
        $h = @{
            CollectedAt   = (Get-Date).ToUniversalTime().ToString('o')
            PoolFreeBytes = 4TB
            MaxCapacityDriveBytes = 1TB
            Csvs          = @([pscustomobject]@{ Name = 'csv1'; State = 'Online'; MaintenanceMode = $false })
            Nodes         = @(
                [pscustomobject]@{ Name = 'node1'; State = 'Up' }
                [pscustomobject]@{ Name = 'node2'; State = 'Up' }
            )
            Pool          = [pscustomobject]@{ FriendlyName = 'pool'; HealthStatus = 'Healthy'; OperationalStatus = 'OK' }
            VirtualDisks  = @(
                [pscustomobject]@{ FriendlyName = 'vol1'; HealthStatus = 'Healthy'; OperationalStatus = 'OK'; ResiliencySettingName = 'Mirror' }
            )
            StorageJobs   = @()
            Faults        = @()
            PhysicalDisks = @(
                [pscustomobject]@{ Node = 'node1'; FriendlyName = 'd1'; SerialNumber = 'SER1'; HealthStatus = 'Healthy'; Usage = 'Auto-Select'; OperationalStatus = 'OK' }
                [pscustomobject]@{ Node = 'node1'; FriendlyName = 'd2'; SerialNumber = 'SER2'; HealthStatus = 'Healthy'; Usage = 'Auto-Select'; OperationalStatus = 'OK' }
                [pscustomobject]@{ Node = 'node2'; FriendlyName = 'd3'; SerialNumber = 'SER3'; HealthStatus = 'Healthy'; Usage = 'Auto-Select'; OperationalStatus = 'OK' }
                [pscustomobject]@{ Node = 'node2'; FriendlyName = 'd4'; SerialNumber = 'SER4'; HealthStatus = 'Healthy'; Usage = 'Auto-Select'; OperationalStatus = 'OK' }
            )
            Quorum        = [pscustomobject]@{ WitnessName = 'w'; WitnessState = 'Online' }
        }
        foreach ($k in $Override.Keys) { $h[$k] = $Override[$k] }
        [pscustomobject]$h
    }
}

Describe 'FaultInjection' {
    BeforeEach {
        InModuleScope FaultInjection -Parameters @{ Lock = (Join-Path $TestDrive ([guid]::NewGuid().ToString() + '\fault-lock.json')) } {
            param($Lock)
            $script:LockPath = $Lock
        }
        Mock Invoke-FaultRemote -ModuleName FaultInjection { [pscustomobject]@{ Applied = $true; Reason = ''; PnpInstanceId = '' } }
    }

    Context 'New-FaultPlan' {
        It 'builds drain + maintenance commands and prints the undo first' {
            $p = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            $p.ApplyCommands[0] | Should -Match '^Suspend-ClusterNode -Name node1 -Drain'
            $p.UndoCommands[-1] | Should -Match 'Resume-ClusterNode -Name node1 -Failback Immediate'
            $p.UndoCommand | Should -Match 'Undo-FaultInjection'
            $p.Executed | Should -BeFalse
        }
        It 'defaults a drive fault to the reversible Retire method' {
            $p = New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER1'
            $p.Method | Should -Be 'Retire'
            $p.ApplyCommands[0] | Should -Match 'Usage Retired'
            $p.UndoCommands[0] | Should -Match 'original usage'
        }
        It 'refuses to pick a drive on its own' {
            { New-FaultPlan -FaultType DriveFault -NodeName 'node1' } | Should -Throw '*DiskSerialNumber*'
        }
        It 'rejects injection characters in the node name and serial' {
            { New-FaultPlan -FaultType NodePause -NodeName 'node1; Remove-Item C:\' } | Should -Throw '*Invalid node name*'
            { New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'x"; calc' } | Should -Throw '*Invalid drive serial*'
        }
        It 'rejects a serial on a node pause' {
            { New-FaultPlan -FaultType NodePause -NodeName 'node1' -DiskSerialNumber 'SER1' } | Should -Throw
        }
    }

    Context 'Test-FaultPreflight' {
        It 'passes on a healthy two-node cluster (node pause)' {
            $r = Test-FaultPreflight -Health (New-Health) -Plan (New-FaultPlan -FaultType NodePause -NodeName 'node1') -AcceptReducedRedundancy
            $r.Passed | Should -BeTrue
        }
        It 'passes on a healthy cluster (drive fault)' {
            $r = Test-FaultPreflight -Health (New-Health) -Plan (New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER1')
            $r.Passed | Should -BeTrue
        }
        It 'refuses: <Name>' -ForEach @(
            @{ Name = 'a node is down'; Override = @{ Nodes = @([pscustomobject]@{ Name = 'node1'; State = 'Up' }, [pscustomobject]@{ Name = 'node2'; State = 'Down' }) } }
            @{ Name = 'single node'; Override = @{ Nodes = @([pscustomobject]@{ Name = 'node1'; State = 'Up' }) } }
            @{ Name = 'a repair job is running'; Override = @{ StorageJobs = @([pscustomobject]@{ Name = 'Repair'; JobState = 'Running'; PercentComplete = 10 }) } }
            @{ Name = 'a volume is degraded'; Override = @{ VirtualDisks = @([pscustomobject]@{ FriendlyName = 'v'; HealthStatus = 'Warning'; OperationalStatus = 'Degraded'; ResiliencySettingName = 'Mirror' }) } }
            @{ Name = 'the pool is unhealthy'; Override = @{ Pool = [pscustomobject]@{ FriendlyName = 'p'; HealthStatus = 'Warning'; OperationalStatus = 'Degraded' } } }
            @{ Name = 'the witness is offline'; Override = @{ Quorum = [pscustomobject]@{ WitnessName = 'w'; WitnessState = 'Offline' } } }
            @{ Name = 'a critical storage fault exists'; Override = @{ Faults = @([pscustomobject]@{ Severity = 'Critical'; FaultType = 'Disk' }) } }
            @{ Name = 'volumes are not mirrored'; Override = @{ VirtualDisks = @([pscustomobject]@{ FriendlyName = 'v'; HealthStatus = 'Healthy'; OperationalStatus = 'OK'; ResiliencySettingName = 'Simple' }) } }
            @{ Name = 'there is no pool'; Override = @{ Pool = $null } }
        ) {
            $r = Test-FaultPreflight -Health (New-Health -Override $Override) -Plan (New-FaultPlan -FaultType NodePause -NodeName 'node1') -AcceptReducedRedundancy
            $r.Passed | Should -BeFalse
        }
        It 'refuses a drive fault when the named drive is not on the node' {
            $r = Test-FaultPreflight -Health (New-Health) -Plan (New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER3')
            $r.Passed | Should -BeFalse
        }
        It 'refuses a drive fault when the node would be left with one drive' {
            $h = New-Health -Override @{ PhysicalDisks = @([pscustomobject]@{ Node = 'node1'; FriendlyName = 'd1'; SerialNumber = 'SER1'; HealthStatus = 'Healthy'; Usage = 'Auto-Select'; OperationalStatus = 'OK' }) }
            (Test-FaultPreflight -Health $h -Plan (New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER1')).Passed | Should -BeFalse
        }
        It 'refuses a stale snapshot' {
            $old = New-Health -Override @{ CollectedAt = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o') }
            (Test-FaultPreflight -Health $old -Plan (New-FaultPlan -FaultType NodePause -NodeName 'node1') -AcceptReducedRedundancy).Passed | Should -BeFalse
        }
        It 'refuses a snapshot without a timestamp' {
            $h = New-Health
            $h.PSObject.Properties.Remove('CollectedAt')
            (Test-FaultPreflight -Health $h -Plan (New-FaultPlan -FaultType NodePause -NodeName 'node1') -AcceptReducedRedundancy).Passed | Should -BeFalse
        }
        It 'refuses when a CSV is not Online' {
            $h = New-Health -Override @{ Csvs = @([pscustomobject]@{ Name = 'csv1'; State = 'Failed'; MaintenanceMode = $false }) }
            (Test-FaultPreflight -Health $h -Plan (New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER1')).Passed | Should -BeFalse
        }
        It 'refuses when the pool has no repair reserve' {
            $h = New-Health -Override @{ PoolFreeBytes = 1TB }
            (Test-FaultPreflight -Health $h -Plan (New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER1')).Passed | Should -BeFalse
        }
        It 'refuses a disk that is in maintenance mode' {
            $h = New-Health
            $h.PhysicalDisks[2].OperationalStatus = 'In Maintenance Mode'
            (Test-FaultPreflight -Health $h -Plan (New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER1')).Passed | Should -BeFalse
        }
        It 'refuses a two-node node pause unless reduced redundancy is accepted' {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            (Test-FaultPreflight -Health (New-Health) -Plan $plan).Passed | Should -BeFalse
            (Test-FaultPreflight -Health (New-Health) -Plan $plan -AcceptReducedRedundancy).Passed | Should -BeTrue
        }
        It 'refuses a second fault while the lock exists' {
            InModuleScope FaultInjection { New-Item -ItemType Directory -Path (Split-Path $script:LockPath) -Force | Out-Null; '{"fault_type":"NodePause","node":"node2","status":"Applied","started_at":"x"}' | Set-Content $script:LockPath }
            $r = Test-FaultPreflight -Health (New-Health) -Plan (New-FaultPlan -FaultType NodePause -NodeName 'node1')
            $r.Passed | Should -BeFalse
            (Test-FaultPreflight -Health (New-Health) -Plan (New-FaultPlan -FaultType NodePause -NodeName 'node1') -AcceptReducedRedundancy -IgnoreLock).Passed | Should -BeTrue
        }
    }

    Context 'Invoke-FaultInjection' {
        It 'does nothing without -AllowFault, but still prints the undo first' {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            $info = Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -Health (New-Health) 6>&1
            ($info | Out-String) | Should -Match 'UNDO FIRST'
            ($info | Out-String) | Should -Match 'PLAN ONLY'
            Should -Invoke Invoke-FaultRemote -ModuleName FaultInjection -Times 0
            Get-FaultLock | Should -BeNullOrEmpty
        }
        It 'refuses and changes nothing when the cluster is unhealthy' {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            $bad = New-Health -Override @{ StorageJobs = @([pscustomobject]@{ Name = 'Repair'; JobState = 'Running'; PercentComplete = 5 }) }
            { Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -Confirm:$false -Health $bad } | Should -Throw 'REFUSED*'
            Should -Invoke Invoke-FaultRemote -ModuleName FaultInjection -Times 0
            Get-FaultLock | Should -BeNullOrEmpty
        }
        It 'applies once, with the lock Applied, when allowed and healthy' {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            $r = Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -Confirm:$false -Health (New-Health)
            $r.Executed | Should -BeTrue
            Should -Invoke Invoke-FaultRemote -ModuleName FaultInjection -Times 1 -Exactly
            (Get-FaultLock).status | Should -Be 'Applied'
            (Get-FaultLock).undo_command | Should -Match 'clu01'
        }
        It 'does not apply under -WhatIf' {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -WhatIf -Health (New-Health) | Out-Null
            Should -Invoke Invoke-FaultRemote -ModuleName FaultInjection -Times 0
            Get-FaultLock | Should -BeNullOrEmpty
        }
        It 'keeps the lock and names the undo when the outcome is unknown' {
            Mock Invoke-FaultRemote -ModuleName FaultInjection { throw 'WinRM timeout' }
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            { Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -Confirm:$false -Health (New-Health) } | Should -Throw '*UNKNOWN*Undo-FaultInjection*'
            (Get-FaultLock).status | Should -Be 'Pending'
        }
        It 'releases the lock when the remote side reports nothing was changed' {
            Mock Invoke-FaultRemote -ModuleName FaultInjection { [pscustomobject]@{ Applied = $false; Reason = 'no unique PnP match'; PnpInstanceId = '' } }
            $plan = New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER1' -Method PnpDisable
            { Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -Confirm:$false -Health (New-Health) } | Should -Throw '*Nothing was changed*'
            Get-FaultLock | Should -BeNullOrEmpty
        }
        It 'creates the lock atomically: a second Pending lock is refused' {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            InModuleScope FaultInjection -Parameters @{ P = $plan } {
                param($P)
                Set-FaultLock -Plan $P -Status Pending -Confirm:$false
                { Set-FaultLock -Plan $P -Status Pending -Confirm:$false } | Should -Throw '*already exists*'
            }
        }
        It 'records the original drive usage and restores it on undo' {
            Mock Get-FaultHealthSnapshot -ModuleName FaultInjection { New-Health }
            Mock Start-Sleep -ModuleName FaultInjection {}
            $h = New-Health
            $plan = New-FaultPlan -FaultType DriveFault -NodeName 'node1' -DiskSerialNumber 'SER1'
            Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -Confirm:$false -Health $h | Out-Null
            (Get-FaultLock).original_usage | Should -Be 'AutoSelect'
            Undo-FaultInjection -ComputerName $script:Target -AllowFault -Confirm:$false -ResyncTimeoutMinutes 0 -SettleObservations 1 | Out-Null
            Should -Invoke Invoke-FaultRemote -ModuleName FaultInjection -ParameterFilter { $ArgumentList -contains 'AutoSelect' } -Times 1
        }
        It 're-collects the snapshot after the confirmation and refuses if the cluster changed' {
            $script:calls = 0
            Mock Get-FaultHealthSnapshot -ModuleName FaultInjection {
                $script:calls++
                if ($script:calls -eq 1) { New-Health } else { New-Health -Override @{ StorageJobs = @([pscustomobject]@{ Name = 'Repair'; JobState = 'Running'; PercentComplete = 1 }) } }
            }
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            { Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -Confirm:$false } | Should -Throw 'REFUSED after confirmation*'
            Should -Invoke Invoke-FaultRemote -ModuleName FaultInjection -Times 0
            Get-FaultLock | Should -BeNullOrEmpty
        }
        It 'rejects an invalid computer name' {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            { Invoke-FaultInjection -Plan $plan -ComputerName $script:BadHost -AllowFault -Health (New-Health) } | Should -Throw '*Invalid computer name*'
        }
        It 'refuses a second fault while one is active' {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -Confirm:$false -Health (New-Health) | Out-Null
            $second = New-FaultPlan -FaultType NodePause -NodeName 'node2'
            { Invoke-FaultInjection -Plan $second -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -Confirm:$false -Health (New-Health) } | Should -Throw 'REFUSED*'
            Should -Invoke Invoke-FaultRemote -ModuleName FaultInjection -Times 1 -Exactly
        }
    }

    Context 'Undo-FaultInjection' {
        BeforeEach {
            $plan = New-FaultPlan -FaultType NodePause -NodeName 'node1'
            Invoke-FaultInjection -Plan $plan -ComputerName $script:Target -AllowFault -AcceptReducedRedundancy -Confirm:$false -Health (New-Health) | Out-Null
            Mock Get-FaultHealthSnapshot -ModuleName FaultInjection { New-Health }
            Mock Start-Sleep -ModuleName FaultInjection {}
        }
        It 'reports nothing to undo when there is no lock' {
            InModuleScope FaultInjection { Remove-Item $script:LockPath -Force }
            (Undo-FaultInjection -ComputerName $script:Target -AllowFault -Confirm:$false).Reason | Should -Be 'NoLock'
        }
        It 'changes nothing without -AllowFault' {
            (Undo-FaultInjection -ComputerName $script:Target).Reason | Should -Be 'PlanOnly'
            Should -Invoke Invoke-FaultRemote -ModuleName FaultInjection -Times 1 -Exactly   # only the injection call
        }
        It 'undoes and clears the lock once volumes are Healthy' {
            $r = Undo-FaultInjection -ComputerName $script:Target -AllowFault -Confirm:$false -ResyncTimeoutMinutes 0 -SettleObservations 1
            $r.Undone | Should -BeTrue
            Get-FaultLock | Should -BeNullOrEmpty
        }
        It 'keeps the lock while a repair job is still running' {
            Mock Get-FaultHealthSnapshot -ModuleName FaultInjection { New-Health -Override @{ StorageJobs = @([pscustomobject]@{ Name = 'Repair'; JobState = 'Running'; PercentComplete = 40 }) } }
            $r = Undo-FaultInjection -ComputerName $script:Target -AllowFault -Confirm:$false -ResyncTimeoutMinutes 0 -SettleObservations 1 -WarningAction SilentlyContinue
            $r.Undone | Should -BeFalse
            Get-FaultLock | Should -Not -BeNullOrEmpty
        }
        It 'refuses to undo against a different target than the lock' {
            { Undo-FaultInjection -ComputerName $script:Other -AllowFault -Confirm:$false } | Should -Throw '*not*other01*'
        }
        It 'needs several consecutive healthy polls before clearing the lock' {
            $script:n = 0
            Mock Get-FaultHealthSnapshot -ModuleName FaultInjection {
                $script:n++
                if ($script:n -eq 2) { New-Health -Override @{ StorageJobs = @([pscustomobject]@{ Name = 'Repair'; JobState = 'Running'; PercentComplete = 3 }) } } else { New-Health }
            }
            $r = Undo-FaultInjection -ComputerName $script:Target -AllowFault -Confirm:$false -ResyncTimeoutMinutes 1 -PollSeconds 1 -SettleObservations 3
            $r.Undone | Should -BeTrue
            $script:n | Should -BeGreaterOrEqual 5
        }
        It 'refuses a tampered lock with an invalid node name' {
            InModuleScope FaultInjection { '{"fault_type":"NodePause","node":"n1; calc","status":"Applied","started_at":"x"}' | Set-Content $script:LockPath }
            { Undo-FaultInjection -ComputerName $script:Target -AllowFault -Confirm:$false } | Should -Throw '*invalid node name*'
        }
    }
}
