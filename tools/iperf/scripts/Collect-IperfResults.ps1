# =============================================================================
# Collect-IperfResults.ps1 - Azure Local Load Tools
# =============================================================================
# Retrieves iPerf3 JSON output from target nodes via SCP, normalizes metrics
# to the standard throughput/latency schema, and writes aggregate report.
# Phase 2 of the iPerf pipeline.
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

$logSession = Start-LogSession -Component 'Iperf-Collect' -LogRootPath (Join-Path $ProjectRoot 'logs\iperf')

try {
    Write-Log -Message 'Starting iPerf3 results collection' -Severity Information

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\iperf\config\iperf.json'
    }
    if (-not $ClusterConfigPath) {
        $ClusterConfigPath = Join-Path $ProjectRoot 'config\clusters\cluster.yml'
    }

    $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json
    Import-Module powershell-yaml -ErrorAction Stop
    $clusterConfig = Get-Content -Path $ClusterConfigPath -Raw | ConvertFrom-Yaml

    if (-not $OutputPath) {
        $OutputPath = Join-Path $ProjectRoot "logs\iperf\$RunId"
    }
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    $sshUserVal = if ($SshUser) { $SshUser } else { $clusterConfig.cluster.ssh_user }
    $sshKeyVal  = if ($SshKeyPath) { $SshKeyPath } else { $clusterConfig.cluster.ssh_key_path }

    $remoteResultsDir = "/tmp/iperf-results/$RunId"
    $pairData = [System.Collections.Generic.List[hashtable]]::new()

    # Collect results from each non-server node (clients stored results)
    # In mesh mode results are distributed; we retrieve from each node
    foreach ($node in $nodes) {
        $localNodeDir = Join-Path $OutputPath $node
        if (-not (Test-Path $localNodeDir)) {
            New-Item -ItemType Directory -Path $localNodeDir -Force | Out-Null
        }

        Write-Log -Message "Checking for iPerf3 results on $node..." -Severity Information

        $scpArgs = @('-r', '-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
        if ($sshKeyVal) { $scpArgs += '-i', $sshKeyVal }
        $scpArgs += "${sshUserVal}@${node}:${remoteResultsDir}/", $localNodeDir

        $scpOut = & scp @scpArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "No results on $node or SCP failed (may be server-only node)" -Severity Information
            continue
        }

        # Parse each JSON result file
        $jsonFiles = Get-ChildItem -Path $localNodeDir -Filter '*.json' -ErrorAction SilentlyContinue
        foreach ($jsonFile in $jsonFiles) {
            $pairLabel = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

            try {
                $iperfRaw = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json

                $end   = $iperfRaw.end
                $proto = if ($iperfRaw.start.test_start.protocol) { $iperfRaw.start.test_start.protocol } else { 'TCP' }

                if ($proto -eq 'UDP') {
                    $normalized = @{
                        run_id               = $RunId
                        pair                 = $pairLabel
                        protocol             = 'UDP'
                        throughput_mbps      = [math]::Round($end.sum.bits_per_second / 1MB, 2)
                        jitter_ms            = [math]::Round($end.sum.jitter_ms, 3)
                        packet_loss_percent  = [math]::Round($end.sum.lost_percent, 2)
                        packets_sent         = $end.sum.packets
                        packets_lost         = $end.sum.lost_packets
                        duration_seconds     = $end.sum.seconds
                    }
                }
                else {
                    $sendSum  = $end.sum_sent
                    $recvSum  = $end.sum_received
                    $normalized = @{
                        run_id              = $RunId
                        pair                = $pairLabel
                        protocol            = 'TCP'
                        send_throughput_mbps  = [math]::Round($sendSum.bits_per_second / 1MB, 2)
                        recv_throughput_mbps  = [math]::Round($recvSum.bits_per_second / 1MB, 2)
                        retransmits           = $sendSum.retransmits
                        duration_seconds      = $sendSum.seconds
                        streams               = $iperfRaw.start.test_start.num_streams
                    }
                }

                $pairData.Add($normalized)
                Write-Log -Message "Normalized result for pair: $pairLabel" -Severity Information
            }
            catch {
                Write-Log -Message "Failed to parse $($jsonFile.Name): $($_.Exception.Message)" -Severity Warning
            }
        }

        # Clean up remote results
        if ($PSCmdlet.ShouldProcess($node, 'Remove remote iPerf3 result files')) {
            $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
            if ($sshKeyVal) { $sshArgs += '-i', $sshKeyVal }
            $sshArgs += "$sshUserVal@$node", "rm -rf $remoteResultsDir"
            & ssh @sshArgs 2>&1 | Out-Null
        }
    }

    # Aggregate — compute max/min/avg throughput across all pairs
    $tcpPairs = $pairData | Where-Object { $_.protocol -eq 'TCP' }
    $udpPairs = $pairData | Where-Object { $_.protocol -eq 'UDP' }

    $aggregate = @{
        run_id       = $RunId
        timestamp    = Get-Timestamp
        cluster_name = $clusterConfig.cluster.name
        node_count   = $nodes.Count
        pair_count   = $pairData.Count
        profile_name = if ($TestMetadata) { $TestMetadata.Parameters.ProfileName } else { 'unknown' }
    }

    if ($tcpPairs.Count -gt 0) {
        $aggregate['tcp_max_send_throughput_mbps'] = [math]::Round(($tcpPairs | Measure-Object -Property send_throughput_mbps -Maximum).Maximum, 2)
        $aggregate['tcp_min_send_throughput_mbps'] = [math]::Round(($tcpPairs | Measure-Object -Property send_throughput_mbps -Minimum).Minimum, 2)
        $aggregate['tcp_avg_send_throughput_mbps'] = [math]::Round(($tcpPairs | Measure-Object -Property send_throughput_mbps -Average).Average, 2)
        $aggregate['tcp_total_retransmits']        = ($tcpPairs | Measure-Object -Property retransmits -Sum).Sum
    }

    if ($udpPairs.Count -gt 0) {
        $aggregate['udp_avg_throughput_mbps']     = [math]::Round(($udpPairs | Measure-Object -Property throughput_mbps -Average).Average, 2)
        $aggregate['udp_avg_jitter_ms']           = [math]::Round(($udpPairs | Measure-Object -Property jitter_ms -Average).Average, 3)
        $aggregate['udp_max_packet_loss_percent'] = [math]::Round(($udpPairs | Measure-Object -Property packet_loss_percent -Maximum).Maximum, 2)
    }

    if ($TestMetadata) {
        $aggregate['test_parameters'] = $TestMetadata.Parameters
    }

    # Write output files
    $aggregateFile = Join-Path $OutputPath "$RunId-aggregate.json"
    $aggregate | ConvertTo-Json -Depth 5 | Set-Content -Path $aggregateFile -Encoding UTF8
    Write-Log -Message "Aggregate results written: $aggregateFile" -Severity Information

    $perPairFile = Join-Path $OutputPath "$RunId-per-pair.json"
    $pairData | ConvertTo-Json -Depth 5 | Set-Content -Path $perPairFile -Encoding UTF8
    Write-Log -Message "Per-pair results written: $perPairFile" -Severity Information

    # Print summary
    Write-Host "`n===== iPerf3 Results Summary =====" -ForegroundColor Cyan
    Write-Host "  Run ID:      $RunId"
    Write-Host "  Pairs:       $($pairData.Count)"
    if ($tcpPairs.Count -gt 0) {
        Write-Host "  TCP Max Throughput: $($aggregate.tcp_max_send_throughput_mbps) MB/s"
        Write-Host "  TCP Avg Throughput: $($aggregate.tcp_avg_send_throughput_mbps) MB/s"
        Write-Host "  TCP Retransmits:    $($aggregate.tcp_total_retransmits)"
    }
    if ($udpPairs.Count -gt 0) {
        Write-Host "  UDP Avg Throughput: $($aggregate.udp_avg_throughput_mbps) MB/s"
        Write-Host "  UDP Avg Jitter:     $($aggregate.udp_avg_jitter_ms) ms"
        Write-Host "  UDP Max Packet Loss: $($aggregate.udp_max_packet_loss_percent)%"
    }
    Write-Host "==================================" -ForegroundColor Cyan

    Write-Log -Message 'iPerf3 results collection completed' -Severity Information

    return @{
        RunId      = $RunId
        OutputPath = $OutputPath
        Aggregate  = $aggregate
        PairData   = $pairData
    }
}
catch {
    Write-Log -Message "Collection failed: $($_.Exception.Message)" -Severity Error -ErrorRecord $_
    throw
}
finally {
    Stop-LogSession
}
