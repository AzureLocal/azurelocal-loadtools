# =============================================================================
# Prepare-VMFleetBaseImage.ps1 - Azure Local Load Tools
# =============================================================================
# OPTIONAL route to a VMFleet base image: ask Azure Local to download a Windows
# Server Azure Edition image from Azure Marketplace (a marketplaceGalleryImages
# resource), poll until it is Succeeded, then look for the VHDX it left in the
# storage path. NOT PROVEN ON A LIVE CLUSTER, and Microsoft Learn does not document
# the file layout of a gallery image in the storage path: if the search below finds
# no single VHDX, use the documented managed-disk export instead
# (docs\tools\vmfleet\deployment.md, "Base image").
#
# VMFleet creates plain Hyper-V Generation 2 VMs, not Azure Local VMs enabled by
# Azure Arc, so the image only has to be a Generation 2 VHD(X) on the cluster.
#
# Needs: an Az PowerShell session (Connect-AzAccount) with rights on the resource
# group, the Microsoft.EdgeMarketplace resource provider registered, and the Azure
# Connected Machine Resource Manager role for the Microsoft.AzureStackHCI resource
# provider app on the resource group (Microsoft Learn: "Create Azure Local VM image
# using Azure Marketplace images"). Subscription, resource group, custom location and
# storage path IDs are passed as parameters (or read from -ConfigPath); they are never
# committed to this repository.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    # Optional YAML with azure.subscription_id, azure.resource_group, azure.location,
    # azure_local.custom_location_id and azure_local.storage_path_id (variables.example.yml layout).
    # A value passed as a parameter wins.
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$SubscriptionId,

    [Parameter()]
    [string]$ResourceGroup,

    [Parameter()]
    [string]$Location,

    # Resource ID of the Azure Local custom location.
    [Parameter()]
    [string]$CustomLocationId,

    # Resource ID of the storage path (storageContainers) the image is stored in.
    [Parameter()]
    [string]$StoragePathId,

    [Parameter()]
    [string]$ImageName = 'vmfleet-base-ws2025',

    # Marketplace SKU of publisher MicrosoftWindowsServer, offer WindowsServer. The smalldisk SKU keeps the per-VM copy
    # (VMFleet copies the base VHD once per VM) at 32 GB. Other SKUs from Learn: 2025-datacenter-azure-edition-core,
    # 2022-datacenter-azure-edition-core, 2022-datacenter-azure-edition.
    [Parameter()]
    [string]$Sku = '2025-datacenter-azure-edition-smalldisk',

    [Parameter()]
    [int]$PollIntervalSeconds = 30,

    [Parameter()]
    [int]$TimeoutMinutes = 60,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
. (Join-Path $ProjectRoot 'tools\vmfleet\scripts\VMFleet-Common.ps1')
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
    } else {
        $response = Invoke-AzRestMethod -Method $Method -Path $Path
    }

    # Invoke-AzRestMethod does not throw on an HTTP error: look at the status code.
    if ($response.StatusCode -ge 400) {
        throw "ARM $Method $Path returned HTTP $($response.StatusCode): $($response.Content)"
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
    } catch {
        if ($_.Exception.Message -match 'HTTP 404|NotFound|not found') {
            return $null
        }
        throw
    }
}

try {
    Write-Log -Message 'Starting VMFleet base image preparation' -Severity INFO -SessionId $logSession

    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot
    }
    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath

    # Parameters win; the optional config file fills the rest (variables.example.yml layout: azure, azure_local).
    if ($ConfigPath) {
        if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
        Import-Module powershell-yaml -ErrorAction Stop
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Yaml
        $azure = Get-VMFleetConfigValue $config 'azure'
        $azureLocal = Get-VMFleetConfigValue $config 'azure_local'
        if (-not $SubscriptionId) { $SubscriptionId = [string](Get-VMFleetConfigValue $azure 'subscription_id' '') }
        if (-not $ResourceGroup) { $ResourceGroup = [string](Get-VMFleetConfigValue $azure 'resource_group' '') }
        if (-not $Location) { $Location = [string](Get-VMFleetConfigValue $azure 'location' '') }
        if (-not $CustomLocationId) { $CustomLocationId = [string](Get-VMFleetConfigValue $azureLocal 'custom_location_id' '') }
        if (-not $StoragePathId) { $StoragePathId = [string](Get-VMFleetConfigValue $azureLocal 'storage_path_id' '') }
    }

    $required = [ordered]@{
        SubscriptionId   = $SubscriptionId
        ResourceGroup    = $ResourceGroup
        Location         = $Location
        CustomLocationId = $CustomLocationId
        StoragePathId    = $StoragePathId
    }
    $missing = @($required.Keys | Where-Object { [string]::IsNullOrWhiteSpace($required[$_]) })
    if ($missing.Count -gt 0) {
        throw "Missing values: $($missing -join ', '). Pass them as parameters or in -ConfigPath (azure.subscription_id, azure.resource_group, azure.location, azure_local.custom_location_id, azure_local.storage_path_id)."
    }

    $nodes = $cluster.Nodes
    $primaryNode = $cluster.PrimaryNode

    $Credential = Get-VMFleetCredentialOrExit -Credential $Credential -ProjectRoot $ProjectRoot

    Write-Log -Message 'Testing cluster connectivity' -Severity INFO -SessionId $logSession -Data @{ nodes = $nodes }
    $connectivity = Test-ClusterConnectivity -NodeNames $nodes -Credential $Credential
    $unreachable = @($connectivity | Where-Object { -not $_.Reachable })
    if ($unreachable.Count -gt 0) {
        throw "Cannot reach nodes: $($unreachable.Node -join ', ')"
    }

    # Braces around the variable name: a bare name followed by a question mark is read as part of the variable name.
    $apiVersion = '2023-09-01-preview'
    $imagePath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.AzureStackHCI/marketplaceGalleryImages/${ImageName}?api-version=$apiVersion"
    $imageResource = Get-ArmResourceIfExists -Path $imagePath

    if ($imageResource -and $imageResource.properties.provisioningState -eq 'Succeeded' -and -not $Force.IsPresent) {
        Write-Log -Message 'Marketplace image already exists in Succeeded state; skipping download' -Severity INFO -SessionId $logSession -Data @{ image_name = $ImageName }
    } else {
        $putBody = @{
            location = $Location
            extendedLocation = @{
                type = 'CustomLocation'
                name = $CustomLocationId
            }
            properties = @{
                osType = 'Windows'
                hyperVGeneration = 'V2'
                containerId = $StoragePathId
                identifier = @{
                    publisher = 'MicrosoftWindowsServer'
                    offer = 'WindowsServer'
                    sku = $Sku
                }
                version = @{
                    name = 'latest'
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($ImageName, 'Trigger marketplace image download')) {
            Write-Log -Message 'Submitting marketplace image PUT request' -Severity INFO -SessionId $logSession -Data @{ image_name = $ImageName; sku = $Sku; location = $Location }
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

    $storageContainerPath = "${StoragePathId}?api-version=$apiVersion"
    $storageContainer = Invoke-ArmRequest -Method GET -Path $storageContainerPath
    $containerRootPath = $storageContainer.properties.path

    if ([string]::IsNullOrWhiteSpace($containerRootPath)) {
        throw "Unable to resolve storage container path from: $StoragePathId"
    }

    # The layout of a gallery image inside the storage path is not documented: search for VHD(X) files whose path
    # contains the image name, on the node (a local read, no second hop).
    Write-Log -Message 'Searching for the image VHD(X) on the primary node' -Severity INFO -SessionId $logSession -Data @{ node = $primaryNode; path = $containerRootPath }
    $found = @(Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            param($Root, $Name)
            Get-ChildItem -LiteralPath $Root -Recurse -File -Include '*.vhdx', '*.vhd' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like "*$Name*" } |
                ForEach-Object { $_.FullName }
        } -ArgumentList @($containerRootPath, $ImageName))

    if ($found.Count -ne 1) {
        $list = if ($found.Count -eq 0) { 'none found' } else { $found -join '; ' }
        throw "Expected exactly one VHD(X) for image $ImageName under $containerRootPath, found: $list. Pick the right file yourself, or use the managed-disk export in docs\tools\vmfleet\deployment.md."
    }
    $resolvedVhdPath = [string]$found[0]

    Write-Log -Message 'VMFleet base image is ready' -Severity INFO -SessionId $logSession -Data @{ resolved_vhd_path = $resolvedVhdPath }

    Write-Host ''
    Write-Host 'VMFleet base image is ready.' -ForegroundColor Green
    Write-Host "Resolved VHDX path: $resolvedVhdPath" -ForegroundColor Green
    Write-Host 'Set this value as storage.base_vhd_path in your cluster YAML (or pass -BaseVHDPath) before running Deploy-VMFleet.ps1.' -ForegroundColor Yellow
} catch {
    Write-Log -Message "Base image preparation failed: $($_.Exception.Message)" -Severity ERROR -SessionId $logSession -ErrorRecord $_
    throw
} finally {
    Stop-LogSession -SessionId $logSession
}
