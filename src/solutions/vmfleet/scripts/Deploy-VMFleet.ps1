# =============================================================================
# Deploy-VMFleet.ps1 - Azure Local Load Tools
# =============================================================================
# Deploys VMFleet fleet VMs on the cluster using Set-Fleet.
# Phase 2 of the VMFleet pipeline.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$SolutionConfigPath,

    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [int]$VMCount,

    [Parameter()]
    [int]$VMMemoryGB,

    [Parameter()]
    [int]$VMProcessorCount,

    [Parameter()]
    [int]$DataDiskSizeGB,

    [Parameter()]
    [int]$DataDiskCount,

    [Parameter()]
    [string]$BaseVHDPath
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'VMFleet-Deploy' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet deployment phase' -Severity Information

    # Load configuration
    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'config\variables\solutions\vmfleet.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\example-cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    # Resolve parameters via override chain
    $vmCount        = if ($VMCount)          { $VMCount }          else { [int]$solutionConfig.vmfleet_vm_count }
    $vmMemory       = if ($VMMemoryGB)       { $VMMemoryGB }       else { [int]$solutionConfig.vmfleet_vm_memory_gb }
    $vmProcessors   = if ($VMProcessorCount) { $VMProcessorCount } else { [int]$solutionConfig.vmfleet_vm_processors }
    $diskSize       = if ($DataDiskSizeGB)   { $DataDiskSizeGB }   else { [int]$solutionConfig.vmfleet_data_disk_size_gb }
    $diskCount      = if ($DataDiskCount)    { $DataDiskCount }    else { [int]$solutionConfig.vmfleet_data_disk_count }
    $baseVhd        = if ($BaseVHDPath)      { $BaseVHDPath }      else { $solutionConfig.vmfleet_base_vhd_path }
    $csvPath        = $clusterConfig.storage.csv_path
    $clusterName    = $clusterConfig.cluster.name
    $primaryNode    = ($clusterConfig.nodes | ForEach-Object { $_.name })[0]

    Write-Log -Message "Deploying $vmCount VMs (${vmMemory}GB RAM, $vmProcessors vCPU, ${diskCount}x${diskSize}GB disks)" -Severity Information
    Write-Log -Message "Cluster: $clusterName | CSV: $csvPath | Base VHD: $baseVhd" -Severity Information

    # Get credentials
    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    # Validate base VHD exists
    if ($PSCmdlet.ShouldProcess($primaryNode, "Validate base VHD")) {
        $vhdExists = Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            param($Path)
            Test-Path $Path
        } -ArgumentList @($baseVhd)

        if (-not $vhdExists) {
            throw "Base VHD not found at: $baseVhd. Deploy a base image first."
        }
        Write-Log -Message 'Base VHD validated' -Severity Information
    }

    # Deploy fleet VMs
    if ($PSCmdlet.ShouldProcess($clusterName, "Deploy $vmCount fleet VMs")) {
        Write-Log -Message 'Deploying fleet VMs via Set-Fleet...' -Severity Information

        Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            param($Count, $MemoryGB, $Processors, $DiskSizeGB, $DiskCount, $BaseVHD, $CSVPath)

            Import-Module VMFleet -ErrorAction Stop

            # Set-Fleet creates the fleet VM infrastructure
            $setFleetParams = @{
                VMs            = $Count
                AdminPassword  = (ConvertTo-SecureString 'Placeholder!' -AsPlainText -Force)
                ConnectUser    = 'Administrator'
                ConnectPassword = (ConvertTo-SecureString 'Placeholder!' -AsPlainText -Force)
            }

            if ($BaseVHD)    { $setFleetParams['BaseDiskPath'] = $BaseVHD }
            if ($CSVPath)    { $setFleetParams['CSV']          = $CSVPath }

            Set-Fleet @setFleetParams

            Write-Output "Fleet VMs deployment initiated for $Count VMs"
        } -ArgumentList @($vmCount, $vmMemory, $vmProcessors, $diskSize, $diskCount, $baseVhd, $csvPath)

        Write-Log -Message 'Fleet VM deployment command issued' -Severity Information
    }

    # Wait for VMs to be ready
    Write-Log -Message 'Waiting for fleet VMs to become ready...' -Severity Information
    $timeout = New-TimeSpan -Minutes 30
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    do {
        Start-Sleep -Seconds 30
        $vmStatus = Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            Import-Module VMFleet -ErrorAction Stop
            $vms = Get-Fleet
            @{
                Total   = ($vms | Measure-Object).Count
                Running = ($vms | Where-Object { $_.State -eq 'Running' } | Measure-Object).Count
            }
        }
        Write-Log -Message "VMs: $($vmStatus.Running)/$($vmStatus.Total) running" -Severity Information
    } while ($vmStatus.Running -lt $vmStatus.Total -and $stopwatch.Elapsed -lt $timeout)

    if ($vmStatus.Running -lt $vmStatus.Total) {
        Write-Log -Message "Timeout: Only $($vmStatus.Running)/$($vmStatus.Total) VMs running after 30 minutes" -Severity Warning
    }
    else {
        Write-Log -Message 'All fleet VMs are running' -Severity Information
    }

    Write-Log -Message 'VMFleet deployment phase completed' -Severity Information
    Write-Host 'VMFleet deployment complete.' -ForegroundColor Green
}
catch {
    Write-Log -Message "Deployment failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
