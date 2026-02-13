# =============================================================================
# StateManager Module - Azure Local Load Tools
# =============================================================================
# Manages run state tracking, checkpoints, and resume capability.
# Uses file-level locking and atomic writes for reliability.
# =============================================================================

# Module-level variables
$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$script:StateDir = Join-Path $script:ProjectRoot 'state'
$script:HistoryDir = Join-Path $script:StateDir 'history'

function New-RunState {
    <#
    .SYNOPSIS
        Creates a new run state file for tracking automation progress.
    .PARAMETER RunId
        Unique identifier for this run. Auto-generated if not provided.
    .PARAMETER Solution
        The solution being executed (e.g., "vmfleet").
    .PARAMETER Phases
        Ordered list of phase names to track.
    .PARAMETER Metadata
        Additional metadata to store with the run state.
    .OUTPUTS
        PSCustomObject representing the new run state.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RunId = "run-$(Get-Date -Format 'yyyy-MM-dd')-$(New-Guid | Select-Object -ExpandProperty Guid | ForEach-Object { $_.Substring(0, 6) })",

        [Parameter(Mandatory)]
        [string]$Solution,

        [Parameter(Mandatory)]
        [string[]]$Phases,

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    # Ensure state directories exist
    foreach ($dir in @($script:StateDir, $script:HistoryDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Archive existing state if present
    $stateFilePath = Join-Path $script:StateDir 'run-state.json'
    if (Test-Path $stateFilePath) {
        $existingState = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json
        if ($existingState.status -ne 'completed' -and $existingState.status -ne 'cancelled') {
            Write-Warning "Archiving incomplete previous run: $($existingState.run_id)"
        }
        $archivePath = Join-Path $script:HistoryDir "$($existingState.run_id).json"
        Move-Item -Path $stateFilePath -Destination $archivePath -Force
    }

    # Build phase tracking
    $phaseStates = [ordered]@{}
    foreach ($phase in $Phases) {
        $phaseStates[$phase] = [ordered]@{
            status       = 'pending'
            started_at   = $null
            completed_at = $null
            duration_seconds = $null
            details      = @{}
            error        = $null
        }
    }

    # Build state object
    $state = [ordered]@{
        run_id       = $RunId
        solution     = $Solution
        status       = 'created'
        created_at   = (Get-Date -Format 'o')
        started_at   = $null
        completed_at = $null
        phases       = $phaseStates
        metadata     = $Metadata
        results_dir  = "results/$RunId/"
    }

    # Atomic write (write to temp, then rename)
    $tempPath = "$stateFilePath.tmp"
    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding UTF8
    Move-Item -Path $tempPath -Destination $stateFilePath -Force

    Write-Verbose "Created run state: $RunId with $($Phases.Count) phases"
    return [PSCustomObject]$state
}

function Get-RunState {
    <#
    .SYNOPSIS
        Reads the current run state.
    .PARAMETER RunId
        Optional specific run ID to retrieve from history. If omitted, returns current state.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RunId
    )

    if ($RunId) {
        # Look in history
        $historyPath = Join-Path $script:HistoryDir "$RunId.json"
        if (Test-Path $historyPath) {
            return Get-Content -Path $historyPath -Raw | ConvertFrom-Json
        }
    }

    $stateFilePath = Join-Path $script:StateDir 'run-state.json'
    if (-not (Test-Path $stateFilePath)) {
        return $null
    }

    return Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json
}

function Update-RunPhase {
    <#
    .SYNOPSIS
        Updates the status of a specific phase in the run state.
    .PARAMETER Phase
        Name of the phase to update.
    .PARAMETER Status
        New status: pending, running, completed, failed, skipped.
    .PARAMETER Details
        Additional details to record with the phase update.
    .PARAMETER ErrorMessage
        Error message if the phase failed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Phase,

        [Parameter(Mandatory)]
        [ValidateSet('pending', 'running', 'completed', 'failed', 'skipped')]
        [string]$Status,

        [Parameter()]
        [hashtable]$Details = @{},

        [Parameter()]
        [string]$ErrorMessage
    )

    $stateFilePath = Join-Path $script:StateDir 'run-state.json'
    if (-not (Test-Path $stateFilePath)) {
        throw "No active run state found. Call New-RunState first."
    }

    # Use a mutex for file-level locking
    $mutexName = 'Global\AzureLocalLoadTools-StateManager'
    $mutex = [System.Threading.Mutex]::new($false, $mutexName)

    try {
        $mutex.WaitOne(30000) | Out-Null  # 30-second timeout

        $state = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json -AsHashtable

        if (-not $state.phases.ContainsKey($Phase)) {
            throw "Phase '$Phase' not found in run state"
        }

        $now = Get-Date -Format 'o'

        # Update phase
        $state.phases[$Phase].status = $Status

        switch ($Status) {
            'running' {
                $state.phases[$Phase].started_at = $now
                $state.status = 'in_progress'
                if (-not $state.started_at) {
                    $state.started_at = $now
                }
            }
            'completed' {
                $state.phases[$Phase].completed_at = $now
                if ($state.phases[$Phase].started_at) {
                    $startTime = [datetime]$state.phases[$Phase].started_at
                    $state.phases[$Phase].duration_seconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
                }
            }
            'failed' {
                $state.phases[$Phase].completed_at = $now
                $state.phases[$Phase].error = ($ErrorMessage ?? 'Unknown error')
                $state.status = 'failed'
                if ($state.phases[$Phase].started_at) {
                    $startTime = [datetime]$state.phases[$Phase].started_at
                    $state.phases[$Phase].duration_seconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
                }
            }
        }

        if ($Details.Count -gt 0) {
            $state.phases[$Phase].details = $Details
        }

        # Check if all phases completed
        $allCompleted = $state.phases.Values | Where-Object { $_.status -notin @('completed', 'skipped') }
        if ($allCompleted.Count -eq 0) {
            $state.status = 'completed'
            $state.completed_at = $now
        }

        # Atomic write
        $tempPath = "$stateFilePath.tmp"
        $state | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding UTF8
        Move-Item -Path $tempPath -Destination $stateFilePath -Force
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }

    Write-Verbose "Phase '$Phase' updated to: $Status"
}

function Test-PhaseCompleted {
    <#
    .SYNOPSIS
        Checks if a phase has already completed (for resume support).
    .PARAMETER Phase
        Name of the phase to check.
    .OUTPUTS
        Boolean - True if the phase is completed or skipped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Phase
    )

    $state = Get-RunState
    if (-not $state) { return $false }

    $phaseState = $state.phases.$Phase
    if (-not $phaseState) { return $false }

    return $phaseState.status -in @('completed', 'skipped')
}

function Complete-Run {
    <#
    .SYNOPSIS
        Marks the current run as completed and archives the state.
    .PARAMETER Status
        Final status: completed, failed, cancelled.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('completed', 'failed', 'cancelled')]
        [string]$Status = 'completed'
    )

    $stateFilePath = Join-Path $script:StateDir 'run-state.json'
    if (-not (Test-Path $stateFilePath)) {
        Write-Warning "No active run state to complete"
        return
    }

    $state = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json -AsHashtable
    $state.status = $Status
    $state.completed_at = (Get-Date -Format 'o')

    # Write final state
    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFilePath -Encoding UTF8

    # Archive
    $archivePath = Join-Path $script:HistoryDir "$($state.run_id).json"
    Copy-Item -Path $stateFilePath -Destination $archivePath -Force

    Write-Verbose "Run $($state.run_id) marked as: $Status"
}

# Export module members
Export-ModuleMember -Function @(
    'New-RunState'
    'Get-RunState'
    'Update-RunPhase'
    'Test-PhaseCompleted'
    'Complete-Run'
)
