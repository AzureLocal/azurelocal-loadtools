# =============================================================================
# Collect-StressNgResults.ps1 - Azure Local Load Tools
# =============================================================================
# Retrieves stress-ng YAML metric output from target nodes via SCP, normalizes
# per-stressor bogo-ops and bogo-ops/s metrics, and writes aggregate results.
# Phase 2 of the stress-ng pipeline.
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

$logSession = Start-LogSession -Component 'StressNg-Collect' -LogRootPath (Join-Path $ProjectRoot 'logs\stress-ng')

try {
    Write-Log -Message 'Starting stress-ng results collection' -Severity Information

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\stress-ng\config\stress-ng.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    if (-not $OutputPath) {
        $OutputPath = Join-Path $ProjectRoot "logs\stress-ng\$RunId"
    }
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    $sshUserVal = if ($SshUser) { $SshUser } else { $clusterConfig.cluster.ssh_user }
    $sshKeyVal  = if ($SshKeyPath) { $SshKeyPath } else { $clusterConfig.cluster.ssh_key_path }

    $remoteResultsDir = "/tmp/stress-ng-results/$RunId"
    $allNodeData = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($node in $nodes) {
        $localNodeDir = Join-Path $OutputPath $node
        if (-not (Test-Path $localNodeDir)) {
            New-Item -ItemType Directory -Path $localNodeDir -Force | Out-Null
        }

        Write-Log -Message "Retrieving stress-ng results from $node..." -Severity Information

        $scpArgs = @('-r', '-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
        if ($sshKeyVal) { $scpArgs += '-i', $sshKeyVal }
        $scpArgs += "${sshUserVal}@${node}:${remoteResultsDir}/", $localNodeDir

        $scpOut = & scp @scpArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "SCP failed for ${node}: $scpOut" -Severity Warning
            continue
        }

        $yamlResultFile = Join-Path $localNodeDir 'stress-ng-results.yml'
        if (-not (Test-Path $yamlResultFile)) {
            Write-Log -Message "Result YAML not found for $node" -Severity Warning
            continue
        }

        # Parse stress-ng YAML output
        $stressData = Get-Content -Path $yamlResultFile -Raw | ConvertFrom-Yaml

        # stress-ng YAML schema: stress-ng.metrics[] with stressor, bogo-ops, bogo-ops-per-second-usr-sys-time
        $metrics = $stressData.'stress-ng'.metrics
        foreach ($metric in $metrics) {
            $normalized = @{
                run_id              = $RunId
                node                = $node
                stressor            = $metric.stressor
                bogo_ops            = $metric.'bogo-ops'
                bogo_ops_per_sec    = [math]::Round($metric.'bogo-ops-per-second-usr-sys-time', 2)
                real_time_seconds   = [math]::Round($metric.'real-time', 2)
                usr_time_seconds    = [math]::Round($metric.'usr-time', 2)
                sys_time_seconds    = [math]::Round($metric.'sys-time', 2)
            }
            $allNodeData.Add($normalized)
        }

        Write-Log -Message "Normalized $($metrics.Count) stressor result(s) from $node" -Severity Information

        # Clean up remote results
        if ($PSCmdlet.ShouldProcess($node, 'Remove remote stress-ng result files')) {
            $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
            if ($sshKeyVal) { $sshArgs += '-i', $sshKeyVal }
            $sshArgs += "$sshUserVal@$node", "rm -rf $remoteResultsDir"
            & ssh @sshArgs 2>&1 | Out-Null
        }
    }

    # Aggregate per stressor across all nodes
    $stressorSummary = $allNodeData | Group-Object -Property stressor | ForEach-Object {
        $grp = $_
        @{
            stressor           = $grp.Name
            avg_bogo_ops_per_sec = [math]::Round(($grp.Group | Measure-Object -Property bogo_ops_per_sec -Average).Average, 2)
            total_bogo_ops       = ($grp.Group | Measure-Object -Property bogo_ops -Sum).Sum
            node_count           = $grp.Group.Count
        }
    }

    $aggregate = @{
        run_id         = $RunId
        timestamp      = Get-Timestamp
        cluster_name   = $clusterConfig.cluster.name
        node_count     = $nodes.Count
        profile_name   = if ($TestMetadata) { $TestMetadata.Parameters.ProfileName } else { 'unknown' }
        stressors      = if ($TestMetadata) { $TestMetadata.Parameters.Stressors } else { $solutionConfig.stress_ng_stressors }
        workers        = if ($TestMetadata) { $TestMetadata.Parameters.Workers } else { $solutionConfig.stress_ng_workers }
        timeout        = if ($TestMetadata) { $TestMetadata.Parameters.Timeout } else { $solutionConfig.stress_ng_timeout }
        stressor_summary = $stressorSummary
    }

    if ($TestMetadata) {
        $aggregate['test_parameters'] = $TestMetadata.Parameters
    }

    # Write output files
    $aggregateFile = Join-Path $OutputPath "$RunId-aggregate.json"
    $aggregate | ConvertTo-Json -Depth 7 | Set-Content -Path $aggregateFile -Encoding UTF8
    Write-Log -Message "Aggregate results written: $aggregateFile" -Severity Information

    $perNodeFile = Join-Path $OutputPath "$RunId-per-node.json"
    $allNodeData | ConvertTo-Json -Depth 5 | Set-Content -Path $perNodeFile -Encoding UTF8
    Write-Log -Message "Per-node results written: $perNodeFile" -Severity Information

    # Print summary
    Write-Host "`n===== stress-ng Results Summary =====" -ForegroundColor Cyan
    Write-Host "  Run ID:     $RunId"
    Write-Host "  Nodes:      $($nodes.Count)"
    foreach ($s in $stressorSummary) {
        Write-Host "  [$($s.stressor)] Avg bogo-ops/s: $($s.avg_bogo_ops_per_sec) | Total bogo-ops: $($s.total_bogo_ops)"
    }
    Write-Host "=====================================" -ForegroundColor Cyan

    Write-Log -Message 'stress-ng results collection completed' -Severity Information

    return @{
        RunId      = $RunId
        OutputPath = $OutputPath
        Aggregate  = $aggregate
        NodeData   = $allNodeData
    }
}
catch {
    Write-Log -Message "Collection failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
