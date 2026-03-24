# iPerf3 — Workload Profiles

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers the built-in iPerf3 workload profiles and how to execute them.

## Built-in Profiles

| Profile | File | Protocol | Mode | Primary Threshold |
|---------|------|----------|------|-----------------|
| TCP Throughput | `tcp-throughput.yml` | TCP | Node-to-node | ≥ 8,000 MB/s |
| UDP Latency | `udp-latency.yml` | UDP | Node-to-node | ≤ 1.0ms jitter, ≤ 0.1% loss |
| Mesh Throughput | `mesh.yml` | TCP | All-to-all | ≥ 7,000 MB/s, ≤ 10% variance |

## Profile Details

### TCP Throughput

Measures peak TCP bandwidth between the first node (server) and all other nodes (clients) using multiple parallel streams.

```yaml
profile:
  name: "TCP Throughput"
  description: "Multi-stream TCP throughput test for maximum bandwidth measurement"
  category: "throughput"
  parameters:
    protocol: "TCP"
    parallel_streams: 8
    duration_seconds: 30
    server_port: 5201
    mesh_test: false
  expected_thresholds:
    min_throughput_mbps: 8000
    max_retransmits_per_pair: 500
```

**When to use:** Baseline network validation before deploying any workload; 10GbE/25GbE qualification; post-NIC driver or firmware update verification; SMB-Direct/RDMA path sanity.

**8 parallel streams** avoids single-TCP-connection bottlenecks on high-throughput links. On 25GbE links, consider raising to 16 streams.

### UDP Latency

Measures jitter and packet loss at a controlled UDP send rate. Unlike TCP, UDP does not retransmit — jitter and loss reveal the true network quality.

```yaml
profile:
  name: "UDP Latency"
  description: "UDP jitter and packet loss test for latency-sensitive workload assessment"
  category: "latency"
  parameters:
    protocol: "UDP"
    parallel_streams: 1
    duration_seconds: 60
    server_port: 5201
    udp_bandwidth_mbps: 100
    mesh_test: false
  expected_thresholds:
    max_jitter_ms: 1.0
    max_packet_loss_percent: 0.1
    min_throughput_mbps: 90
```

**When to use:** Pre-deployment validation for latency-sensitive workloads (real-time analytics, VoIP, trading platforms); VLAN/switch QoS verification.

**`udp_bandwidth_mbps: 100`** caps the send rate to avoid saturating the link — UDP has no congestion control, so an uncapped rate would fill the pipe and create artificial packet loss.

### Mesh Throughput

Tests all directional node pairs (N×N-1 pairs for N nodes) to reveal asymmetric bandwidth or topology bottlenecks that do not appear in a single pair test.

```yaml
profile:
  name: "Mesh Throughput"
  description: "All-to-all TCP throughput across every node pair — identifies asymmetric bandwidth"
  category: "mesh"
  parameters:
    protocol: "TCP"
    parallel_streams: 4
    duration_seconds: 30
    server_port: 5201
    mesh_test: true
  expected_thresholds:
    min_throughput_mbps: 7000
    max_throughput_variance_percent: 10
    max_retransmits_per_pair: 200
```

**When to use:** After cluster hardware changes; NIC replacement or driver updates; switch firmware upgrades; to identify spine/leaf topology asymmetry.

**`max_throughput_variance_percent: 10`** — a variance greater than 10% between node pairs indicates that some paths are slower than others. Common causes: mismatched NIC firmware, VLAN misconfiguration, or oversubscription at a switch uplink.

## Running Profiles

### TCP Throughput

```powershell
.\tools\iperf\scripts\Start-IperfTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3", "hci01-node4") `
    -Profile "tcp-throughput"
```

### UDP Latency

```powershell
.\tools\iperf\scripts\Start-IperfTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -Profile "udp-latency"
```

### Mesh All-to-All

```powershell
# Mesh tests every pair: node1→node2, node1→node3, node2→node1, node2→node3, etc.
.\tools\iperf\scripts\Start-IperfTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3", "hci01-node4") `
    -Profile "mesh"
```

### Override Parameters at Runtime

```powershell
.\tools\iperf\scripts\Start-IperfTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -Profile "tcp-throughput" `
    -ParallelStreams 16 `
    -DurationSeconds 120
```

## Profile Schema

```yaml
profile:
  name: string                    # Human-readable name
  description: string
  category: string                # throughput | latency | mesh
  parameters:
    protocol: string              # TCP | UDP
    parallel_streams: integer     # Number of parallel TCP/UDP streams
    duration_seconds: integer     # Test window in seconds
    server_port: integer          # iPerf3 server port (default 5201)
    udp_bandwidth_mbps: integer   # UDP only: send rate cap in Mbps
    mesh_test: boolean            # true = all-to-all; false = client→server only
  expected_thresholds:
    min_throughput_mbps: number
    max_jitter_ms: number         # UDP only
    max_packet_loss_percent: number  # UDP only
    max_retransmits_per_pair: integer  # TCP only
    max_throughput_variance_percent: number  # Mesh only
```
