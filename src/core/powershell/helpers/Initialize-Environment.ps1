# =============================================================================
# Initialize-Environment.ps1 - Azure Local Load Tools
# =============================================================================
# Bootstrap script that validates prerequisites, loads modules, and prepares
# the environment for load testing operations.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [string]$MasterConfigPath,

    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [ValidateSet('VMFleet', 'fio', 'iPerf', 'HammerDB', 'StressNg')]
    [string]$Solution = 'VMFleet',

    [Parameter()]
    [switch]$SkipPrerequisiteCheck,

    [Parameter()]
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# Resolve project root
if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

# ---- Prerequisite Checks ----
function Test-Prerequisites {
    [CmdletBinding()]
    param([string]$Solution)

    $checks = @()

    # PowerShell version
    $checks += [PSCustomObject]@{
        Name     = 'PowerShell 7.2+'
        Required = $true
        Found    = $PSVersionTable.PSVersion -ge [version]'7.2'
        Detail   = "Found: $($PSVersionTable.PSVersion)"
    }

    # powershell-yaml module
    $psYaml = Get-Module -ListAvailable -Name powershell-yaml
    $checks += [PSCustomObject]@{
        Name     = 'powershell-yaml module'
        Required = $true
        Found    = $null -ne $psYaml
        Detail   = if ($psYaml) { "Found: v$($psYaml.Version)" } else { 'Not installed' }
    }

    # ImportExcel module
    $importExcel = Get-Module -ListAvailable -Name ImportExcel
    $checks += [PSCustomObject]@{
        Name     = 'ImportExcel module'
        Required = $false
        Found    = $null -ne $importExcel
        Detail   = if ($importExcel) { "Found: v$($importExcel.Version)" } else { 'Not installed (optional - for XLSX reports)' }
    }

    # Az.KeyVault module (optional)
    $azKv = Get-Module -ListAvailable -Name Az.KeyVault
    $checks += [PSCustomObject]@{
        Name     = 'Az.KeyVault module'
        Required = $false
        Found    = $null -ne $azKv
        Detail   = if ($azKv) { "Found: v$($azKv.Version)" } else { 'Not installed (optional - for Key Vault credentials)' }
    }

    # Az.Monitor module (optional)
    $azMon = Get-Module -ListAvailable -Name Az.Monitor
    $checks += [PSCustomObject]@{
        Name     = 'Az.Monitor module'
        Required = $false
        Found    = $null -ne $azMon
        Detail   = if ($azMon) { "Found: v$($azMon.Version)" } else { 'Not installed (optional - for Azure Monitor push)' }
    }

    # asciidoctor-pdf (optional)
    $adocPdf = Get-Command 'asciidoctor-pdf' -ErrorAction SilentlyContinue
    $checks += [PSCustomObject]@{
        Name     = 'asciidoctor-pdf'
        Required = $false
        Found    = $null -ne $adocPdf
        Detail   = if ($adocPdf) { "Found: $($adocPdf.Source)" } else { 'Not installed (optional - for PDF reports)' }
    }

    # pandoc (optional)
    $pandoc = Get-Command 'pandoc' -ErrorAction SilentlyContinue
    $checks += [PSCustomObject]@{
        Name     = 'pandoc'
        Required = $false
        Found    = $null -ne $pandoc
        Detail   = if ($pandoc) { "Found: $($pandoc.Source)" } else { 'Not installed (optional - for DOCX reports)' }
    }

    # Solution-specific checks
    if ($Solution -eq 'VMFleet') {
        $vmfleet = Get-Module -ListAvailable -Name VMFleet
        $checks += [PSCustomObject]@{
            Name     = 'VMFleet module'
            Required = $true
            Found    = $null -ne $vmfleet
            Detail   = if ($vmfleet) { "Found: v$($vmfleet.Version)" } else { 'Not installed - Install-Module VMFleet' }
        }
    }

    return $checks
}

function Show-PrerequisiteReport {
    [CmdletBinding()]
    param($Checks)

    Write-Host "`n===== Prerequisite Check =====" -ForegroundColor Cyan
    foreach ($c in $Checks) {
        $symbol = if ($c.Found) { '[OK]' } elseif ($c.Required) { '[FAIL]' } else { '[SKIP]' }
        $color  = if ($c.Found) { 'Green' } elseif ($c.Required) { 'Red' } else { 'Yellow' }
        Write-Host "  $symbol $($c.Name) - $($c.Detail)" -ForegroundColor $color
    }
    Write-Host ''

    $failures = $Checks | Where-Object { $_.Required -and -not $_.Found }
    if ($failures.Count -gt 0) {
        Write-Error "Missing required prerequisites: $($failures.Name -join ', '). Install them and retry."
    }
}

# ---- Module Loading ----
function Import-CoreModules {
    [CmdletBinding()]
    param([string]$ProjectRoot)

    $modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
    $modules = @('ConfigManager', 'Logger', 'StateManager', 'CredentialManager', 'MonitoringManager', 'ReportGenerator')

    foreach ($mod in $modules) {
        $modFile = Join-Path $modulesPath "$mod\$mod.psm1"
        if (Test-Path $modFile) {
            Import-Module $modFile -Force -Verbose:$false
            Write-Verbose "Loaded module: $mod"
        }
        else {
            Write-Warning "Module not found: $modFile"
        }
    }
}

# ---- Config Validation ----
function Test-ConfigFiles {
    [CmdletBinding()]
    param(
        [string]$MasterConfigPath,
        [string]$ClusterConfigPath
    )

    if ($MasterConfigPath -and -not (Test-Path $MasterConfigPath)) {
        Write-Error "Master config not found: $MasterConfigPath"
    }
    if ($ClusterConfigPath -and -not (Test-Path $ClusterConfigPath)) {
        Write-Error "Cluster config not found: $ClusterConfigPath"
    }

    if ($MasterConfigPath -and (Test-Path $MasterConfigPath)) {
        $validation = Test-MasterConfig -ConfigPath $MasterConfigPath -ErrorAction SilentlyContinue
        if (-not $validation.IsValid) {
            Write-Warning "Master config validation issues found."
        }
    }
}

# ---- Directory Structure ----
function Initialize-DirectoryStructure {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProjectRoot)

    $directories = @(
        'logs\vmfleet', 'logs\fio', 'logs\iperf', 'logs\hammerdb',
        'logs\stress-ng', 'logs\monitoring', 'logs\pipeline', 'logs\reports',
        'state',
        'reports'
    )

    foreach ($dir in $directories) {
        $fullPath = Join-Path $ProjectRoot $dir
        if (-not (Test-Path $fullPath)) {
            if ($PSCmdlet.ShouldProcess($fullPath, "Create directory")) {
                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                Write-Verbose "Created directory: $dir"
            }
        }
    }
}

# ---- Main Execution ----
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Azure Local Load Tools - Init" -ForegroundColor Cyan
Write-Host "  Project Root: $ProjectRoot" -ForegroundColor Cyan
Write-Host "  Solution:     $Solution" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Step 1: Prerequisites
if (-not $SkipPrerequisiteCheck) {
    $checks = Test-Prerequisites -Solution $Solution
    Show-PrerequisiteReport -Checks $checks
}

# Step 2: Directory structure
Initialize-DirectoryStructure -ProjectRoot $ProjectRoot

# Step 3: Load modules
Import-CoreModules -ProjectRoot $ProjectRoot

# Step 4: Validate configs
$defaultMaster = Join-Path $ProjectRoot 'config\variables\master-environment.yml'
$defaultCluster = Join-Path $ProjectRoot 'config\clusters\example-cluster.yml'

$masterConfig  = if ($MasterConfigPath) { $MasterConfigPath } else { $defaultMaster }
$clusterConfig = if ($ClusterConfigPath) { $ClusterConfigPath } else { $defaultCluster }

Test-ConfigFiles -MasterConfigPath $masterConfig -ClusterConfigPath $clusterConfig

Write-Host "`nEnvironment initialized successfully." -ForegroundColor Green
Write-Host "Solution: $Solution | Config: $masterConfig" -ForegroundColor Gray
