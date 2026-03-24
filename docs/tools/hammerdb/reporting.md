# HammerDB — Reporting

![Tool: HammerDB](https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers how HammerDB results are collected, parsed, and rendered into reports.

## Result Collection

`Collect-HammerDBResults.ps1` retrieves and parses the HammerDB log output from the primary node:

```powershell
.\tools\hammerdb\scripts\Collect-HammerDBResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1" `
    -RunId "<run-id>"
```

### What It Does

1. Reads the raw HammerDB log from `C:\hammerdb-results\<RunId>\hammerdb.log` via PowerShell remoting
2. Parses NOPM/TPM lines using the `Get-HammerDBMetrics` function:  
   Pattern: `"System achieved 12345 NOPM from 23456 PostgreSQL TPM"`
3. Extracts peak, average, and sample-count values
4. Writes two output files to `logs\hammerdb\<RunId>\`

## Output Files

| File | Contents |
|------|---------|
| `<RunId>-aggregate.json` | Peak/average NOPM and TPM, sample count, threshold violations |
| `<RunId>-hammerdb.log` | Copy of the raw HammerDB log |

### Aggregate JSON Schema

```json
{
  "run_id": "hammerdb-20260324-150012",
  "timestamp": "2026-03-24T15:00:12Z",
  "cluster_name": "hci01.corp.infiniteimprobability.com",
  "profile": "tpc-c",
  "primary_node": "hci01-node1",
  "metrics": {
    "peak_nopm": 7823,
    "avg_nopm": 6941,
    "peak_tpm": 12440,
    "avg_tpm": 11032,
    "samples": 18
  },
  "threshold_violations": []
}
```

### Key Metric Fields

| Field | Description |
|-------|-------------|
| `peak_nopm` | Highest single-sample NOPM across the test duration |
| `avg_nopm` | Mean NOPM across all samples (excludes ramp-up period) |
| `peak_tpm` | Highest single-sample TPM |
| `avg_tpm` | Mean TPM across all samples |
| `samples` | Number of measurement samples captured |

## Report Generation

```powershell
asciidoctor-pdf `
    tools/hammerdb/reports/templates/report-template.adoc `
    -a run-id="<RunId>" `
    -a results-dir="logs/hammerdb/<RunId>" `
    -o reports/hammerdb-<RunId>.pdf
```

### Template Placeholders

| Placeholder | Value Source |
|-------------|-------------|
| `{hammerdb-benchmark-type}` | Profile `benchmark_type` (tpcc / tpch) |
| `{hammerdb-db-type}` | Profile `db_type` |
| `{hammerdb-warehouses}` | Profile `warehouse_count` |
| `{hammerdb-virtual-users}` | Profile `virtual_users` |
| `{peak-nopm}` | `metrics.peak_nopm` |
| `{avg-nopm}` | `metrics.avg_nopm` |
| `{peak-tpm}` | `metrics.peak_tpm` |
| `{avg-tpm}` | `metrics.avg_tpm` |

## Interpreting Results

**NOPM is the primary benchmark output.** Report it as:

- Peak NOPM: the highest instantaneous throughput achieved
- Average NOPM: the sustained throughput over the test window (more representative)

A spread of more than 30% between peak and average NOPM indicates inconsistent performance — check for I/O latency spikes in the [Monitoring](monitoring.md) log.

## Reviewing Raw Log

The raw HammerDB log is preserved for audit purposes:

```powershell
# View NOPM/TPM measurement lines
Get-Content "logs\hammerdb\<RunId>\<RunId>-hammerdb.log" |
    Select-String "NOPM"
```
