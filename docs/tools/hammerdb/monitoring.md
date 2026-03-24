# HammerDB — Monitoring

![Tool: HammerDB](https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

During HammerDB benchmark runs, host-side performance counters are collected and evaluated against the thresholds in `tools/hammerdb/monitoring/alerts/alert-rules.yml`.

## Alert Rules Reference

| Rule Name | Counter | Threshold | Severity | Rationale |
|-----------|---------|-----------|----------|-----------|
| `hammerdb_high_cpu` | `\Processor(_Total)\% Processor Time` | > 95% | Warning | CPU bottleneck limits NOPM — not a storage issue |
| `hammerdb_high_cpu_critical` | `\Processor(_Total)\% Processor Time` | > 99% | **Critical** | Results at 99% CPU are not representative of storage performance |
| `hammerdb_low_memory` | `\Memory\Available MBytes` | < 1,024 MB | Warning | Buffer pool pressure may reduce SQL cache-hit ratio |
| `hammerdb_critical_memory` | `\Memory\Available MBytes` | < 256 MB | **Critical** | HammerDB test may fail; database memory allocation will fail |
| `hammerdb_db_disk_latency` | `\PhysicalDisk(*)\Avg. Disk sec/Write` | > 20ms | Warning | Write latency above 20ms will depress TPC-C NOPM scores |
| `hammerdb_high_disk_queue` | `\PhysicalDisk(*)\Current Disk Queue Length` | > 32 | Warning | Storage backpressure on the database volume |
| `hammerdb_network_saturation` | `\Network Interface(*)\Bytes Total/sec` | > 9 GB/s | Warning | Network between HammerDB client and DB server may be bottlenecked |

## Understanding HammerDB Alerts

### CPU Alerts

HammerDB creates a CPU-intensive workload by design — TPC-C warehouses drive many small transactions. The two CPU alert thresholds are distinct:

- **`hammerdb_high_cpu` (95%, Warning)** — signals that CPU is likely the limiting factor for NOPM, not storage I/O. Results are still valid but do not reflect peak storage-limited throughput.
- **`hammerdb_high_cpu_critical` (99%, Critical)** — at this point, HammerDB's virtual users are being starved of CPU cycles, and NOPM/TPM measurements are unreliable. Reduce `virtual_users` or the `warehouse_count`.

### Memory Alerts

The memory thresholds are higher than other tools because SQL Server and PostgreSQL reserve large buffer pools:

- **Warning at 1,024 MB** — buffer pool eviction becomes likely; cache-hit ratio degrades; IOPS increases
- **Critical at 256 MB** — the SQL Server `min server memory` setting alone may exceed this; process will crash

### Storage Alert

**`hammerdb_db_disk_latency` (20ms)** specifically monitors write latency on the database volume, because TPC-C is write-intensive (every new order creates writes to the `orders`, `new_order`, and `order_line` tables). Write latency above 20ms indicates the storage tier is the bottleneck.

## Monitoring During a Run

```powershell
# View alerts from a completed run's log
Get-Content "logs\hammerdb\<RunId>\hammerdb-test.log.jsonl" |
    ConvertFrom-Json |
    Where-Object { $_.Severity -in @('WARNING', 'CRITICAL') } |
    Select-Object Timestamp, Severity, Message
```

## Key Counters to Watch Manually

During a live run, monitor these counters from the management station:

```powershell
# Monitor SQL Server database node (replace with actual hostname)
$dbNode = "sql01.corp.infiniteimprobability.com"
Get-Counter `
    '\Processor(_Total)\% Processor Time',
    '\Memory\Available MBytes',
    '\PhysicalDisk(_Total)\Avg. Disk sec/Write',
    '\PhysicalDisk(_Total)\Disk Writes/sec' `
    -ComputerName $dbNode `
    -SampleInterval 10 -MaxSamples 30 |
    ForEach-Object { $_.CounterSamples } |
    Select-Object Path, CookedValue |
    Format-Table -AutoSize
```
