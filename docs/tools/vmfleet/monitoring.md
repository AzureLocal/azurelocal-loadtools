# VMFleet Monitoring

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

The monitoring subsystem collects real-time storage, network, and compute metrics during VMFleet test execution. It uses a hybrid architecture: local PowerShell/PerfMon collection (always active) with optional push to Azure Monitor/Log Analytics.

## Monitoring Architecture

```text
Cluster Nodes (PerfMon counters)
        │
        ▼
PowerShell Get-Counter (remote sessions)
        │
        ├──► Local CSV/JSON files (results/{run-id}/metrics/)
        │
        └──► Azure Monitor / Log Analytics (optional)
                    │
                    ▼
              Azure Portal dashboards, alerts
```

## Live Console Monitoring

Use the built-in watcher during active tests:

```powershell
.\src\solutions\vmfleet\scripts\Watch-VMFleetMonitor.ps1 `
    -ClusterConfigPath "config/clusters/my-cluster.yml" `
    -RefreshIntervalSeconds 5 `
    -DurationMinutes 30
```

The watcher prints rolling VM count, read/write IOPS, read/write latency, and throughput.

## Metric Categories

### Storage Metrics

Collected by `Collect-StorageMetrics.ps1`:

| Counter | Description |
| --- | --- |
| CSVFS: Read IOPS | Cluster Shared Volume read operations per second |
| CSVFS: Write IOPS | Cluster Shared Volume write operations per second |
| CSVFS: Read Throughput (MB/s) | Aggregate read bandwidth across CSVs |
| CSVFS: Write Throughput (MB/s) | Aggregate write bandwidth across CSVs |
| CSVFS: Read Latency (ms) | Average read latency per I/O operation |
| CSVFS: Write Latency (ms) | Average write latency per I/O operation |
| S2D Cache Hit Ratio | Percentage of I/O served from cache tier |
| Physical Disk Queue Depth | Outstanding I/O requests per physical disk |
| Storage Pool Health | Degraded/healthy status of storage pools |

### Network Metrics

Collected by `Collect-NetworkMetrics.ps1`:

| Counter | Description |
| --- | --- |
| RDMA Activity: Bytes Sent/sec | RDMA network adapter transmit throughput |
| RDMA Activity: Bytes Received/sec | RDMA network adapter receive throughput |
| SMB Direct: Bytes Sent/sec | SMB Direct (RDMA) data transfer rate |
| Network Adapter: Throughput (Gbps) | Total NIC throughput per adapter |
| Network Adapter: Packets Dropped | Dropped packets indicating congestion or errors |
| TCP: Retransmits/sec | TCP retransmission rate (indicates network issues) |

### Compute Metrics

Collected by `Collect-ComputeMetrics.ps1`:

| Counter | Description |
| --- | --- |
| Processor: % Total CPU | Host CPU utilization across all logical processors |
| Hyper-V Hypervisor Logical Processor: % Total Run Time | Hypervisor-level CPU consumption |
| Guest vCPU Utilization | Per-VM CPU usage (via VMFleet `Watch-FleetCPU`) |
| Memory: Available MBytes | Free physical memory on each host |
| Memory: % Committed Bytes In Use | Memory pressure indicator |
| Hyper-V Dynamic Memory: Current Pressure | Dynamic memory pressure per VM |

## Local Metric Collection

Local collection is always active during test runs:

```powershell
# Collect all metric categories with 5-second intervals
.\tools\vmfleet\monitoring\Collect-StorageMetrics.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -SampleIntervalSeconds 5 `
    -OutputPath "results/run-001/metrics/storage/"

.\tools\vmfleet\monitoring\Collect-NetworkMetrics.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -SampleIntervalSeconds 5 `
    -OutputPath "results/run-001/metrics/network/"

.\tools\vmfleet\monitoring\Collect-ComputeMetrics.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -SampleIntervalSeconds 5 `
    -OutputPath "results/run-001/metrics/compute/"
```

Output format is JSON-lines for machine parsing:

```json
{"timestamp":"2026-02-13T10:05:00Z","node":"hci-node-01","counter":"CSVFS_ReadIOPS","value":45230}
{"timestamp":"2026-02-13T10:05:00Z","node":"hci-node-01","counter":"CSVFS_WriteIOPS","value":12840}
```

## Azure Monitor Integration

Optionally push collected metrics to Azure Monitor for centralized dashboards and alerting:

```powershell
.\tools\vmfleet\monitoring\Push-MetricsToAzureMonitor.ps1 `
    -MetricsPath "results/run-001/metrics/" `
    -WorkspaceId "your-log-analytics-workspace-id" `
    -CredentialSource KeyVault
```

Each pushed metric contains these core fields:

- `timestamp`
- `node`
- `counter_name`
- `value`
- `run_id`
- `profile_name`

> [!NOTE]
> Azure Monitor integration requires the `monitoring.bicep` infrastructure template to be deployed. See `tools/vmfleet/infrastructure/bicep/monitoring.bicep`.
>
## Alert Rules

Predefined alert thresholds in `monitoring/alerts/alert-rules.yml`:

```yaml
alerts:
  - name: high_storage_latency
    metric: csvfs_write_latency_ms
    threshold: 50
    severity: warning
    description: "Write latency exceeds 50ms — possible storage bottleneck"

  - name: critical_cpu
    metric: host_cpu_percent
    threshold: 95
    severity: critical
    description: "Host CPU exceeds 95% — test may be compute-bound"
```

## Real-Time Dashboard

During test execution, use the monitoring dashboard wrapper:

```powershell
# Launch real-time monitoring (combines VMFleet Watch-FleetCluster with custom metrics)
.\tools\vmfleet\monitoring\Export-MetricsDashboard.ps1 `
    -InputPath "results/run-001/metrics/" `
    -OutputPath "reports/run-001/" `
    -Title "VMFleet Run 001"
```

## Counter Reference

| Category | Counter name | Purpose |
| --- | --- | --- |
| Storage | `CSVFS_ReadIOPS` | CSVFS read operations per second |
| Storage | `CSVFS_WriteIOPS` | CSVFS write operations per second |
| Storage | `CSVFS_ReadMBps` | Read throughput |
| Storage | `CSVFS_WriteMBps` | Write throughput |
| Storage | `CSVFS_ReadLatencyMs` | Read latency |
| Storage | `CSVFS_WriteLatencyMs` | Write latency |
| Compute | `HostCpuPercent` | Host CPU saturation |
| Compute | `HostAvailableMemoryMB` | Available memory headroom |
| Compute | `HyperVLogicalProcessorRunTime` | Hypervisor CPU pressure |

## KQL Examples

```kusto
VMFleetMetrics_CL
| where CounterName_s in ("CSVFS_ReadIOPS", "CSVFS_WriteIOPS")
| summarize AvgValue=avg(Value_d) by bin(TimeGenerated, 1m), CounterName_s
| render timechart
```

```kusto
VMFleetMetrics_CL
| where CounterName_s in ("CSVFS_ReadLatencyMs", "CSVFS_WriteLatencyMs")
| summarize P95=percentile(Value_d, 95) by bin(TimeGenerated, 1m), CounterName_s
| render timechart
```
