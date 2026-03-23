# =============================================================================
# Prepare-VMFleetBaseImage.ps1 - Azure Local Load Tools
# =============================================================================
# Ensures a VMFleet base image exists on Azure Local cluster storage.
# If missing, triggers marketplace download and polls progress until ready.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$ImageName = 'ws2022-core-g2',

    [Parameter()]
    [int]$PollIntervalSeconds = 30,

    [Parameter()]
    [int]$TimeoutMinutes = 60,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'VMFleet-BaseImage' -LogBasePath (Join-Path $ProjectRoot 'logs\vmfleet')

function Invoke-ArmRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'PUT')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [hashtable]$Body
    )

    if ($Body) {
        $payload = $Body | ConvertTo-Json -Depth 10
        $response = Invoke-AzRestMethod -Method $Method -Path $Path -Payload $payload
    }
    else {
        $response = Invoke-AzRestMethod -Method $Method -Path $Path
    }

    if ($response.Content) {
        return $response.Content | ConvertFrom-Json -Depth 20
    }

    return $null
}

function Get-ArmResourceIfExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        return Invoke-ArmRequest -Method GET -Path $Path
    }
    catch {
        if ($_.Exception.Message -match '404|NotFound|not found') {
            return $null
        }
        throw
    }
}

try {
    Write-Log -Message 'Starting VMFleet base image preparation' -Severity INFO -SessionId $logSession

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $ProjectRoot 'config\variables\variables.yml'
    }

    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    if (-not (Test-Path $ClusterConfigPath)) {
        throw "Cluster config file not found: $ClusterConfigPath"
    }

    Import-Module powershell-yaml -ErrorAction Stop
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Yaml
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    $subscriptionId = $config.azure.subscription_id
    $resourceGroup = $config.azure.resource_group
    $location = $config.azure.location
    $customLocationId = $config.azure_local.custom_location_id
    $storagePathId = $config.azure_local.storage_path_id
    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    $primaryNode = $nodes[0]

    if ([string]::IsNullOrWhiteSpace($subscriptionId) -or
        [string]::IsNullOrWhiteSpace($resourceGroup) -or
        [string]::IsNullOrWhiteSpace($location) -or
        [string]::IsNullOrWhiteSpace($customLocationId) -or
        [string]::IsNullOrWhiteSpace($storagePathId)) {
        throw 'Missing required config values: azure.subscription_id, azure.resource_group, azure.location, azure_local.custom_location_id, azure_local.storage_path_id'
    }

    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    Write-Log -Message 'Testing cluster connectivity' -Severity INFO -SessionId $logSession -Data @{ nodes = $nodes }
    $connectivity = Test-ClusterConnectivity -NodeNames $nodes -Credential $Credential
    $unreachable = $connectivity | Where-Object { -not $_.Reachable }
    if ($unreachable.Count -gt 0) {
        throw "Cannot reach nodes: $($unreachable.Node -join ', ')"
    }

    $imagePath = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.AzureStackHCI/marketplaceGalleryImages/$ImageName?api-version=2023-09-01-preview"
    $imageResource = Get-ArmResourceIfExists -Path $imagePath

    if ($imageResource -and $imageResource.properties.provisioningState -eq 'Succeeded' -and -not $Force.IsPresent) {
        Write-Log -Message 'Marketplace image already exists in Succeeded state; skipping download' -Severity INFO -SessionId $logSession -Data @{ image_name = $ImageName }
    }
    else {
        $putBody = @{
            location = $location
            extendedLocation = @{
                type = 'CustomLocation'
                name = $customLocationId
            }
            properties = @{
                osType = 'Windows'
                hyperVGeneration = 'V2'
                identifier = @{
                    publisher = 'MicrosoftWindowsServer'
                    offer = 'WindowsServer'
                    sku = '2022-datacenter-core-g2'
                }
                version = @{
                    name = 'latest'
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($ImageName, 'Trigger marketplace image download')) {
            Write-Log -Message 'Submitting marketplace image PUT request' -Severity INFO -SessionId $logSession -Data @{ image_name = $ImageName; location = $location }
            [void](Invoke-ArmRequest -Method PUT -Path $imagePath -Body $putBody)

            $timeout = [TimeSpan]::FromMinutes($TimeoutMinutes)
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $finalState = $null

            while ($stopwatch.Elapsed -lt $timeout) {
                Start-Sleep -Seconds $PollIntervalSeconds
                $imageResource = Invoke-ArmRequest -Method GET -Path $imagePath
                $state = $imageResource.properties.provisioningState
                $finalState = $state

                $percent = [math]::Min(99, [math]::Floor(($stopwatch.Elapsed.TotalSeconds / $timeout.TotalSeconds) * 100))
                Write-Progress -Activity 'Downloading VMFleet base image' -Status "State: $state" -PercentComplete $percent

                Write-Log -Message 'Image provisioning state update' -Severity INFO -SessionId $logSession -Data @{
                    image_name = $ImageName
                    provisioning_state = $state
                    elapsed_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
                }

                if ($state -eq 'Succeeded') {
                    break
                }

                if ($state -in @('Failed', 'Canceled')) {
                    throw "Marketplace image provisioning failed with state: $state"
                }
            }

            Write-Progress -Activity 'Downloading VMFleet base image' -Completed

            if ($finalState -ne 'Succeeded') {
                throw "Timed out waiting for marketplace image provisioning after $TimeoutMinutes minutes. Last state: $finalState"
            }
        }
    }

    $storageContainerPath = "$storagePathId?api-version=2023-09-01-preview"
    $storageContainer = Invoke-ArmRequest -Method GET -Path $storageContainerPath
    $containerRootPath = $storageContainer.properties.path

    if ([string]::IsNullOrWhiteSpace($containerRootPath)) {
        throw "Unable to resolve storage container path from: $storagePathId"
    }

    $resolvedVhdPath = Join-Path -Path (Join-Path -Path $containerRootPath -ChildPath $ImageName) -ChildPath "$ImageName.vhdx"

    Write-Log -Message 'Validating base image path on primary node' -Severity INFO -SessionId $logSession -Data @{ node = $primaryNode; path = $resolvedVhdPath }
    $exists = Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
        param($Path)
        Test-Path -Path $Path
    } -ArgumentList @($resolvedVhdPath)

    if (-not $exists) {
        throw "Base image was provisioned but VHDX was not found on cluster path: $resolvedVhdPath"
    }

    Write-Log -Message 'VMFleet base image is ready' -Severity INFO -SessionId $logSession -Data @{ resolved_vhd_path = $resolvedVhdPath }

    Write-Host ''
    Write-Host 'VMFleet base image is ready.' -ForegroundColor Green
    Write-Host "Resolved VHDX path: $resolvedVhdPath" -ForegroundColor Green
    Write-Host 'Set this value in config\variables\variables.yml as storage.base_vhd_path before running Deploy-VMFleet.ps1.' -ForegroundColor Yellow
}
catch {
    Write-Log -Message "Base image preparation failed: $($_.Exception.Message)" -Severity ERROR -SessionId $logSession -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession -SessionId $logSession
}
