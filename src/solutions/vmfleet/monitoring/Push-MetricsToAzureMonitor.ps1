# =============================================================================
# Push-MetricsToAzureMonitor.ps1 - Azure Local Load Tools
# =============================================================================
# Pushes collected metrics to Azure Monitor / Log Analytics workspace.
# Optional component - requires Az.Monitor module and Azure connectivity.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$MetricsPath,

    [Parameter()]
    [string]$SolutionConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [string]$WorkspaceId,

    [Parameter()]
    [string]$WorkspaceKey,

    [Parameter()]
    [string]$LogType = 'AzureLocalLoadTest'
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'Monitoring-AzurePush' -LogRootPath (Join-Path $ProjectRoot 'logs\monitoring')

try {
    Write-Log -Message 'Starting Azure Monitor metrics push' -Severity Information

    # Load config for workspace details
    if (-not $WorkspaceId -or -not $WorkspaceKey) {
        if (-not $SolutionConfigPath) {
            $SolutionConfigPath = Join-Path $ProjectRoot 'config\variables\solutions\vmfleet.json'
        }
        $config = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json

        if (-not $WorkspaceId)  { $WorkspaceId  = $config.monitoring_workspace_id }
        if (-not $WorkspaceKey) {
            Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
            $WorkspaceKey = Get-ManagedSecret -SecretName 'log_analytics_key' -ProjectRoot $ProjectRoot
        }
    }

    if (-not $WorkspaceId -or -not $WorkspaceKey) {
        Write-Log -Message 'Azure Monitor workspace ID or key not configured. Skipping push.' -Severity Warning
        return
    }

    if (-not $MetricsPath) {
        Write-Error 'MetricsPath is required. Provide the directory containing .jsonl metric files.'
    }

    # Build the authorization signature for Log Analytics Data Collector API
    function New-LogAnalyticsSignature {
        param(
            [string]$WorkspaceId,
            [string]$SharedKey,
            [string]$Date,
            [int]$ContentLength,
            [string]$Method = 'POST',
            [string]$ContentType = 'application/json',
            [string]$Resource = '/api/logs'
        )

        $xHeaders = "x-ms-date:$Date"
        $stringToHash = "$Method`n$ContentLength`n$ContentType`n$xHeaders`n$Resource"
        $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
        $keyBytes = [Convert]::FromBase64String($SharedKey)
        $sha256 = New-Object System.Security.Cryptography.HMACSHA256
        $sha256.Key = $keyBytes
        $calculatedHash = $sha256.ComputeHash($bytesToHash)
        $encodedHash = [Convert]::ToBase64String($calculatedHash)
        return "SharedKey ${WorkspaceId}:${encodedHash}"
    }

    function Send-LogAnalyticsData {
        param(
            [string]$WorkspaceId,
            [string]$SharedKey,
            [string]$Body,
            [string]$LogType
        )

        $rfc1123 = [DateTime]::UtcNow.ToString('r')
        $contentLength = [Text.Encoding]::UTF8.GetByteCount($Body)
        $signature = New-LogAnalyticsSignature -WorkspaceId $WorkspaceId -SharedKey $SharedKey -Date $rfc1123 -ContentLength $contentLength

        $uri = "https://$WorkspaceId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"

        $headers = @{
            'Authorization'        = $signature
            'Log-Type'             = $LogType
            'x-ms-date'           = $rfc1123
            'time-generated-field' = 'timestamp'
        }

        $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Headers $headers -Body $Body
        return $response
    }

    # Read and push metric files
    $metricFiles = Get-ChildItem -Path $MetricsPath -Filter '*.jsonl' -Recurse
    Write-Log -Message "Found $($metricFiles.Count) metric files to push" -Severity Information

    foreach ($file in $metricFiles) {
        $entries = Get-Content -Path $file.FullName | Where-Object { $_ -match '\S' } | ConvertFrom-Json

        if ($entries.Count -eq 0) { continue }

        # Batch in groups of 500 (API limit)
        $batchSize = 500
        for ($i = 0; $i -lt $entries.Count; $i += $batchSize) {
            $batch = $entries[$i..([math]::Min($i + $batchSize - 1, $entries.Count - 1))]
            $body = $batch | ConvertTo-Json -Depth 5

            if ($PSCmdlet.ShouldProcess("$($batch.Count) records from $($file.Name)", 'Push to Azure Monitor')) {
                try {
                    Send-LogAnalyticsData -WorkspaceId $WorkspaceId -SharedKey $WorkspaceKey -Body $body -LogType $LogType
                    Write-Log -Message "Pushed $($batch.Count) records from $($file.Name)" -Severity Information
                }
                catch {
                    Write-Log -Message "Failed to push batch from $($file.Name): $($_.Exception.Message)" -Severity Warning
                }
            }
        }
    }

    Write-Log -Message 'Azure Monitor push complete' -Severity Information
    Write-Host 'Metrics pushed to Azure Monitor.' -ForegroundColor Green
}
catch {
    Write-Log -Message "Azure Monitor push failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
