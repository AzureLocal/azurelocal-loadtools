# =============================================================================
# Stop-VMFleetTest.ps1 - Azure Local Load Tools
# =============================================================================
# Stops a running VMFleet workload. Phase 4 of the VMFleet pipeline.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

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

$logSession = Start-LogSession -Component 'VMFleet-Stop' -LogRootPath (Join-Path $ProjectRoot 'logs\vmfleet')

try {
    Write-Log -Message 'Stopping VMFleet workload' -Severity Information

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

    if ($PSCmdlet.ShouldProcess($primaryNode, 'Stop VMFleet workload')) {
        Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            Import-Module VMFleet -ErrorAction Stop
            Stop-Fleet
            Write-Output 'VMFleet workload stop command issued'
        }

        Write-Log -Message 'VMFleet workload stopped' -Severity Information
        Write-Host 'VMFleet workload stopped.' -ForegroundColor Green
    }
}
catch {
    Write-Log -Message "Stop failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
