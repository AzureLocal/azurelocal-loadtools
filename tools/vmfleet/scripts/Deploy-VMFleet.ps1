# =============================================================================
# Deploy-VMFleet.ps1 - Azure Local Load Tools
# =============================================================================
# Deploys the VMFleet fleet VMs on the cluster: New-Fleet (VMs per node, from the
# base VHD), Set-Fleet (vCPU and memory), Start-Fleet, then waits until Get-FleetVM
# reports every VM Ok. Runs on the first node as a one-shot scheduled task
# (VMFleet-Common.ps1). Phase 3 of the VMFleet pipeline.
#
# NOT PROVEN ON A LIVE CLUSTER. Running it creates VMs and copies the base VHD
# once per VM onto the node volumes.
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
    [string]$RunId,

    # Fleet VMs PER NODE (New-Fleet -VMs). Default: vm_count_per_node in vmfleet.json.
    [Parameter()]
    [int]$VMCount,

    [Parameter()]
    [int]$VMMemoryGB,

    [Parameter()]
    [int]$VMProcessorCount,

    # Not applied: VMFleet 2.1 data disks are a separate Set-Fleet -DataDiskSize step this tool does not run yet.
    [Parameter()]
    [int]$DataDiskSizeGB,

    # Not applied, see DataDiskSizeGB.
    [Parameter()]
    [int]$DataDiskCount,

    # Path ON THE NODE of the base VHD(X); a Generation 2 image. Default: storage.base_vhd_path in the cluster YAML.
    [Parameter()]
    [string]$BaseVHDPath,

    # Local administrator account and password inside the fleet VMs (New-Fleet -Admin / -AdminPass).
    # There is deliberately no default: a fleet must never be created with a well-known password.
    [Parameter()]
    [PSCredential]$FleetAdminCredential,

    # Account the fleet VMs use to reach the Collect volume (New-Fleet -ConnectUser / -ConnectPass). It must be an
    # administrator on every node. Default: -Credential.
    [Parameter()]
    [PSCredential]$FleetConnectCredential,

    # Minutes to wait for every fleet VM to report Ok after Start-Fleet.
    [Parameter()]
    [int]$WaitMinutes = 30,

    [Parameter()]
    [int]$TimeoutMinutes = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
. (Join-Path $PSScriptRoot 'VMFleet-Common.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$null = Start-LogSession -Component 'VMFleet-Deploy' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet deployment phase' -Severity Information
    if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

    if (-not $SolutionConfigPath) { $SolutionConfigPath = Join-Path $ProjectRoot 'tools\vmfleet\config\vmfleet.json' }
    if (-not $ClusterConfigPath) { $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot }

    $solutionConfig = Get-Content -LiteralPath $SolutionConfigPath -Raw | ConvertFrom-Json
    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath

    # Override chain: parameter > solution JSON (registry names: vm_count_per_node, vm_vcpu_count, vm_memory_gb, base_vhd_path)
    $vmCount = if ($VMCount) { $VMCount } else { [int](Get-VMFleetConfigValue $solutionConfig 'vm_count_per_node' 0) }
    $vmMemory = if ($VMMemoryGB) { $VMMemoryGB } else { [int](Get-VMFleetConfigValue $solutionConfig 'vm_memory_gb' 0) }
    $vmProcessors = if ($VMProcessorCount) { $VMProcessorCount } else { [int](Get-VMFleetConfigValue $solutionConfig 'vm_vcpu_count' 0) }
    $baseVhd = if ($BaseVHDPath) { $BaseVHDPath } elseif ($cluster.BaseVhdPath) { $cluster.BaseVhdPath } else { [string](Get-VMFleetConfigValue $solutionConfig 'base_vhd_path' '') }

    if ($vmCount -lt 1) { throw 'The VM count per node is not set: pass -VMCount or set vm_count_per_node in tools\vmfleet\config\vmfleet.json.' }
    if (-not $baseVhd -and -not $WhatIfPreference) { throw 'No base VHD: pass -BaseVHDPath, set storage.base_vhd_path in the cluster YAML or base_vhd_path in vmfleet.json. See docs\tools\vmfleet\deployment.md (base image).' }

    $expected = $vmCount * $cluster.Nodes.Count
    Write-Log -Message "Deploying $vmCount VMs per node on $($cluster.Nodes.Count) nodes ($expected in total), $vmProcessors vCPU, ${vmMemory}GB RAM each" -Severity Information
    Write-Log -Message "Cluster: $($cluster.ClusterName) | Base VHD (on the node): $baseVhd" -Severity Information
    if ($DataDiskSizeGB -or $DataDiskCount) {
        Write-Log -Message 'DataDiskSizeGB and DataDiskCount are not applied: this tool does not add VMFleet data disks (Set-Fleet -DataDiskSize).' -Severity Warning
    }

    $Credential = Get-VMFleetCredentialOrExit -Credential $Credential -ProjectRoot $ProjectRoot
    if (-not $FleetConnectCredential) { $FleetConnectCredential = $Credential }
    if (-not $FleetAdminCredential -and -not $WhatIfPreference) {
        throw 'FleetAdminCredential is required: supply the local administrator account the fleet VMs are created with (no default password is used).'
    }

    if ($PSCmdlet.ShouldProcess($cluster.ClusterName, "Deploy $expected fleet VMs ($vmCount per node)")) {
        # New-Fleet -Admin is a local account name: strip DOMAIN\ or @domain.
        $adminName = ($FleetAdminCredential.UserName -split '@')[0]
        $adminName = ($adminName -split '\\')[-1]
        if (-not $adminName) { $adminName = 'Administrator' }

        $nodeArguments = @{
            BaseVhdPath        = $baseVhd
            VMsPerNode         = $vmCount
            ExpectedVMs        = $expected
            Admin              = $adminName
            ConnectUser        = $FleetConnectCredential.UserName
            ProcessorCount     = $vmProcessors
            MemoryStartupBytes = ([int64]$vmMemory * 1GB)
            WaitMinutes        = $WaitMinutes
        }
        $nodeSecrets = @{
            FleetAdminPassword = $FleetAdminCredential.GetNetworkCredential().Password
            ConnectPassword    = $FleetConnectCredential.GetNetworkCredential().Password
        }

        Write-Log -Message 'Deploying fleet VMs with New-Fleet, Set-Fleet and Start-Fleet (node task)...' -Severity Information
        $result = Invoke-VMFleetNodeTask -ComputerName $cluster.PrimaryNode -Credential $Credential -Step 'Deploy' -RunId $RunId `
            -CollectPath $cluster.CollectPath -TimeoutSeconds ($TimeoutMinutes * 60) -Arguments $nodeArguments -Secrets $nodeSecrets
        $nodeSecrets = $null
        Write-Log -Message "Fleet VMs Ok: $($result.Output.VMsOk) of $($result.Output.VMsExpected)" -Severity Information
    }

    Write-Log -Message 'VMFleet deployment phase completed' -Severity Information
    Write-Host 'VMFleet deployment complete.' -ForegroundColor Green
} catch {
    Write-Log -Message "Deployment failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
} finally {
    Stop-LogSession
}
