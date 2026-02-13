# =============================================================================
# Invoke-VMFleetPipeline.ps1 - Azure Local Load Tools
# =============================================================================
# End-to-end orchestrator for VMFleet load testing. Executes all pipeline
# phases with checkpoint-based resume support.
#
# Phases: PreCheck → Install → Deploy → Test → Monitor → Collect → Report → Cleanup
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
    [string]$RunId,

    [Parameter()]
    [ValidateSet('PDF', 'DOCX', 'XLSX')]
    [string[]]$ReportFormats = @('PDF', 'XLSX'),

    [Parameter()]
    [switch]$SkipInstall,

    [Parameter()]
    [switch]$SkipDeploy,

    [Parameter()]
    [switch]$SkipCleanup,

    [Parameter()]
    [switch]$IncludeAzureMonitor,

    [Parameter()]
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

# ---- Bootstrap ----
. (Join-Path $ProjectRoot 'src\core\powershell\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'src\core\powershell\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force
Import-Module (Join-Path $modulesPath 'StateManager\StateManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'MonitoringManager\MonitoringManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'ReportGenerator\ReportGenerator.psm1') -Force

# ---- Initialize ----
if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

$logSession = Start-LogSession -Component 'VMFleet-Pipeline' -LogRootPath (Join-Path $ProjectRoot 'logs\pipeline')

# Default config paths
if (-not $SolutionConfigPath) { $SolutionConfigPath = Join-Path $ProjectRoot 'config\variables\solutions\vmfleet.json' }
if (-not $ClusterConfigPath)  { $ClusterConfigPath  = Join-Path $ProjectRoot 'config\clusters\example-cluster.yml' }

$outputPath = Join-Path $ProjectRoot "reports\$RunId"
$metricsPath = Join-Path $outputPath 'metrics'
$vmfleetScripts = Join-Path $ProjectRoot 'src\solutions\vmfleet\scripts'
$monitoringScripts = Join-Path $ProjectRoot 'src\solutions\vmfleet\monitoring'

Write-Host '=====================================================' -ForegroundColor Cyan
Write-Host '  Azure Local Load Tools - VMFleet Pipeline' -ForegroundColor Cyan
Write-Host "  Run ID: $RunId" -ForegroundColor Cyan
Write-Host '=====================================================' -ForegroundColor Cyan

# Define pipeline phases
$phases = @(
    'PreCheck', 'Install', 'Deploy', 'StartTest',
    'Monitor', 'StopTest', 'Collect', 'Report', 'Cleanup'
)

# Initialize or resume state
$stateDir = Join-Path $ProjectRoot 'state'
if ($Resume) {
    $state = Get-RunState -StateDirectory $stateDir
    if (-not $state) {
        Write-Warning 'No previous state found. Starting fresh.'
        $state = New-RunState -RunId $RunId -Solution 'VMFleet' -Phases $phases -StateDirectory $stateDir
    }
    else {
        Write-Log -Message "Resuming run: $($state.run_id)" -Severity Information
        $RunId = $state.run_id
    }
}
else {
    $state = New-RunState -RunId $RunId -Solution 'VMFleet' -Phases $phases -StateDirectory $stateDir
}

try {
    # Get credentials once
    if (-not $Credential) {
        $Credential = Get-ManagedCredential -CredentialName 'cluster_admin' -ProjectRoot $ProjectRoot
    }

    # Common params for sub-scripts
    $commonParams = @{
        ClusterConfigPath  = $ClusterConfigPath
        ProjectRoot        = $ProjectRoot
        Credential         = $Credential
    }

    # ================================================================
    # Phase 1: PreCheck
    # ================================================================
    if (-not (Test-PhaseCompleted -RunId $RunId -Phase 'PreCheck' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'PreCheck' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: PreCheck ==' -Severity Information

        # Validate config files exist
        if (-not (Test-Path $SolutionConfigPath)) { throw "Solution config not found: $SolutionConfigPath" }
        if (-not (Test-Path $ClusterConfigPath))  { throw "Cluster config not found: $ClusterConfigPath" }

        # Test cluster connectivity
        Import-Module powershell-yaml -ErrorAction Stop
        $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml
        $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }

        $connectivity = Test-ClusterConnectivity -NodeNames $nodes -Credential $Credential
        $unreachable = $connectivity | Where-Object { -not $_.Reachable }
        if ($unreachable.Count -gt 0) {
            throw "Unreachable nodes: $($unreachable.Node -join ', ')"
        }

        Update-RunPhase -RunId $RunId -Phase 'PreCheck' -Status 'Completed' -StateDirectory $stateDir
        Write-Log -Message 'PreCheck passed' -Severity Information
    }

    # ================================================================
    # Phase 2: Install
    # ================================================================
    if (-not $SkipInstall -and -not (Test-PhaseCompleted -RunId $RunId -Phase 'Install' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'Install' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: Install ==' -Severity Information

        & (Join-Path $vmfleetScripts 'Install-VMFleet.ps1') @commonParams -SolutionConfigPath $SolutionConfigPath

        Update-RunPhase -RunId $RunId -Phase 'Install' -Status 'Completed' -StateDirectory $stateDir
    }
    elseif ($SkipInstall) {
        Update-RunPhase -RunId $RunId -Phase 'Install' -Status 'Skipped' -StateDirectory $stateDir
    }

    # ================================================================
    # Phase 3: Deploy
    # ================================================================
    if (-not $SkipDeploy -and -not (Test-PhaseCompleted -RunId $RunId -Phase 'Deploy' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'Deploy' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: Deploy ==' -Severity Information

        & (Join-Path $vmfleetScripts 'Deploy-VMFleet.ps1') @commonParams -SolutionConfigPath $SolutionConfigPath

        Update-RunPhase -RunId $RunId -Phase 'Deploy' -Status 'Completed' -StateDirectory $stateDir
    }
    elseif ($SkipDeploy) {
        Update-RunPhase -RunId $RunId -Phase 'Deploy' -Status 'Skipped' -StateDirectory $stateDir
    }

    # ================================================================
    # Phase 4: Start Test
    # ================================================================
    if (-not (Test-PhaseCompleted -RunId $RunId -Phase 'StartTest' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'StartTest' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: StartTest ==' -Severity Information

        $testParams = @{}
        if ($ProfilePath) { $testParams['ProfilePath'] = $ProfilePath }

        $testMeta = & (Join-Path $vmfleetScripts 'Start-VMFleetTest.ps1') @commonParams -SolutionConfigPath $SolutionConfigPath @testParams

        Update-RunPhase -RunId $RunId -Phase 'StartTest' -Status 'Completed' -StateDirectory $stateDir
    }

    # ================================================================
    # Phase 5: Monitor (runs during test)
    # ================================================================
    if (-not (Test-PhaseCompleted -RunId $RunId -Phase 'Monitor' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'Monitor' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: Monitor ==' -Severity Information

        New-Item -ItemType Directory -Path $metricsPath -Force | Out-Null

        # Load test duration from config
        $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
        $testDuration = [int]$solutionConfig.vmfleet_test_duration
        $warmup = [int]$solutionConfig.vmfleet_warmup_seconds
        $monitorDuration = $testDuration + $warmup + 30  # Extra buffer

        # Start metric collection in parallel
        $storageJob = Start-Job -ScriptBlock {
            param($Script, $Config, $Root, $Cred, $Output, $Duration)
            & $Script -ClusterConfigPath $Config -ProjectRoot $Root -Credential $Cred -OutputPath $Output -DurationSeconds $Duration
        } -ArgumentList @(
            (Join-Path $monitoringScripts 'Collect-StorageMetrics.ps1'),
            $ClusterConfigPath, $ProjectRoot, $Credential,
            (Join-Path $metricsPath 'storage'), $monitorDuration
        )

        $networkJob = Start-Job -ScriptBlock {
            param($Script, $Config, $Root, $Cred, $Output, $Duration)
            & $Script -ClusterConfigPath $Config -ProjectRoot $Root -Credential $Cred -OutputPath $Output -DurationSeconds $Duration
        } -ArgumentList @(
            (Join-Path $monitoringScripts 'Collect-NetworkMetrics.ps1'),
            $ClusterConfigPath, $ProjectRoot, $Credential,
            (Join-Path $metricsPath 'network'), $monitorDuration
        )

        $computeJob = Start-Job -ScriptBlock {
            param($Script, $Config, $Root, $Cred, $Output, $Duration)
            & $Script -ClusterConfigPath $Config -ProjectRoot $Root -Credential $Cred -OutputPath $Output -DurationSeconds $Duration
        } -ArgumentList @(
            (Join-Path $monitoringScripts 'Collect-ComputeMetrics.ps1'),
            $ClusterConfigPath, $ProjectRoot, $Credential,
            (Join-Path $metricsPath 'compute'), $monitorDuration
        )

        Write-Log -Message "Monitoring jobs started. Waiting for test completion (~${monitorDuration}s)..." -Severity Information

        # Wait for test + monitoring to complete
        Wait-WithProgress -Seconds $monitorDuration -Activity 'VMFleet test + monitoring'

        # Collect monitoring job results
        @($storageJob, $networkJob, $computeJob) | ForEach-Object {
            $_ | Wait-Job -Timeout 120 | Out-Null
            Receive-Job -Job $_ -ErrorAction SilentlyContinue
            Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue
        }

        Update-RunPhase -RunId $RunId -Phase 'Monitor' -Status 'Completed' -StateDirectory $stateDir
    }

    # ================================================================
    # Phase 6: Stop Test
    # ================================================================
    if (-not (Test-PhaseCompleted -RunId $RunId -Phase 'StopTest' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'StopTest' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: StopTest ==' -Severity Information

        & (Join-Path $vmfleetScripts 'Stop-VMFleetTest.ps1') @commonParams

        Update-RunPhase -RunId $RunId -Phase 'StopTest' -Status 'Completed' -StateDirectory $stateDir
    }

    # ================================================================
    # Phase 7: Collect Results
    # ================================================================
    if (-not (Test-PhaseCompleted -RunId $RunId -Phase 'Collect' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'Collect' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: Collect ==' -Severity Information

        $collectResult = & (Join-Path $vmfleetScripts 'Collect-VMFleetResults.ps1') @commonParams `
            -SolutionConfigPath $SolutionConfigPath -OutputPath $outputPath -RunId $RunId

        # Optional: push to Azure Monitor
        if ($IncludeAzureMonitor) {
            & (Join-Path $monitoringScripts 'Push-MetricsToAzureMonitor.ps1') `
                -MetricsPath $metricsPath -SolutionConfigPath $SolutionConfigPath -ProjectRoot $ProjectRoot
        }

        Update-RunPhase -RunId $RunId -Phase 'Collect' -Status 'Completed' -StateDirectory $stateDir
    }

    # ================================================================
    # Phase 8: Generate Reports
    # ================================================================
    if (-not (Test-PhaseCompleted -RunId $RunId -Phase 'Report' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'Report' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: Report ==' -Severity Information

        New-TestReport -RunId $RunId -ResultsPath $outputPath -OutputPath $outputPath `
            -Formats $ReportFormats -IncludeMetrics -ClusterConfig $ClusterConfigPath

        # Generate HTML dashboard
        & (Join-Path $monitoringScripts 'Export-MetricsDashboard.ps1') `
            -MetricsPath $metricsPath -OutputPath $outputPath -RunId $RunId -Format 'HTML'

        Update-RunPhase -RunId $RunId -Phase 'Report' -Status 'Completed' -StateDirectory $stateDir
    }

    # ================================================================
    # Phase 9: Cleanup
    # ================================================================
    if (-not $SkipCleanup -and -not (Test-PhaseCompleted -RunId $RunId -Phase 'Cleanup' -StateDirectory $stateDir)) {
        Update-RunPhase -RunId $RunId -Phase 'Cleanup' -Status 'Running' -StateDirectory $stateDir
        Write-Log -Message '== Phase: Cleanup ==' -Severity Information

        & (Join-Path $vmfleetScripts 'Remove-VMFleet.ps1') @commonParams -Force -Confirm:$false

        Update-RunPhase -RunId $RunId -Phase 'Cleanup' -Status 'Completed' -StateDirectory $stateDir
    }
    elseif ($SkipCleanup) {
        Update-RunPhase -RunId $RunId -Phase 'Cleanup' -Status 'Skipped' -StateDirectory $stateDir
    }

    # Mark run complete
    Complete-Run -RunId $RunId -StateDirectory $stateDir

    Write-Host ''
    Write-Host '=====================================================' -ForegroundColor Green
    Write-Host '  VMFleet Pipeline Complete' -ForegroundColor Green
    Write-Host "  Run ID:  $RunId" -ForegroundColor Green
    Write-Host "  Reports: $outputPath" -ForegroundColor Green
    Write-Host '=====================================================' -ForegroundColor Green
}
catch {
    Write-Log -Message "Pipeline failed at phase: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    Write-Host "Pipeline failed. Use -Resume to continue from last checkpoint." -ForegroundColor Red
    throw
}
finally {
    Stop-LogSession
}
