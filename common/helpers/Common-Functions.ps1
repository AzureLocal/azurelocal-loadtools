# =============================================================================
# Common-Functions.ps1 - Azure Local Load Tools
# =============================================================================
# Shared utility functions used across all solution scripts.
# Dot-source this file in any script that needs common helpers.
# =============================================================================

function Test-ClusterConnectivity {
    <#
    .SYNOPSIS
        Tests WinRM connectivity to all cluster nodes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$NodeNames,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [int]$TimeoutSeconds = 15
    )

    $results = @()
    foreach ($node in $NodeNames) {
        $params = @{ ComputerName = $node; ErrorAction = 'SilentlyContinue' }
        if ($Credential) { $params['Credential'] = $Credential }

        $result = Test-WSMan @params
        $results += [PSCustomObject]@{
            Node     = $node
            Reachable = $null -ne $result
            Detail    = if ($result) { 'OK' } else { 'Unreachable' }
        }
    }

    $unreachable = $results | Where-Object { -not $_.Reachable }
    if ($unreachable.Count -gt 0) {
        Write-Warning "Unreachable nodes: $($unreachable.Node -join ', ')"
    }

    return $results
}

function Invoke-RemoteCommand {
    <#
    .SYNOPSIS
        Executes a script block on a remote node with retry logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object[]]$ArgumentList,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 5
    )

    $params = @{
        ComputerName = $ComputerName
        ScriptBlock  = $ScriptBlock
        ErrorAction  = 'Stop'
    }
    if ($ArgumentList) { $params['ArgumentList'] = $ArgumentList }
    if ($Credential)   { $params['Credential']   = $Credential }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            return Invoke-Command @params
        }
        catch {
            if ($attempt -eq $MaxRetries) {
                throw "Failed after $MaxRetries attempts on $ComputerName : $($_.Exception.Message)"
            }
            Write-Warning "Attempt $attempt/$MaxRetries failed on $ComputerName. Retrying in ${RetryDelaySeconds}s..."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function ConvertTo-SafeFileName {
    <#
    .SYNOPSIS
        Converts a string to a filesystem-safe name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return ($Name -replace '[^a-zA-Z0-9\-_\.]', '_').ToLower()
}

function Get-Timestamp {
    <#
    .SYNOPSIS
        Returns a standardized ISO 8601 timestamp.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$FilenameSafe
    )

    if ($FilenameSafe) {
        return Get-Date -Format 'yyyyMMdd-HHmmss'
    }
    return Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ' -AsUTC
}

function Wait-WithProgress {
    <#
    .SYNOPSIS
        Waits for a specified duration showing a progress bar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Seconds,

        [Parameter()]
        [string]$Activity = 'Waiting'
    )

    for ($i = 0; $i -lt $Seconds; $i++) {
        $percent = [int](($i / $Seconds) * 100)
        Write-Progress -Activity $Activity -Status "$($Seconds - $i) seconds remaining" -PercentComplete $percent
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $Activity -Completed
}

function Copy-ToClusterNodes {
    <#
    .SYNOPSIS
        Copies a file or directory to all cluster nodes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter(Mandatory)]
        [string[]]$NodeNames,

        [Parameter()]
        [PSCredential]$Credential
    )

    foreach ($node in $NodeNames) {
        if ($PSCmdlet.ShouldProcess("$SourcePath → $node`:$DestinationPath", "Copy")) {
            $sessionParams = @{ ComputerName = $node }
            if ($Credential) { $sessionParams['Credential'] = $Credential }

            $session = New-PSSession @sessionParams
            try {
                Copy-Item -Path $SourcePath -Destination $DestinationPath -ToSession $session -Recurse -Force
                Write-Verbose "Copied to $node`:$DestinationPath"
            }
            finally {
                Remove-PSSession -Session $session
            }
        }
    }
}

function Get-ClusterNodesFromConfig {
    <#
    .SYNOPSIS
        Extracts node names from a cluster config file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClusterConfigPath
    )

    Import-Module powershell-yaml -ErrorAction Stop
    $config = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    return $config.nodes | ForEach-Object { $_.name }
}

function Format-ByteSize {
    <#
    .SYNOPSIS
        Formats bytes into human-readable size strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$Bytes
    )

    $sizes = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $order = 0
    while ($Bytes -ge 1024 -and $order -lt $sizes.Count - 1) {
        $order++
        $Bytes = $Bytes / 1024
    }
    return '{0:N2} {1}' -f $Bytes, $sizes[$order]
}

function Format-Duration {
    <#
    .SYNOPSIS
        Formats a TimeSpan into a human-readable string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [TimeSpan]$Duration
    )

    if ($Duration.TotalHours -ge 1) {
        return '{0}h {1}m {2}s' -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds
    }
    elseif ($Duration.TotalMinutes -ge 1) {
        return '{0}m {1}s' -f [int]$Duration.TotalMinutes, $Duration.Seconds
    }
    return '{0}s' -f [int]$Duration.TotalSeconds
}
