# =============================================================================
# Install-VMFleet.ps1 - Azure Local Load Tools
# =============================================================================
# Installs the VMFleet PowerShell module and DiskSpd on the cluster.
# Phase 1 of the VMFleet pipeline.
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
    [string]$VMFleetVersion,

    [Parameter()]
    [string]$DiskSpdVersion,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Resolve project root
if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}

# Load core modules
. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

# Initialize logging
$logSession = Start-LogSession -Component 'VMFleet-Install' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Starting VMFleet installation phase' -Severity Information

    # Load configuration with override chain
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
    $vmfleetVer = if ($VMFleetVersion) { $VMFleetVersion } else { $solutionConfig.vmfleet_version }
    $diskspdVer = if ($DiskSpdVersion) { $DiskSpdVersion } else { $solutionConfig.diskspd_version }
    $clusterName = $clusterConfig.cluster.name
    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }

    Write-Log -Message "Cluster: $clusterName | VMFleet: $vmfleetVer | DiskSpd: $diskspdVer" -Severity Information
    Write-Log -Message "Nodes: $($nodes -join ', ')" -Severity Information

    # Get credentials if not provided
    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    # Test connectivity
    Write-Log -Message 'Testing cluster connectivity...' -Severity Information
    $connectivity = Test-ClusterConnectivity -NodeNames $nodes -Credential $Credential
    $unreachable = $connectivity | Where-Object { -not $_.Reachable }
    if ($unreachable.Count -gt 0) {
        throw "Cannot reach nodes: $($unreachable.Node -join ', ')"
    }
    Write-Log -Message 'All nodes reachable' -Severity Information

    # Install VMFleet module on the first node (it distributes to CSV)
    $primaryNode = $nodes[0]

    if ($PSCmdlet.ShouldProcess($primaryNode, "Install VMFleet $vmfleetVer")) {
        Write-Log -Message "Installing VMFleet module on $primaryNode..." -Severity Information

        Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            param($Version, $ForceInstall)

            $existing = Get-Module -ListAvailable -Name VMFleet | Where-Object { $_.Version -eq $Version }
            if ($existing -and -not $ForceInstall) {
                Write-Output "VMFleet $Version already installed"
                return
            }

            Install-Module -Name VMFleet -RequiredVersion $Version -Force -AllowClobber -Scope AllUsers
            Write-Output "VMFleet $Version installed successfully"
        } -ArgumentList @($vmfleetVer, $Force.IsPresent)

        Write-Log -Message 'VMFleet module installation complete' -Severity Information
    }

    # Verify DiskSpd availability
    if ($PSCmdlet.ShouldProcess($primaryNode, "Verify DiskSpd $diskspdVer")) {
        Write-Log -Message 'Verifying DiskSpd availability...' -Severity Information

        $diskspdCheck = Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            $diskspd = Get-Command 'diskspd.exe' -ErrorAction SilentlyContinue
            if ($diskspd) {
                return @{ Found = $true; Path = $diskspd.Source }
            }
            return @{ Found = $false; Path = $null }
        }

        if ($diskspdCheck.Found) {
            Write-Log -Message "DiskSpd found at: $($diskspdCheck.Path)" -Severity Information
        }
        else {
            Write-Log -Message 'DiskSpd not found. VMFleet will use its bundled version.' -Severity Warning
        }
    }

    Write-Log -Message 'VMFleet installation phase completed successfully' -Severity Information
    Write-Host 'VMFleet installation complete.' -ForegroundColor Green
}
catch {
    Write-Log -Message "Installation failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
