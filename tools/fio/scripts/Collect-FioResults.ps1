# =============================================================================
# Collect-FioResults.ps1 - Azure Local Load Tools
# =============================================================================
# Retrieves fio JSON output from target nodes via SCP, normalizes metrics to
# the standard IOPS/latency/throughput schema, and writes aggregate report.
# Phase 3 of the fio pipeline.
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
    [string]$SshUser,

    [Parameter()]
    [string]$SshKeyPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter(Mandatory)]
    [string]$RunId,

    [Parameter()]
    [hashtable]$TestMetadata
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

. (Join-Path $ProjectRoot 'common\helpers\Common-Functions.ps1')
$modulesPath = Join-Path $ProjectRoot 'common\modules'
Import-Module (Join-Path $modulesPath 'ConfigManager\ConfigManager.psm1') -Force
Import-Module (Join-Path $modulesPath 'Logger\Logger.psm1') -Force

$logSession = Start-LogSession -Component 'Fio-Collect' -LogRootPath (Join-Path $ProjectRoot 'logs\fio')

try {
    Write-Log -Message 'Starting fio results collection' -Severity Information

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\fio\config\fio.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    if (-not $OutputPath) {
        $OutputPath = Join-Path $ProjectRoot "logs\fio\$RunId"
    }
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $nodes = $clusterConfig.nodes | Where-Object { $_.role -eq 'worker' -or -not $_.role } | ForEach-Object { $_.name }
    if ($nodes.Count -eq 0) {
        $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    }

    $sshUserVal = if ($SshUser) { $SshUser } else { $clusterConfig.cluster.ssh_user }
    $sshKeyVal  = if ($SshKeyPath) { $SshKeyPath } else { $clusterConfig.cluster.ssh_key_path }

    $remoteResultsDir = "/tmp/fio-results/$RunId"
    $nodeData = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($node in $nodes) {
        $localNodeDir = Join-Path $OutputPath $node
        if (-not (Test-Path $localNodeDir)) {
            New-Item -ItemType Directory -Path $localNodeDir -Force | Out-Null
        }

        Write-Log -Message "Retrieving fio results from $node..." -Severity Information

        $scpArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
        if ($sshKeyVal) { $scpArgs += '-i', $sshKeyVal }
        $scpArgs += "${sshUserVal}@${node}:${remoteResultsDir}/fio-results.json", $localNodeDir

        $scpOut = & scp @scpArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "SCP failed for ${node}: $scpOut" -Severity Warning
            continue
        }

        $localResultFile = Join-Path $localNodeDir 'fio-results.json'
        if (-not (Test-Path $localResultFile)) {
            Write-Log -Message "Result file not found for $node after SCP" -Severity Warning
            continue
        }

        # Parse fio JSON output and normalize
        $fioRaw = Get-Content -Path $localResultFile -Raw | ConvertFrom-Json

        foreach ($job in $fioRaw.jobs) {
            $readResult  = $job.read
            $writeResult = $job.write

            $normalized = @{
                cluster_name          = $clusterConfig.cluster.name
                node                  = $node
                run_id                = $RunId
                job_name              = $job.jobname
                # IOPS
                read_iops             = [math]::Round($readResult.iops, 0)
                write_iops            = [math]::Round($writeResult.iops, 0)
                total_iops            = [math]::Round($readResult.iops + $writeResult.iops, 0)
                # Throughput (MB/s)
                read_throughput_mbps  = [math]::Round($readResult.bw_bytes / 1MB, 2)
                write_throughput_mbps = [math]::Round($writeResult.bw_bytes / 1MB, 2)
                # Latency (ms) — fio reports in nanoseconds
                read_lat_mean_ms      = [math]::Round($readResult.lat_ns.mean / 1e6, 3)
                read_lat_p99_ms       = [math]::Round($readResult.lat_ns.percentile.'99.000000' / 1e6, 3)
                write_lat_mean_ms     = [math]::Round($writeResult.lat_ns.mean / 1e6, 3)
                write_lat_p99_ms      = [math]::Round($writeResult.lat_ns.percentile.'99.000000' / 1e6, 3)
                avg_lat_ms            = [math]::Round(($readResult.lat_ns.mean + $writeResult.lat_ns.mean) / 2e6, 3)
                # Errors
                read_errors           = $readResult.total_ios - $readResult.io_kbytes / ($job.global_options.bs -replace '[^0-9]', '' -as [int]) * 1
                io_errors             = ($job.error ?? 0)
            }

            $nodeData.Add($normalized)
        }

        Write-Log -Message "Normalized $($fioRaw.jobs.Count) job(s) from $node" -Severity Information

        # Clean up remote results
        if ($PSCmdlet.ShouldProcess($node, 'Remove remote fio result files')) {
            $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
            if ($sshKeyVal) { $sshArgs += '-i', $sshKeyVal }
            $sshArgs += "$sshUserVal@$node", "rm -rf $remoteResultsDir"
            & ssh @sshArgs 2>&1 | Out-Null
        }
    }

    # Aggregate across all nodes
    $aggregate = @{
        run_id                     = $RunId
        timestamp                  = Get-Timestamp
        cluster_name               = $clusterConfig.cluster.name
        node_count                 = $nodes.Count
        profile_name               = if ($TestMetadata) { $TestMetadata.Parameters.ProfileName } else { 'unknown' }
        total_read_iops            = ($nodeData | Measure-Object -Property read_iops -Sum).Sum
        total_write_iops           = ($nodeData | Measure-Object -Property write_iops -Sum).Sum
        total_iops                 = ($nodeData | Measure-Object -Property total_iops -Sum).Sum
        total_read_throughput_mbps = [math]::Round(($nodeData | Measure-Object -Property read_throughput_mbps -Sum).Sum, 2)
        total_write_throughput_mbps = [math]::Round(($nodeData | Measure-Object -Property write_throughput_mbps -Sum).Sum, 2)
        avg_read_lat_mean_ms       = [math]::Round(($nodeData | Measure-Object -Property read_lat_mean_ms -Average).Average, 3)
        avg_write_lat_mean_ms      = [math]::Round(($nodeData | Measure-Object -Property write_lat_mean_ms -Average).Average, 3)
        avg_lat_ms                 = [math]::Round(($nodeData | Measure-Object -Property avg_lat_ms -Average).Average, 3)
        p99_read_lat_ms            = [math]::Round(($nodeData | Measure-Object -Property read_lat_p99_ms -Maximum).Maximum, 3)
        p99_write_lat_ms           = [math]::Round(($nodeData | Measure-Object -Property write_lat_p99_ms -Maximum).Maximum, 3)
    }

    if ($TestMetadata) {
        $aggregate['test_parameters'] = $TestMetadata.Parameters
    }

    # Write output files
    $aggregateFile = Join-Path $OutputPath "$RunId-aggregate.json"
    $aggregate | ConvertTo-Json -Depth 5 | Set-Content -Path $aggregateFile -Encoding UTF8
    Write-Log -Message "Aggregate results written: $aggregateFile" -Severity Information

    $perJobFile = Join-Path $OutputPath "$RunId-per-job.json"
    $nodeData | ConvertTo-Json -Depth 5 | Set-Content -Path $perJobFile -Encoding UTF8
    Write-Log -Message "Per-job results written: $perJobFile" -Severity Information

    # Print summary
    Write-Host "`n===== fio Results Summary =====" -ForegroundColor Cyan
    Write-Host "  Run ID:              $RunId"
    Write-Host "  Nodes:               $($nodes.Count)"
    Write-Host "  Total IOPS:          $($aggregate.total_iops)"
    Write-Host "  Read IOPS:           $($aggregate.total_read_iops)"
    Write-Host "  Write IOPS:          $($aggregate.total_write_iops)"
    Write-Host "  Avg Latency:         $($aggregate.avg_lat_ms) ms"
    Write-Host "  P99 Read Latency:    $($aggregate.p99_read_lat_ms) ms"
    Write-Host "  P99 Write Latency:   $($aggregate.p99_write_lat_ms) ms"
    Write-Host "  Read Throughput:     $($aggregate.total_read_throughput_mbps) MB/s"
    Write-Host "  Write Throughput:    $($aggregate.total_write_throughput_mbps) MB/s"
    Write-Host "===============================" -ForegroundColor Cyan

    Write-Log -Message 'fio results collection completed' -Severity Information

    return @{
        RunId      = $RunId
        OutputPath = $OutputPath
        Aggregate  = $aggregate
        JobData    = $nodeData
    }
}
catch {
    Write-Log -Message "Collection failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
