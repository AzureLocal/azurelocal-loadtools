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

    # Account the fleet VMs are created with; required for the Deploy phase (no default password exists).
    [Parameter()]
    [PSCredential]$FleetAdminCredential,

    # Account the fleet VMs use to reach the Collect volume (an admin on every node). Default: -Credential.
    [Parameter()]
    [PSCredential]$FleetConnectCredential,

    [Parameter()]
    [string]$RunId,

    # Fleet VMs per node; default vm_count_per_node in the solution config.
    [Parameter()]
    [int]$VMCount,

    # Path ON THE NODE of the base VHD(X); default storage.base_vhd_path in the cluster YAML.
    [Parameter()]
    [string]$BaseVHDPath,

    # VMFleet module version; default vmfleet_version in the solution config.
    [Parameter()]
    [string]$VMFleetVersion,

    # HTML (and CSV) needs nothing extra. PDF needs asciidoctor-pdf, DOCX needs asciidoctor and pandoc,
    # XLSX needs the ImportExcel module: a format whose tool is missing is skipped with a warning.
    [Parameter()]
    [ValidateSet('HTML', 'PDF', 'DOCX', 'XLSX')]
    [string[]]$ReportFormats = @('HTML'),

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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

# ---- Bootstrap ----
. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
. (Join-Path $PSScriptRoot 'scripts\VMFleet-Common.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force
Import-Module (Join-Path $modulesPath 'StateManager\StateManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'CredentialManager\CredentialManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'MonitoringManager\MonitoringManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'ReportGenerator\ReportGenerator.psm1') -Force

# ---- Initialize ----
if (-not $RunId) { $RunId = "vmfleet-$(Get-Timestamp -FilenameSafe)" }

$null = Start-LogSession -Component 'VMFleet-Pipeline' -LogRootPath (Join-Path $ProjectRoot 'logs\pipeline')

# Default config paths
if (-not $SolutionConfigPath) { $SolutionConfigPath = Join-Path $ProjectRoot 'tools\vmfleet\config\vmfleet.json' }
if (-not $ClusterConfigPath) { $ClusterConfigPath = Get-VMFleetDefaultClusterConfigPath -ProjectRoot $ProjectRoot }

$outputPath = Join-Path $ProjectRoot "reports\$RunId"
$metricsPath = Join-Path $outputPath 'metrics'
$vmfleetScripts = Join-Path $ProjectRoot 'tools\vmfleet\scripts'
$monitoringScripts = Join-Path $ProjectRoot 'tools\vmfleet\monitoring'

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
if ($Resume) {
    $state = Get-RunState
    if (-not $state) {
        Write-Warning 'No previous state found. Starting fresh.'
        $state = New-RunState -RunId $RunId -Solution 'VMFleet' -Phases $phases
    } else {
        Write-Log -Message "Resuming run: $($state.run_id)" -Severity Information
        $RunId = $state.run_id
    }
} else {
    $state = New-RunState -RunId $RunId -Solution 'VMFleet' -Phases $phases
}

# -Resume may switch to the run id of the saved state: the report folder follows it.
$outputPath = Join-Path $ProjectRoot "reports\$RunId"
$metricsPath = Join-Path $outputPath 'metrics'

try {
    # Get credentials once
    if (-not $Credential) {
        # No prompt: -Credential, CLUSTER_ADMIN_USERNAME/CLUSTER_ADMIN_PASSWORD or the Key Vault mapping; otherwise stop (exit 2).
        try {
            $Credential = Get-ManagedCredential -Name 'cluster_admin' -ProjectRoot $ProjectRoot
        } catch {
            Write-Log -Message $_.Exception.Message -Severity Error
            exit 2
        }
    }

    # Common params for sub-scripts
    $commonParams = @{
        ClusterConfigPath  = $ClusterConfigPath
        ProjectRoot        = $ProjectRoot
        Credential         = $Credential
        RunId              = $RunId
    }

    # The cluster (nodes by management IP, Collect volume) and the test parameters are needed by several phases
    # and on -Resume, so they are read once here.
    $cluster = Get-VMFleetClusterConfig -ClusterConfigPath $ClusterConfigPath
    $testMetadata = $null

    # ================================================================
    # Phase 1: PreCheck
    # ================================================================
    if (-not (Test-PhaseCompleted -Phase 'PreCheck')) {
        Update-RunPhase -Phase 'PreCheck' -Status 'Running'
        Write-Log -Message '== Phase: PreCheck ==' -Severity Information

        # Validate config files exist
        if (-not (Test-Path $SolutionConfigPath)) { throw "Solution config not found: $SolutionConfigPath" }

        # Test cluster connectivity (the nodes are reached by management IP with the explicit credential)
        $connectivity = Test-ClusterConnectivity -NodeNames $cluster.Nodes -Credential $Credential
        $unreachable = @($connectivity | Where-Object { -not $_.Reachable })
        if ($unreachable.Count -gt 0) {
            throw "Unreachable nodes: $($unreachable.Node -join ', ')"
        }

        Update-RunPhase -Phase 'PreCheck' -Status 'Completed'
        Write-Log -Message 'PreCheck passed' -Severity Information
    }

    # ================================================================
    # Phase 2: Install
    # ================================================================
    if (-not $SkipInstall -and -not (Test-PhaseCompleted -Phase 'Install')) {
        Update-RunPhase -Phase 'Install' -Status 'Running'
        Write-Log -Message '== Phase: Install ==' -Severity Information

        $installParams = @{}
        if ($VMFleetVersion) { $installParams['VMFleetVersion'] = $VMFleetVersion }
        & (Join-Path $vmfleetScripts 'Install-VMFleet.ps1') @commonParams -SolutionConfigPath $SolutionConfigPath @installParams

        Update-RunPhase -Phase 'Install' -Status 'Completed'
    } elseif ($SkipInstall) {
        Update-RunPhase -Phase 'Install' -Status 'Skipped'
    }

    # ================================================================
    # Phase 3: Deploy
    # ================================================================
    if (-not $SkipDeploy -and -not (Test-PhaseCompleted -Phase 'Deploy')) {
        Update-RunPhase -Phase 'Deploy' -Status 'Running'
        Write-Log -Message '== Phase: Deploy ==' -Severity Information

        if (-not $FleetAdminCredential) {
            throw 'FleetAdminCredential is required for the Deploy phase: supply the local administrator account the fleet VMs are created with (or use -SkipDeploy when the fleet already exists).'
        }
        $deployParams = @{ FleetAdminCredential = $FleetAdminCredential }
        if ($FleetConnectCredential) { $deployParams['FleetConnectCredential'] = $FleetConnectCredential }
        if ($VMCount) { $deployParams['VMCount'] = $VMCount }
        if ($BaseVHDPath) { $deployParams['BaseVHDPath'] = $BaseVHDPath }
        & (Join-Path $vmfleetScripts 'Deploy-VMFleet.ps1') @commonParams -SolutionConfigPath $SolutionConfigPath @deployParams

        Update-RunPhase -Phase 'Deploy' -Status 'Completed'
    } elseif ($SkipDeploy) {
        Update-RunPhase -Phase 'Deploy' -Status 'Skipped'
    }

    # ================================================================
    # Phase 4: Start Test
    # ================================================================
    if (-not (Test-PhaseCompleted -Phase 'StartTest')) {
        Update-RunPhase -Phase 'StartTest' -Status 'Running'
        Write-Log -Message '== Phase: StartTest ==' -Severity Information

        $testParams = @{}
        if ($ProfilePath) { $testParams['ProfilePath'] = $ProfilePath }

        # -NoWait: Start-FleetSweep blocks on the node until the run is over; the Monitor phase waits for it
        # while the metric collectors run.
        $testMetadata = & (Join-Path $vmfleetScripts 'Start-VMFleetTest.ps1') @commonParams -SolutionConfigPath $SolutionConfigPath @testParams -NoWait

        Update-RunPhase -Phase 'StartTest' -Status 'Completed'
    }

    # ================================================================
    # Phase 5: Monitor (runs during test)
    # ================================================================
    if (-not (Test-PhaseCompleted -Phase 'Monitor')) {
        Update-RunPhase -Phase 'Monitor' -Status 'Running'
        Write-Log -Message '== Phase: Monitor ==' -Severity Information

        New-Item -ItemType Directory -Path $metricsPath -Force | Out-Null

        # The same resolution Start-VMFleetTest.ps1 used: profile (profile.parameters) > solution config.
        $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
        $testPlan = Resolve-VMFleetTestParameters -LoadProfile (Import-VMFleetProfile -ProfilePath $ProfilePath) -SolutionConfig $solutionConfig
        # Measured time + warm-up + cool-down, plus about two minutes for the sweep's own start-up and CSV move.
        $monitorDuration = $testPlan.TotalSeconds + 120

        # Start metric collection in parallel
        $storageJob = Start-Job -ScriptBlock {
            param($Script, $Config, $Root, $RunAs, $Output, $Duration)
            & $Script -ClusterConfigPath $Config -ProjectRoot $Root -Credential $RunAs -OutputPath $Output -DurationSeconds $Duration
        } -ArgumentList @(
            (Join-Path $monitoringScripts 'Collect-StorageMetrics.ps1'),
            $ClusterConfigPath, $ProjectRoot, $Credential,
            (Join-Path $metricsPath 'storage'), $monitorDuration
        )

        $networkJob = Start-Job -ScriptBlock {
            param($Script, $Config, $Root, $RunAs, $Output, $Duration)
            & $Script -ClusterConfigPath $Config -ProjectRoot $Root -Credential $RunAs -OutputPath $Output -DurationSeconds $Duration
        } -ArgumentList @(
            (Join-Path $monitoringScripts 'Collect-NetworkMetrics.ps1'),
            $ClusterConfigPath, $ProjectRoot, $Credential,
            (Join-Path $metricsPath 'network'), $monitorDuration
        )

        $computeJob = Start-Job -ScriptBlock {
            param($Script, $Config, $Root, $RunAs, $Output, $Duration)
            & $Script -ClusterConfigPath $Config -ProjectRoot $Root -Credential $RunAs -OutputPath $Output -DurationSeconds $Duration
        } -ArgumentList @(
            (Join-Path $monitoringScripts 'Collect-ComputeMetrics.ps1'),
            $ClusterConfigPath, $ProjectRoot, $Credential,
            (Join-Path $metricsPath 'compute'), $monitorDuration
        )

        Write-Log -Message "Monitoring jobs started. Waiting for the DiskSpd sweep on the node (~${monitorDuration}s)..." -Severity Information

        try {
            # Wait for the sweep itself: its node task ends when the load is over (or fails), so a run of any
            # profile length is covered, not a fixed number of seconds.
            $sweepHandle = if ($testMetadata -is [hashtable] -and $testMetadata.ContainsKey('TaskHandle') -and $testMetadata['TaskHandle']) {
                $testMetadata['TaskHandle']
            } else {
                Get-VMFleetNodeTaskHandle -ComputerName $cluster.PrimaryNode -RunId $RunId -Step 'Test' -CollectPath $cluster.CollectPath
            }
            $null = Wait-VMFleetNodeTask -Handle $sweepHandle -Credential $Credential -TimeoutSeconds ($testPlan.TotalSeconds + 1800)
        } finally {
            # Collect monitoring job results (also when the sweep failed: do not leave jobs running)
            @($storageJob, $networkJob, $computeJob) | ForEach-Object {
                $_ | Wait-Job -Timeout 120 | Out-Null
                Receive-Job -Job $_ -ErrorAction SilentlyContinue
                Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue
            }
        }

        Update-RunPhase -Phase 'Monitor' -Status 'Completed'
    }

    # ================================================================
    # Phase 6: Stop Test
    # ================================================================
    if (-not (Test-PhaseCompleted -Phase 'StopTest')) {
        Update-RunPhase -Phase 'StopTest' -Status 'Running'
        Write-Log -Message '== Phase: StopTest ==' -Severity Information

        & (Join-Path $vmfleetScripts 'Stop-VMFleetTest.ps1') @commonParams

        Update-RunPhase -Phase 'StopTest' -Status 'Completed'
    }

    # ================================================================
    # Phase 7: Collect Results
    # ================================================================
    if (-not (Test-PhaseCompleted -Phase 'Collect')) {
        Update-RunPhase -Phase 'Collect' -Status 'Running'
        Write-Log -Message '== Phase: Collect ==' -Severity Information

        $collectParams = @{}
        if ($testMetadata -is [hashtable]) { $collectParams['TestMetadata'] = $testMetadata }
        $null = & (Join-Path $vmfleetScripts 'Collect-VMFleetResults.ps1') @commonParams `
            -SolutionConfigPath $SolutionConfigPath -OutputPath $outputPath @collectParams

        # Optional: push to Azure Monitor
        if ($IncludeAzureMonitor) {
            & (Join-Path $monitoringScripts 'Push-MetricsToAzureMonitor.ps1') `
                -MetricsPath $metricsPath -SolutionConfigPath $SolutionConfigPath -ProjectRoot $ProjectRoot
        }

        Update-RunPhase -Phase 'Collect' -Status 'Completed'
    }

    # ================================================================
    # Phase 8: Generate Reports
    # ================================================================
    if (-not (Test-PhaseCompleted -Phase 'Report')) {
        Update-RunPhase -Phase 'Report' -Status 'Running'
        Write-Log -Message '== Phase: Report ==' -Severity Information

        # HTML (+ CSV) is the offline report and needs no extra tool. PDF, DOCX and XLSX need external tools:
        # a format whose tool is missing is skipped with a warning instead of failing the run.
        $toolFormats = @()
        foreach ($format in $ReportFormats) {
            if ($format -eq 'HTML') {
                & (Join-Path $vmfleetScripts 'New-VMFleetReport.ps1') -ResultPath (Join-Path $outputPath "$RunId-aggregate.json") `
                    -OutputPath $outputPath -ProjectRoot $ProjectRoot
                continue
            }
            $support = Get-VMFleetReportFormatSupport -Format $format
            if ($support.Available) {
                $toolFormats += $format
            } else {
                Write-Log -Message "Skipping the $format report: $($support.Reason)" -Severity Warning
            }
        }
        if ($toolFormats.Count -gt 0) {
            New-TestReport -RunId $RunId -ResultsPath $outputPath -OutputPath $outputPath `
                -Formats $toolFormats -IncludeMetrics -ClusterConfig $ClusterConfigPath
        }

        # Generate HTML dashboard (best effort: a dashboard problem must not fail a finished run)
        try {
            & (Join-Path $monitoringScripts 'Export-MetricsDashboard.ps1') `
                -MetricsPath $metricsPath -OutputPath $outputPath -RunId $RunId -Format 'HTML'
        } catch {
            Write-Log -Message "Metrics dashboard was not generated: $($_.Exception.Message)" -Severity Warning
        }

        Update-RunPhase -Phase 'Report' -Status 'Completed'
    }

    # ================================================================
    # Phase 9: Cleanup
    # ================================================================
    if (-not $SkipCleanup -and -not (Test-PhaseCompleted -Phase 'Cleanup')) {
        Update-RunPhase -Phase 'Cleanup' -Status 'Running'
        Write-Log -Message '== Phase: Cleanup ==' -Severity Information

        & (Join-Path $vmfleetScripts 'Remove-VMFleet.ps1') @commonParams -Force -Confirm:$false

        Update-RunPhase -Phase 'Cleanup' -Status 'Completed'
    } elseif ($SkipCleanup) {
        Update-RunPhase -Phase 'Cleanup' -Status 'Skipped'
    }

    # Mark run complete
    Complete-Run

    Write-Host ''
    Write-Host '=====================================================' -ForegroundColor Green
    Write-Host '  VMFleet Pipeline Complete' -ForegroundColor Green
    Write-Host "  Run ID:  $RunId" -ForegroundColor Green
    Write-Host "  Reports: $outputPath" -ForegroundColor Green
    Write-Host '=====================================================' -ForegroundColor Green
} catch {
    Write-Log -Message "Pipeline failed at phase: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    Write-Host "Pipeline failed. Use -Resume to continue from last checkpoint." -ForegroundColor Red
    throw
} finally {
    Stop-LogSession
}
