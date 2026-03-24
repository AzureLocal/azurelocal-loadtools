# =============================================================================
# Start-HammerDBTest.ps1 - Azure Local Load Tools
# =============================================================================
# Executes a HammerDB TPC-C or TPC-H benchmark run against a target database
# server using the HammerDB Tcl CLI (hammerdbcli.exe).
# Phase 2 of the HammerDB pipeline.
# =============================================================================

#Requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$SolutionConfigPath,

    [Parameter()]
    [string]$ClusterConfigPath,

    [Parameter()]
    [string]$ProfilePath,

    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [ValidateSet('mssql', 'postgresql')]
    [string]$DbType,

    [Parameter()]
    [string]$DbServer,

    [Parameter()]
    [string]$DbName,

    [Parameter()]
    [int]$WarehouseCount,

    [Parameter()]
    [int]$VirtualUsers,

    [Parameter()]
    [string]$HammerDBPath = 'C:\HammerDB',

    [Parameter()]
    [string]$RunId
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'HammerDB-Test' -LogRootPath (Join-Path $ProjectRoot 'logs\hammerdb')

try {
    Write-Log -Message 'Starting HammerDB test phase' -Severity Information

    if (-not $RunId) { $RunId = "hammerdb-$(Get-Timestamp -FilenameSafe)" }

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\hammerdb\config\hammerdb.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    # Load workload profile
    $profile = $null
    if ($ProfilePath -and (Test-Path $ProfilePath)) {
        $profile = Get-Content -Path $ProfilePath -Raw | ConvertFrom-Yaml
        Write-Log -Message "Loaded profile: $($profile.profile.name)" -Severity Information
    }

    # Resolve parameters: explicit > profile > solution config
    $dbTypeVal       = if ($DbType)         { $DbType }         elseif ($profile) { $profile.profile.parameters.db_type }        else { $solutionConfig.hammerdb_db_type }
    $dbServerVal     = if ($DbServer)       { $DbServer }       elseif ($profile) { $profile.profile.parameters.db_server }      else { $solutionConfig.hammerdb_db_server }
    $dbNameVal       = if ($DbName)         { $DbName }         elseif ($profile) { $profile.profile.parameters.db_name }        else { $solutionConfig.hammerdb_db_name }
    $warehouseVal    = if ($WarehouseCount) { $WarehouseCount } elseif ($profile) { $profile.profile.parameters.warehouse_count } else { [int]$solutionConfig.hammerdb_warehouse_count }
    $vuVal           = if ($VirtualUsers)   { $VirtualUsers }   elseif ($profile) { $profile.profile.parameters.virtual_users }  else { [int]$solutionConfig.hammerdb_virtual_users }
    $benchmarkType   = if ($profile)        { $profile.profile.parameters.benchmark_type } else { 'tpcc' }
    $rampUpSeconds   = if ($profile)        { $profile.profile.parameters.ramp_up_seconds }   else { 120 }
    $testDuration    = if ($profile)        { $profile.profile.parameters.test_duration_seconds } else { [int]$solutionConfig.test_duration_seconds }

    if (-not $dbServerVal) {
        throw "DB server not specified. Set hammerdb_db_server in config, use -DbServer, or specify a profile."
    }

    Write-Log -Message "Benchmark: $benchmarkType | DB: $dbTypeVal@$dbServerVal/$dbNameVal | Warehouses: $warehouseVal | VUs: $vuVal" -Severity Information

    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    $primaryNode = $nodes[0]

    if (-not $Credential) {
        Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    # Build HammerDB Tcl script content
    $tclBenchmark = switch ($benchmarkType) {
        'tpcc' { 'tpcc' }
        'tpch' { 'tpch' }
        default { 'tpcc' }
    }

    $tclDbType = switch ($dbTypeVal) {
        'mssql'      { 'mssqls' }
        'postgresql' { 'pg' }
        default      { 'mssqls' }
    }

    $resultsDir = "C:\\hammerdb-results\\$RunId"

    $tclScript = @"
dbset db $tclDbType
dbset bm $tclBenchmark
diset connection ${tclDbType}_server $dbServerVal
diset connection ${tclDbType}_dbase $dbNameVal
diset tpcc ${tclDbType}_count_ware $warehouseVal
diset tpcc ${tclDbType}_num_vu $vuVal
diset tpcc ${tclDbType}_rampup $rampUpSeconds
diset tpcc ${tclDbType}_duration $testDuration
diset tpcc logtotemp 1
diset tpcc unique 1
vuset logtotemp 1
vuset unique 1
loadscript
vucreate
vurun
runtimer $($rampUpSeconds + $testDuration + 60)
vudestroy
"@

    if ($PSCmdlet.ShouldProcess($primaryNode, "Run HammerDB $benchmarkType benchmark")) {
        Write-Log -Message "Running HammerDB on $primaryNode..." -Severity Information

        Invoke-RemoteCommand -ComputerName $primaryNode -Credential $Credential -ScriptBlock {
            param($HammerPath, $TclScript, $ResultsDir, $RunIdVal)

            New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null

            $tclFile = Join-Path $env:TEMP "hammerdb-run-$RunIdVal.tcl"
            Set-Content -Path $tclFile -Value $TclScript -Encoding UTF8

            $hammerCli = Join-Path $HammerPath 'hammerdbcli.exe'
            if (-not (Test-Path $hammerCli)) {
                throw "HammerDB CLI not found at: $hammerCli"
            }

            $logFile = Join-Path $ResultsDir 'hammerdb-run.log'
            $proc = Start-Process -FilePath $hammerCli -ArgumentList "auto $tclFile" `
                                  -RedirectStandardOutput $logFile `
                                  -Wait -PassThru -NoNewWindow

            Remove-Item $tclFile -Force -ErrorAction SilentlyContinue

            if ($proc.ExitCode -ne 0) {
                throw "HammerDB CLI exited with code $($proc.ExitCode). See $logFile"
            }

            Write-Output "HammerDB run complete. Log: $logFile"
        } -ArgumentList @($HammerDBPath, $tclScript, $resultsDir, $RunId)

        Write-Log -Message 'HammerDB benchmark execution complete' -Severity Information
    }

    Write-Host "HammerDB test finished. Run ID: $RunId" -ForegroundColor Green

    return @{
        RunId         = $RunId
        PrimaryNode   = $primaryNode
        RemoteResults = $resultsDir
        Parameters    = @{
            BenchmarkType   = $benchmarkType
            DbType          = $dbTypeVal
            DbServer        = $dbServerVal
            DbName          = $dbNameVal
            WarehouseCount  = $warehouseVal
            VirtualUsers    = $vuVal
            RampUpSeconds   = $rampUpSeconds
            TestDuration    = $testDuration
            ProfileName     = if ($profile) { $profile.profile.name } else { 'custom' }
        }
    }
}
catch {
    Write-Log -Message "Test phase failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
