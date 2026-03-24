# fio — Monitoring

![Tool: fio](https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

During fio test runs, host-side performance counters are collected and evaluated against the thresholds in `tools/fio/monitoring/alerts/alert-rules.yml`. Alerts are emitted via the `MonitoringManager` module to the structured log and optionally to Azure Monitor.

## Alert Rules Reference

| Rule Name | Counter | Threshold | Severity | Rationale |
|-----------|---------|-----------|----------|-----------|
| `fio_high_disk_wait` | `\PhysicalDisk(*)\% Disk Time` | > 95% | Warning | Disk fully saturated; additional IOPS headroom is exhausted |
| `fio_high_disk_latency` | `\PhysicalDisk(*)\Avg. Disk sec/Transfer` | > 50ms | **Critical** | Latency this high indicates storage path issues, not just load |
| `fio_high_disk_queue` | `\PhysicalDisk(*)\Current Disk Queue Length` | > 64 | Warning | Queue depth beyond 64 signals storage bandwidth exhaustion |
| `fio_high_cpu` | `\Processor(_Total)\% Processor Time` | > 90% | Warning | High host CPU during fio may artificially depress IOPS results |
| `fio_high_iowait` | `\System\Processor Queue Length` | > 32 | Warning | Processor queue buildup indicates I/O → CPU coupling |
| `fio_low_memory` | `\Memory\Available MBytes` | < 512 MB | Warning | Memory pressure can affect I/O cache hit rates |
| `fio_network_saturation` | `\Network Interface(*)\Bytes Total/sec` | > 9 GB/s | Warning | Storage network saturation may indicate RDMA path issues |

## Understanding fio Alerts

### Storage Alerts

**`fio_high_disk_latency` (Critical)** is raised when the OS-level average disk transfer latency exceeds 50ms. This threshold is intentionally lower than the fio-reported profile thresholds — if the OS latency is already this high, fio is measuring a degraded path, and results are not valid as a baseline.

**`fio_high_disk_queue`** is complementary to disk time: a disk can show 100% busy but still have low queue depth if it is processing requests quickly. A queue beyond 64 on a single disk indicates backpressure accumulating from the fio workload.

### Compute Alerts

**`fio_high_cpu`** warns when CPU utilization exceeds 90% during a storage test. Because fio itself runs in userspace and processes I/O completions, high CPU can limit IOPS measurements on fast NVMe storage and SCM tiers. If this fires, consider reducing `num_jobs` or `io_depth`.

### Memory Alert

**`fio_low_memory`** at the 512 MB threshold warns that the OS buffer cache may be under pressure. Linux I/O cache effects are intentional with libaio (`O_DIRECT` is set by default in the profiles, so this mainly protects the test environment).

## Monitoring During a Run

Monitoring is started automatically by `Start-FioTest.ps1` when the `MonitoringManager` module is available. To check alert output after the fact, review the structured log:

```powershell
# Find alert entries in the run log
Get-Content "logs\fio\<RunId>\fio-test.log.jsonl" |
    ConvertFrom-Json |
    Where-Object { $_.Severity -in @('WARNING', 'CRITICAL') } |
    Select-Object Timestamp, Severity, Message
```

## Alert Configuration File

`tools/fio/monitoring/alerts/alert-rules.yml` — alert definitions are consumed by `MonitoringManager` during test execution. To adjust a threshold, edit the `threshold` field for the relevant rule.

```yaml
# Example: lower the disk latency critical threshold to 20ms
- name: fio_high_disk_latency
  threshold: 0.020    # 20ms
  severity: critical
```

Changes take effect on the next test run. No restart required.
