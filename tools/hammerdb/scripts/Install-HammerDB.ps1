# =============================================================================
# Install-HammerDB.ps1 - Azure Local Load Tools
# =============================================================================
# Downloads and installs HammerDB on target Windows VMs via PowerShell remoting.
# Phase 1 of the HammerDB pipeline.
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
    [string]$HammerDBVersion = '4.6',

    [Parameter()]
    [string]$InstallPath = 'C:\HammerDB',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'HammerDB-Install' -LogRootPath (Join-Path $ProjectRoot 'logs\hammerdb')

try {
    Write-Log -Message 'Starting HammerDB installation phase' -Severity Information

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\hammerdb\config\hammerdb.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    $clusterName = $clusterConfig.cluster.name
    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }

    Write-Log -Message "Cluster: $clusterName | HammerDB: $HammerDBVersion" -Severity Information
    Write-Log -Message "Target nodes: $($nodes -join ', ')" -Severity Information

    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    $connectivity = Test-ClusterConnectivity -NodeNames $nodes -Credential $Credential
    $unreachable = $connectivity | Where-Object { -not $_.Reachable }
    if ($unreachable.Count -gt 0) {
        throw "Cannot reach nodes: $($unreachable.Node -join ', ')"
    }

    $downloadUrl = "https://github.com/TPC-Council/HammerDB/releases/download/v${HammerDBVersion}/HammerDB-${HammerDBVersion}-Win.exe"

    foreach ($node in $nodes) {
        if ($PSCmdlet.ShouldProcess($node, "Install HammerDB $HammerDBVersion")) {
            Write-Log -Message "Installing HammerDB on $node..." -Severity Information

            Invoke-RemoteCommand -ComputerName $node -Credential $Credential -ScriptBlock {
                param($Url, $InstPath, $Ver, $ForceInstall)

                $installerPath = "$env:TEMP\HammerDB-$Ver-Win.exe"
                $existingDir   = Join-Path $InstPath "HammerDB-$Ver"

                if ((Test-Path $existingDir) -and -not $ForceInstall) {
                    Write-Output "HammerDB $Ver already installed at $existingDir"
                    return
                }

                # Download installer
                Write-Output "Downloading HammerDB $Ver from GitHub..."
                Invoke-WebRequest -Uri $Url -OutFile $installerPath -UseBasicParsing

                # Silent install
                Write-Output "Installing HammerDB to $InstPath..."
                $process = Start-Process -FilePath $installerPath -ArgumentList "/S /D=$InstPath" -Wait -PassThru
                if ($process.ExitCode -ne 0) {
                    throw "HammerDB installer failed with exit code $($process.ExitCode)"
                }

                Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                Write-Output "HammerDB $Ver installed at $InstPath"
            } -ArgumentList @($downloadUrl, $InstallPath, $HammerDBVersion, $Force.IsPresent)

            Write-Log -Message "HammerDB installation complete on $node" -Severity Information
        }
    }

    Write-Host "HammerDB $HammerDBVersion installation complete." -ForegroundColor Green

    return @{
        ClusterName     = $clusterName
        Nodes           = $nodes
        HammerDBVersion = $HammerDBVersion
        InstallPath     = $InstallPath
        Status          = 'Installed'
    }
}
catch {
    Write-Log -Message "Installation failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
