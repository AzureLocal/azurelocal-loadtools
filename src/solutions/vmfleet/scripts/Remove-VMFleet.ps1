# =============================================================================
# Remove-VMFleet.ps1 - Azure Local Load Tools
# =============================================================================
# Tears down VMFleet VMs and cleans up cluster resources.
# Phase 7 (cleanup) of the VMFleet pipeline.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [switch]$RemoveVHDs,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'VMFleet-Remove' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet cleanup phase' -Severity Information

    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\example-cluster.yml'
    }

    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml
    $primaryNode = ($clusterConfig.nodes | ForEach-Object { $_.name })[0]

    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    # Stop any running workloads first
    if ($PSCmdlet.ShouldProcess($primaryNode, 'Stop running VMFleet workloads')) {
        Write-Log -Message 'Stopping any running workloads...' -Severity Information
        Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            Import-Module VMFleet -ErrorAction Stop
            try { Stop-Fleet -ErrorAction SilentlyContinue } catch { }
        }
    }

    # Remove fleet VMs
    if ($PSCmdlet.ShouldProcess($primaryNode, 'Remove all VMFleet VMs')) {
        Write-Log -Message 'Removing fleet VMs...' -Severity Information

        Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            param($CleanVHDs)
            Import-Module VMFleet -ErrorAction Stop

            # Get all fleet VMs
            $fleetVMs = Get-Fleet -ErrorAction SilentlyContinue
            if ($fleetVMs) {
                Write-Output "Removing $($fleetVMs.Count) fleet VMs..."

                # Stop VMs first
                $fleetVMs | Where-Object { $_.State -eq 'Running' } | ForEach-Object {
                    Stop-VM -Name $_.Name -Force -ErrorAction SilentlyContinue
                }

                # Remove VMs
                $fleetVMs | ForEach-Object {
                    Remove-VM -Name $_.Name -Force -ErrorAction SilentlyContinue
                }

                Write-Output 'Fleet VMs removed'
            }
            else {
                Write-Output 'No fleet VMs found'
            }
        } -ArgumentList @($RemoveVHDs.IsPresent)

        Write-Log -Message 'Fleet VMs removed' -Severity Information

        if ($RemoveVHDs) {
            Write-Log -Message 'Cleaning up VHD files...' -Severity Information
            Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
                param($CSVPath)
                $fleetPath = Join-Path $CSVPath 'collect'
                if (Test-Path $fleetPath) {
                    Remove-Item -Path $fleetPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "Cleaned up fleet storage at $fleetPath"
                }
            } -ArgumentList @($clusterConfig.storage.csv_path)
        }
    }

    Write-Log -Message 'VMFleet cleanup completed' -Severity Information
    Write-Host 'VMFleet cleanup complete.' -ForegroundColor Green
}
catch {
    Write-Log -Message "Cleanup failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
