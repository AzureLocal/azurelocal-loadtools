# VMFleet Workload Profiles

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers the predefined workload profiles for VMFleet testing and how to execute them.

## Built-in Profiles

| Profile | Description |
| --- | --- |
| General | Balanced 70/30 read/write, 70% random, 8K blocks — general purpose validation |
| Peak IOPS | 100% random 4K reads — maximum IOPS measurement |
| VDI | Mixed small block I/O simulating Virtual Desktop Infrastructure patterns |
| SQL OLTP | 8K random read/write mix simulating SQL Server OLTP workloads |
| Sequential Throughput | 100% sequential 512K writes for maximum MB/s measurement |
| Day2Smoke | The General workload shortened to about 15 minutes for a readiness gate: see [Day-2 smoke](../../reference/day2-smoke.md) |
| FailureInjection | The General workload held for 20 minutes so one injected failure can be measured. Opt-in: see [failure injection](failure-injection.md) |

## Running Tests

### Single Profile

```powershell
.\tools\vmfleet\scripts\Start-VMFleetTest.ps1 `
    -ProfilePath "tools/vmfleet/config/profiles/general.yml" `
    -DurationSeconds 300
```

### Profile Sweep

```powershell
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath "config/clusters/my-cluster.yml" `
    -ProfilePaths @(
        "tools/vmfleet/config/profiles/general.yml",
        "tools/vmfleet/config/profiles/peak-iops.yml",
        "tools/vmfleet/config/profiles/sql-oltp.yml",
        "tools/vmfleet/config/profiles/vdi.yml",
        "tools/vmfleet/config/profiles/sequential-throughput.yml"
    )
```

## Profile Configuration

Profiles are defined in `tools/vmfleet/config/profiles/`:

```yaml
# tools/vmfleet/config/profiles/general.yml
profile:
  name: "General"
  description: "Balanced read/write workload for general validation"
  parameters:
    block_size: "8k"
    write_ratio: 30
    random_ratio: 70
    outstanding_io: 8
    threads_per_vm: 2
    duration_seconds: 300
    warmup_seconds: 60
```

### Profile Parameters

| Parameter | Description | Example |
| --- | --- | --- |
| `block_size` | I/O block size | `4k`, `8k`, `64k` |
| `write_ratio` | Percentage of I/O that is writes (0–100) | `30` for 70/30 read/write |
| `random_ratio` | Percentage of I/O that is random (0–100) | `70` for mostly random |
| `outstanding_io` | I/O queue depth per thread | `8` |
| `threads_per_vm` | DiskSpd threads per fleet VM | `2` |
| `duration_seconds` | Test duration (excluding warmup) | `300` |
| `warmup_seconds` | Warmup before measurement starts | `60` |

## DiskSpd Parameter Mapping

| Profile key | DiskSpd switch | Meaning |
| --- | --- | --- |
| `block_size` | `-b` | I/O block size |
| `write_ratio` | `-w` | Write ratio percentage |
| `random_ratio` | `-r` | Random I/O ratio percentage |
| `outstanding_io` | `-o` | Queue depth per thread |
| `threads_per_vm` | `-t` | Threads per VM |
| `duration_seconds` | `-d` | Measurement duration |
| `warmup_seconds` | `-W` | Warmup duration |

## Expected Thresholds

| Profile | Primary metric focus | Typical pass criteria |
| --- | --- | --- |
| General | Balanced IOPS + latency | Stable mixed IOPS and latency under target |
| Peak IOPS | Max read IOPS | Highest sustained random read IOPS |
| SQL OLTP | Read/write DB pattern | Low latency under mixed random load |
| VDI | Light mixed desktop load | Predictable latency across many VMs |
| Sequential Throughput | MB/s | Highest sustained throughput |

## Profile Selection Guide

- Use `peak-iops.yml` for storage ceiling discovery.
- Use `sql-oltp.yml` for database-aligned validation.
- Use `vdi.yml` for desktop density readiness checks.
- Use `sequential-throughput.yml` for bulk transfer throughput checks.
- Use `general.yml` for a balanced baseline run.

## Collecting Results

After tests complete, parse DiskSpd XML output and aggregate metrics:

```powershell
.\src\solutions\vmfleet\scripts\Collect-VMFleetResults.ps1 `
    -ResultsPath "results/current-run/"
```

## Next Steps

- [Monitoring](monitoring.md) — Metric collection during tests
- [Reporting](reporting.md) — Generate reports from results

## Read this before you compare results

### The CSV in-memory read cache can make these tools look worse

Learn says: "Certain microbenchmarking tools like DISKSPD and VM Fleet may produce worse results with the CSV in-memory read cache enabled than without it." VMFleet by default creates one 10 GiB VHDX per VM and then issues *uniformly random* reads and writes against them. Unlike a real workload, the reads follow no predictable or repeated pattern, so the in-memory read cache is not effective and "just incurs overhead" ([Use the CSV in-memory read cache](https://learn.microsoft.com/windows-server/storage/storage-spaces/use-csv-cache)).

What to do with that:

- Record the CSV cache size next to every result (`(Get-Cluster).BlockCacheSize`, in MiB per server; the Azure Local default is 1 GiB).
- Compare runs only when the cache setting is the same. A result taken with the cache off is not comparable with one taken with it on.
- Do not conclude that the cache is bad for your workloads from a synthetic uniform-random test. Learn says it is most effective for read-intensive workloads such as VDI, and that writes cannot be cached in memory.
- Do not change the cache setting on a production cluster to chase a benchmark number.

### Validate with DiskSpd from representative VMs, including under failure

The Azure Well-Architected Framework guidance for Azure Local recommends using DiskSpd, application benchmarks or SAN vendor tools "from representative VMs to validate latency, throughput, and IOPS under normal and intended failure conditions" ([Architecture best practices for Azure Local](https://learn.microsoft.com/azure/well-architected/service-guides/azure-local#performance-efficiency)). The Azure Local baseline reference architecture says synthetic tools such as DiskSpd or VMFleet "isolate storage subsystem constraints and establish a repeatable performance baseline", and that the application itself should be load-tested to confirm end-to-end targets ([baseline architecture](https://learn.microsoft.com/azure/architecture/hybrid/azure-local-baseline#considerations)). See also [DiskSpd overview](https://learn.microsoft.com/azure/azure-local/manage/diskspd-overview).

This repository supports the failure part with an opt-in helper: [failure injection](failure-injection.md).
