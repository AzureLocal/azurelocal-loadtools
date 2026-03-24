# =============================================================================
# Install-Fio.ps1 - Azure Local Load Tools
# =============================================================================
# Installs fio on Linux VMs via Ansible playbook invocation.
# Phase 1 of the fio pipeline.
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
    [string]$AnsibleInventory,

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

$logSession = Start-LogSession -Component 'Fio-Install' -LogRootPath (Join-Path $ProjectRoot 'logs\fio')

try {
    Write-Log -Message 'Starting fio installation phase' -Severity Information

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\fio\config\fio.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    $clusterName = $clusterConfig.cluster.name
    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }

    Write-Log -Message "Cluster: $clusterName | Nodes: $($nodes -join ', ')" -Severity Information

    # Resolve Ansible inventory
    if (-not $AnsibleInventory) {
        $AnsibleInventory = Join-Path $ProjectRoot 'common\ansible\inventory\hosts.yml'
    }

    $playbookPath = Join-Path $ProjectRoot 'tools\fio\playbooks\deploy-fio.yml'

    if (-not (Test-Path $playbookPath)) {
        throw "Playbook not found: $playbookPath"
    }
    if (-not (Test-Path $AnsibleInventory)) {
        throw "Ansible inventory not found: $AnsibleInventory"
    }

    # Check if ansible-playbook is available
    $ansibleCmd = Get-Command 'ansible-playbook' -ErrorAction SilentlyContinue
    if (-not $ansibleCmd) {
        throw "ansible-playbook not found in PATH. Install Ansible or run from a Linux/WSL2 jump box."
    }

    if ($PSCmdlet.ShouldProcess($clusterName, 'Install fio via Ansible')) {
        Write-Log -Message "Running Ansible playbook: $playbookPath" -Severity Information

        $ansibleArgs = @(
            '--inventory', $AnsibleInventory,
            $playbookPath
        )

        if ($Force) {
            $ansibleArgs += '--extra-vars', 'force_reinstall=true'
        }

        $result = & ansible-playbook @ansibleArgs 2>&1
        $exitCode = $LASTEXITCODE

        foreach ($line in $result) {
            Write-Log -Message $line -Severity Information
        }

        if ($exitCode -ne 0) {
            throw "Ansible playbook failed with exit code $exitCode"
        }

        Write-Log -Message 'fio installation completed via Ansible' -Severity Information
    }

    Write-Host 'fio installation complete.' -ForegroundColor Green

    return @{
        ClusterName = $clusterName
        Nodes       = $nodes
        Playbook    = $playbookPath
        Status      = 'Installed'
    }
}
catch {
    Write-Log -Message "Installation failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
