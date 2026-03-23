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

## Running Tests

### Single Profile

```powershell
.\src\solutions\vmfleet\scripts\Start-VMFleetTest.ps1 `
    -ProfilePath "config/profiles/vmfleet/general.yml" `
    -DurationSeconds 300
```

### Profile Sweep

```powershell
.\src\solutions\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath "config/clusters/my-cluster.yml" `
    -ProfilePaths @(
        "config/profiles/vmfleet/general.yml",
        "config/profiles/vmfleet/peak-iops.yml",
        "config/profiles/vmfleet/sql-oltp.yml",
        "config/profiles/vmfleet/vdi.yml",
        "config/profiles/vmfleet/sequential-throughput.yml"
    )
```

## Profile Configuration

Profiles are defined in `config/profiles/vmfleet/`:

```yaml
# config/profiles/vmfleet/general.yml
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
