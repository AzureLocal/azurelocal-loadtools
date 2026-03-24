# fio — Reporting

![Tool: fio](https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers how fio results are collected, normalized, and rendered into reports.

## Result Collection

`Collect-FioResults.ps1` retrieves and normalizes fio output from each node:

```powershell
.\tools\fio\scripts\Collect-FioResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3") `
    -RunId "<run-id>"
```

### What It Does

1. SCP-copies `/tmp/fio-results/<RunId>/fio-results.json` from each node
2. Parses the fio JSON structure (`jobs[].read` and `jobs[].write`)
3. Normalizes units — latency from nanoseconds to milliseconds, bandwidth from bytes/s to MB/s
4. Aggregates per-node results into cluster totals
5. Writes two output files and removes remote result files

## Output Files

Results land in `logs\fio\<RunId>\`:

| File | Contents |
|------|---------|
| `<RunId>-aggregate.json` | Cluster-level summary metrics |
| `<RunId>-per-job.json` | Per-node, per-job detail |

### Aggregate JSON Schema

```json
{
  "run_id": "fio-20260324-143012",
  "timestamp": "2026-03-24T14:30:12Z",
  "cluster_name": "hci01.corp.infiniteimprobability.com",
  "profile": "random-read",
  "nodes_tested": ["hci01-node1", "hci01-node2"],
  "aggregate": {
    "read_iops": 98234,
    "write_iops": 0,
    "total_iops": 98234,
    "read_throughput_mbps": 384.5,
    "write_throughput_mbps": 0,
    "read_lat_mean_ms": 1.32,
    "read_lat_p99_ms": 4.87,
    "write_lat_mean_ms": null,
    "write_lat_p99_ms": null
  },
  "threshold_violations": []
}
```

### Key Metric Fields

| Field | Unit | Source |
|-------|------|--------|
| `read_iops` | IOPS | `jobs[].read.iops` |
| `write_iops` | IOPS | `jobs[].write.iops` |
| `total_iops` | IOPS | read + write combined |
| `read_throughput_mbps` | MB/s | `jobs[].read.bw_bytes` ÷ 1,048,576 |
| `write_throughput_mbps` | MB/s | `jobs[].write.bw_bytes` ÷ 1,048,576 |
| `read_lat_mean_ms` | ms | `jobs[].read.lat_ns.mean` ÷ 1,000,000 |
| `read_lat_p99_ms` | ms | `jobs[].read.lat_ns.percentile["99.000000"]` ÷ 1,000,000 |

## Report Generation

Reports are generated from the AsciiDoc templates in `tools/fio/reports/templates/`:

```powershell
# Generate PDF from collected results
asciidoctor-pdf `
    tools/fio/reports/templates/report-template.adoc `
    -a run-id="<RunId>" `
    -a results-dir="logs/fio/<RunId>" `
    -o reports/fio-<RunId>.pdf
```

### Template Placeholders

The report template uses these attribute substitutions:

| Placeholder | Value Source |
|-------------|-------------|
| `{run-id}` | `RunId` parameter |
| `{cluster-name}` | `cluster_name` in aggregate JSON |
| `{profile-name}` | `profile` in aggregate JSON |
| `{fio-block-size}` | Profile `block_size` |
| `{fio-rw}` | Profile `rw` pattern |
| `{total-read-iops}` | `aggregate.read_iops` |
| `{total-write-iops}` | `aggregate.write_iops` |
| `{read-throughput-mbps}` | `aggregate.read_throughput_mbps` |
| `{read-lat-mean-ms}` | `aggregate.read_lat_mean_ms` |
| `{read-lat-p99-ms}` | `aggregate.read_lat_p99_ms` |

## Reviewing Threshold Violations

```powershell
# Check if any thresholds were violated
$results = Get-Content "logs\fio\<RunId>\<RunId>-aggregate.json" | ConvertFrom-Json
if ($results.threshold_violations.Count -gt 0) {
    $results.threshold_violations | Format-Table -AutoSize
}
```

A threshold violation does not fail the run — it is recorded in the output and surfaced in the log for human review.
