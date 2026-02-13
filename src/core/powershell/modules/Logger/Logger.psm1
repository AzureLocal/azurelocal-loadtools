# =============================================================================
# Logger Module - Azure Local Load Tools
# =============================================================================
# Provides structured JSON-lines logging with correlation IDs, severity levels,
# and per-component log file separation.
# =============================================================================

# Module-level variables
$script:ActiveSessions = @{}
$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$script:DefaultLogLevel = 'INFO'
$script:LogLevels = @{
    'DEBUG'    = 0
    'INFO'     = 1
    'WARNING'  = 2
    'ERROR'    = 3
    'CRITICAL' = 4
}

function Start-LogSession {
    <#
    .SYNOPSIS
        Starts a new logging session with a correlation ID.
    .PARAMETER Component
        Component name (e.g., "VMFleet", "ConfigManager"). Determines log directory.
    .PARAMETER RunId
        Run identifier for correlating logs across components.
    .PARAMETER LogLevel
        Minimum severity level to log. Default: INFO.
    .PARAMETER LogBasePath
        Base directory for logs. Default: logs/ in project root.
    .OUTPUTS
        String - The session ID for use with Write-Log and Stop-LogSession.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter()]
        [string]$RunId = (New-Guid).ToString().Substring(0, 8),

        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL')]
        [string]$LogLevel = 'INFO',

        [Parameter()]
        [string]$LogBasePath
    )

    if (-not $LogBasePath) {
        $LogBasePath = Join-Path $script:ProjectRoot 'logs'
    }

    $sessionId = "$RunId-$Component-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $componentDir = Join-Path $LogBasePath ($Component.ToLower())

    if (-not (Test-Path $componentDir)) {
        New-Item -ItemType Directory -Path $componentDir -Force | Out-Null
    }

    $logFilePath = Join-Path $componentDir "$sessionId.jsonl"

    $session = @{
        SessionId    = $sessionId
        Component    = $Component
        RunId        = $RunId
        LogLevel     = $LogLevel
        LogFilePath  = $logFilePath
        StartedAt    = (Get-Date -Format 'o')
        EntryCount   = 0
    }

    $script:ActiveSessions[$sessionId] = $session

    # Write session start entry
    Write-Log -Message "Log session started" -Severity 'INFO' -Component $Component -SessionId $sessionId -Data @{
        run_id    = $RunId
        log_level = $LogLevel
        log_file  = $logFilePath
    }

    return $sessionId
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a structured log entry to the component log file.
    .PARAMETER Message
        Log message text.
    .PARAMETER Severity
        Log severity: DEBUG, INFO, WARNING, ERROR, CRITICAL.
    .PARAMETER Component
        Component name. If SessionId is provided, auto-resolved from session.
    .PARAMETER SessionId
        Active session ID from Start-LogSession.
    .PARAMETER Data
        Additional structured data to include in the log entry.
    .PARAMETER ErrorRecord
        PowerShell ErrorRecord object for error logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL')]
        [string]$Severity = 'INFO',

        [Parameter()]
        [string]$Component,

        [Parameter()]
        [string]$SessionId,

        [Parameter()]
        [hashtable]$Data,

        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    # Resolve session
    $session = $null
    if ($SessionId -and $script:ActiveSessions.ContainsKey($SessionId)) {
        $session = $script:ActiveSessions[$SessionId]
        if (-not $Component) { $Component = $session.Component }
    }

    # Check log level threshold
    if ($session) {
        $threshold = $script:LogLevels[$session.LogLevel]
        $current = $script:LogLevels[$Severity]
        if ($current -lt $threshold) { return }
    }

    # Build log entry
    $entry = [ordered]@{
        timestamp     = (Get-Date -Format 'o')
        severity      = $Severity
        component     = ($Component ?? 'Unknown')
        message       = $Message
        correlation_id = ($session ? $session.RunId : '')
        session_id    = ($SessionId ?? '')
    }

    # Add optional data
    if ($Data) {
        $entry['data'] = $Data
    }

    # Add error details
    if ($ErrorRecord) {
        $entry['error'] = [ordered]@{
            type       = $ErrorRecord.Exception.GetType().FullName
            message    = $ErrorRecord.Exception.Message
            target     = $ErrorRecord.TargetObject
            position   = $ErrorRecord.InvocationInfo.PositionMessage
            stack      = $ErrorRecord.ScriptStackTrace
        }
    }

    # Convert to JSON line
    $jsonLine = $entry | ConvertTo-Json -Depth 5 -Compress

    # Write to file if session is active
    if ($session) {
        Add-Content -Path $session.LogFilePath -Value $jsonLine -Encoding UTF8
        $session.EntryCount++
    }
    else {
        # Fallback: write to default orchestrator log
        $defaultLogDir = Join-Path $script:ProjectRoot 'logs\orchestrator'
        if (-not (Test-Path $defaultLogDir)) {
            New-Item -ItemType Directory -Path $defaultLogDir -Force | Out-Null
        }
        $defaultLogFile = Join-Path $defaultLogDir "default-$(Get-Date -Format 'yyyyMMdd').jsonl"
        Add-Content -Path $defaultLogFile -Value $jsonLine -Encoding UTF8
    }

    # Also write to verbose/warning/error streams
    switch ($Severity) {
        'DEBUG'    { Write-Debug $Message }
        'INFO'     { Write-Verbose $Message }
        'WARNING'  { Write-Warning $Message }
        'ERROR'    { Write-Error $Message -ErrorAction Continue }
        'CRITICAL' { Write-Error "[CRITICAL] $Message" -ErrorAction Continue }
    }
}

function Stop-LogSession {
    <#
    .SYNOPSIS
        Ends a logging session and writes the closing entry.
    .PARAMETER SessionId
        The session ID returned by Start-LogSession.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SessionId
    )

    if (-not $script:ActiveSessions.ContainsKey($SessionId)) {
        Write-Warning "Session not found: $SessionId"
        return
    }

    $session = $script:ActiveSessions[$SessionId]

    Write-Log -Message "Log session ended" -Severity 'INFO' -SessionId $SessionId -Data @{
        duration_seconds = [math]::Round(((Get-Date) - [datetime]$session.StartedAt).TotalSeconds, 2)
        total_entries    = $session.EntryCount
    }

    $script:ActiveSessions.Remove($SessionId)
}

function Get-LogSession {
    <#
    .SYNOPSIS
        Returns information about active log sessions.
    .PARAMETER SessionId
        Specific session ID. If omitted, returns all active sessions.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SessionId
    )

    if ($SessionId) {
        if ($script:ActiveSessions.ContainsKey($SessionId)) {
            return [PSCustomObject]$script:ActiveSessions[$SessionId]
        }
        return $null
    }

    return $script:ActiveSessions.Values | ForEach-Object { [PSCustomObject]$_ }
}

# Export module members
Export-ModuleMember -Function @(
    'Start-LogSession'
    'Write-Log'
    'Stop-LogSession'
    'Get-LogSession'
)
