# =============================================================================
# Start-IperfTest.ps1 - Azure Local Load Tools
# =============================================================================
# Orchestrates iPerf3 network throughput and latency tests across cluster nodes.
# Starts an iPerf3 server on one node and runs client connections from others.
# Supports mesh testing (all-to-all node pairs).
# Phase 1 of the iPerf pipeline.
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
    [string]$SshUser,

    [Parameter()]
    [string]$SshKeyPath,

    [Parameter()]
    [ValidateSet('TCP', 'UDP')]
    [string]$Protocol,

    [Parameter()]
    [int]$ParallelStreams,

    [Parameter()]
    [int]$DurationSeconds,

    [Parameter()]
    [int]$Port,

    [Parameter()]
    [switch]$MeshTest,

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

$logSession = Start-LogSession -Component 'Iperf-Test' -LogRootPath (Join-Path $ProjectRoot 'logs\iperf')

try {
    Write-Log -Message 'Starting iPerf3 test phase' -Severity Information

    if (-not $RunId) { $RunId = "iperf-$(Get-Timestamp -FilenameSafe)" }

    if (-not $SolutionConfigPath) {
        $SolutionConfigPath = Join-Path $ProjectRoot 'tools\iperf\config\iperf.json'
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
    $protocolVal  = if ($Protocol)         { $Protocol }         elseif ($profile) { $profile.profile.parameters.protocol }          else { $solutionConfig.iperf_protocol }
    $streamsVal   = if ($ParallelStreams)   { $ParallelStreams }   elseif ($profile) { $profile.profile.parameters.parallel_streams }  else { [int]$solutionConfig.iperf_parallel_streams }
    $durationVal  = if ($DurationSeconds)  { $DurationSeconds }  elseif ($profile) { $profile.profile.parameters.duration_seconds }  else { [int]$solutionConfig.iperf_duration_seconds }
    $portVal      = if ($Port)             { $Port }             elseif ($profile) { $profile.profile.parameters.server_port }       else { [int]$solutionConfig.iperf_server_port }
    $meshVal      = if ($MeshTest)         { $true }             elseif ($profile) { $profile.profile.parameters.mesh_test -eq $true } else { $false }
    $bandwidthUdp = if ($profile)          { $profile.profile.parameters.udp_bandwidth_mbps }  else { $null }

    $nodes = $clusterConfig.nodes | ForEach-Object { $_.name }
    if ($nodes.Count -lt 2) {
        throw "iPerf3 requires at least 2 nodes. Found: $($nodes.Count)"
    }

    $sshUserVal = if ($SshUser) { $SshUser } else { $clusterConfig.cluster.ssh_user }
    $sshKeyVal  = if ($SshKeyPath) { $SshKeyPath } else { $clusterConfig.cluster.ssh_key_path }

    Write-Log -Message "Protocol: $protocolVal | Streams: $streamsVal | Duration: ${durationVal}s | Port: $portVal | Mesh: $meshVal" -Severity Information
    Write-Log -Message "Nodes: $($nodes -join ', ')" -Severity Information

    $remoteResultsDir = "/tmp/iperf-results/$RunId"
    $pairResults = [System.Collections.Generic.List[hashtable]]::new()

    # Build node pairs for testing
    $nodePairs = [System.Collections.Generic.List[hashtable]]::new()
    if ($meshVal) {
        # All-to-all pairs
        for ($i = 0; $i -lt $nodes.Count; $i++) {
            for ($j = 0; $j -lt $nodes.Count; $j++) {
                if ($i -ne $j) {
                    $nodePairs.Add(@{ Server = $nodes[$i]; Client = $nodes[$j] })
                }
            }
        }
        Write-Log -Message "Mesh mode: $($nodePairs.Count) directional pairs" -Severity Information
    }
    else {
        # First node is server, all others are clients
        $serverNode = $nodes[0]
        foreach ($clientNode in $nodes[1..($nodes.Count - 1)]) {
            $nodePairs.Add(@{ Server = $serverNode; Client = $clientNode })
        }
    }

    foreach ($pair in $nodePairs) {
        $server = $pair.Server
        $client = $pair.Client
        $pairLabel = "$client-to-$server"

        if ($PSCmdlet.ShouldProcess($pairLabel, "Run iPerf3 $protocolVal test")) {
            Write-Log -Message "Testing: $client → $server ($protocolVal)" -Severity Information

            # Start iPerf3 server on the server node (daemonized, killed after test)
            $serverSshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
            if ($sshKeyVal) { $serverSshArgs += '-i', $sshKeyVal }
            $serverCmd = "pkill -f 'iperf3 -s' 2>/dev/null; iperf3 -s -p $portVal -D && sleep 2 && echo 'SERVER_READY'"
            $serverSshArgs += "$sshUserVal@$server", $serverCmd

            & ssh @serverSshArgs 2>&1 | Out-Null

            Start-Sleep -Seconds 2

            # Run client
            $resultFile = "$remoteResultsDir/${pairLabel}.json"
            $clientCmd = "mkdir -p $remoteResultsDir"

            if ($protocolVal -eq 'UDP') {
                $bwFlag = if ($bandwidthUdp) { "-b ${bandwidthUdp}M" } else { '-b 1G' }
                $clientCmd += " && iperf3 -c $server -p $portVal -u $bwFlag -P $streamsVal -t $durationVal --json > $resultFile"
            }
            else {
                $clientCmd += " && iperf3 -c $server -p $portVal -P $streamsVal -t $durationVal --json > $resultFile"
            }
            $clientCmd += " && echo 'IPERF_DONE'"

            $clientSshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
            if ($sshKeyVal) { $clientSshArgs += '-i', $sshKeyVal }
            $clientSshArgs += "$sshUserVal@$client", $clientCmd

            $clientOutput = & ssh @clientSshArgs 2>&1
            $exitCode = $LASTEXITCODE

            # Stop iPerf3 server
            $stopSshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')
            if ($sshKeyVal) { $stopSshArgs += '-i', $sshKeyVal }
            $stopSshArgs += "$sshUserVal@$server", "pkill -f 'iperf3 -s' 2>/dev/null; echo 'SERVER_STOPPED'"
            & ssh @stopSshArgs 2>&1 | Out-Null

            if ($exitCode -ne 0) {
                Write-Log -Message "iPerf3 failed on $pairLabel (exit $exitCode)" -Severity Error
                $pairResults.Add(@{ Pair = $pairLabel; Server = $server; Client = $client; Status = 'Failed' })
            }
            else {
                Write-Log -Message "iPerf3 completed: $pairLabel" -Severity Information
                $pairResults.Add(@{
                    Pair            = $pairLabel
                    Server          = $server
                    Client          = $client
                    Status          = 'Completed'
                    RemoteResultFile = $resultFile
                })
            }
        }
    }

    $completed = ($pairResults | Where-Object { $_.Status -eq 'Completed' }).Count
    Write-Log -Message "iPerf3 tests complete: $completed/$($pairResults.Count) pairs succeeded" -Severity Information
    Write-Host "iPerf3 test finished. Run ID: $RunId" -ForegroundColor Green

    return @{
        RunId        = $RunId
        PairResults  = $pairResults
        RemoteResultDir = $remoteResultsDir
        Parameters   = @{
            Protocol       = $protocolVal
            ParallelStreams = $streamsVal
            DurationSeconds = $durationVal
            Port           = $portVal
            MeshTest       = $meshVal
            ProfileName    = if ($profile) { $profile.profile.name } else { 'custom' }
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
