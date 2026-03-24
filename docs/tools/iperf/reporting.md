# iPerf3 — Reporting

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers how iPerf3 results are collected, normalized, and rendered into reports.

## Result Collection

`Collect-IperfResults.ps1` retrieves per-pair JSON result files from each node:

```powershell
.\tools\iperf\scripts\Collect-IperfResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3") `
    -RunId "<run-id>"
```

### What It Does

1. SCP-copies `/tmp/iperf-results/<RunId>/` recursively from each node
2. Parses the iPerf3 JSON output (per-pair `<client>-to-<server>.json` files)
3. Normalizes TCP metrics: bits/s → MB/s, retransmit counts, stream counts
4. Normalizes UDP metrics: bits/s → MB/s, jitter (ms), lost packets, loss percentage
5. Aggregates cluster-wide statistics (max/min/avg across pairs)
6. Writes two output files and removes remote result files

## Output Files

Results land in `logs\iperf\<RunId>\`:

| File | Contents |
|------|---------|
| `<RunId>-aggregate.json` | Cluster-level summary metrics across all pairs |
| `<RunId>-per-pair.json` | Per-node-pair detail |

### Aggregate JSON Schema

```json
{
  "run_id": "iperf-20260324-160012",
  "timestamp": "2026-03-24T16:00:12Z",
  "cluster_name": "hci01.corp.infiniteimprobability.com",
  "profile": "tcp-throughput",
  "pairs_tested": 6,
  "aggregate": {
    "tcp_max_send_throughput_mbps": 9421.3,
    "tcp_min_send_throughput_mbps": 9187.6,
    "tcp_avg_send_throughput_mbps": 9304.2,
    "tcp_total_retransmits": 12,
    "udp_avg_throughput_mbps": null,
    "udp_avg_jitter_ms": null,
    "udp_max_packet_loss_percent": null
  },
  "threshold_violations": []
}
```

### Key Metric Fields

| Field | Unit | Protocol | Description |
|-------|------|----------|-------------|
| `tcp_max_send_throughput_mbps` | MB/s | TCP | Highest throughput across all pairs |
| `tcp_min_send_throughput_mbps` | MB/s | TCP | Lowest throughput across all pairs |
| `tcp_avg_send_throughput_mbps` | MB/s | TCP | Average across all pairs |
| `tcp_total_retransmits` | count | TCP | Sum of retransmits from all pairs |
| `udp_avg_throughput_mbps` | MB/s | UDP | Average UDP throughput across pairs |
| `udp_avg_jitter_ms` | ms | UDP | Average jitter across pairs |
| `udp_max_packet_loss_percent` | % | UDP | Worst-case packet loss across pairs |

## Per-Pair File

The per-pair file is essential for mesh tests — it shows which specific pair had low throughput or high loss:

```json
{
  "pairs": [
    {
      "client": "hci01-node1",
      "server": "hci01-node2",
      "protocol": "TCP",
      "send_throughput_mbps": 9421.3,
      "retransmits": 4,
      "streams": 8
    },
    {
      "client": "hci01-node2",
      "server": "hci01-node1",
      "send_throughput_mbps": 8912.1,
      "retransmits": 2,
      "streams": 8
    }
  ]
}
```

A large asymmetry between `hci01-node1 → hci01-node2` and `hci01-node2 → hci01-node1` indicates a directional path issue.

## Report Generation

```powershell
asciidoctor-pdf `
    tools/iperf/reports/templates/report-template.adoc `
    -a run-id="<RunId>" `
    -a results-dir="logs/iperf/<RunId>" `
    -o reports/iperf-<RunId>.pdf
```

### Template Placeholders

| Placeholder | Value Source |
|-------------|-------------|
| `{iperf-protocol}` | Profile `protocol` |
| `{iperf-streams}` | Profile `parallel_streams` |
| `{iperf-duration}` | Profile `duration_seconds` |
| `{tcp-max-send-throughput-mbps}` | `aggregate.tcp_max_send_throughput_mbps` |
| `{tcp-min-send-throughput-mbps}` | `aggregate.tcp_min_send_throughput_mbps` |
| `{tcp-avg-send-throughput-mbps}` | `aggregate.tcp_avg_send_throughput_mbps` |
| `{tcp-total-retransmits}` | `aggregate.tcp_total_retransmits` |
| `{udp-avg-jitter-ms}` | `aggregate.udp_avg_jitter_ms` |
| `{udp-max-packet-loss-percent}` | `aggregate.udp_max_packet_loss_percent` |

## Checking Mesh Variance

For mesh profiles, calculate throughput variance across pairs:

```powershell
$perPair = Get-Content "logs\iperf\<RunId>\<RunId>-per-pair.json" | ConvertFrom-Json
$throughputs = $perPair.pairs | Select-Object -ExpandProperty send_throughput_mbps
$max = ($throughputs | Measure-Object -Maximum).Maximum
$min = ($throughputs | Measure-Object -Minimum).Minimum
$variance = ($max - $min) / $max * 100
Write-Host "Throughput variance: $([math]::Round($variance, 1))%"
```

Variance > 10% requires investigation (see [Troubleshooting](troubleshooting.md)).
