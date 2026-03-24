# fio — Workload Profiles

![Tool: fio](https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers the built-in fio workload profiles and how to execute them.

## Built-in Profiles

| Profile | File | Category | Block Size | Pattern | Primary Threshold |
|---------|------|----------|-----------|---------|-----------------|
| Sequential Read | `sequential-read.yml` | throughput | 128K | `read` | ≥ 500 MB/s |
| Sequential Write | `sequential-write.yml` | throughput | 128K | `write` | ≥ 400 MB/s |
| Random Read | `random-read.yml` | iops | 4K | `randread` | ≥ 50,000 IOPS |
| Random Write | `random-write.yml` | iops | 4K | `randwrite` | ≥ 30,000 IOPS |
| Mixed 70/30 | `mixed-70-30.yml` | mixed | 4K | `randrw` | ≥ 25,000 IOPS |

## Profile Details

### Sequential Read

Measures peak sustained read throughput using large 128K blocks — typical of streaming, analytics, and backup/restore workloads.

```yaml
profile:
  name: "Sequential Read"
  description: "128K sequential reads for maximum throughput measurement"
  category: "throughput"
  parameters:
    block_size: "128k"
    rw: "read"
    io_engine: "libaio"
    io_depth: 16
    num_jobs: 4
    runtime_seconds: 300
    test_directory: "/tmp/fio-test"
  expected_thresholds:
    min_throughput_mbps: 500
    max_lat_mean_ms: 50
    min_iops: 4000
```

**When to use:** Pre-migration validation for streaming workloads; storage tier qualification; RDMA-enabled storage read baseline.

### Sequential Write

Measures peak sustained write throughput — typical of log ingestion, backup targets, and write-heavy analytics.

```yaml
profile:
  name: "Sequential Write"
  parameters:
    block_size: "128k"
    rw: "write"
    io_engine: "libaio"
    io_depth: 16
    num_jobs: 4
    runtime_seconds: 300
  expected_thresholds:
    min_throughput_mbps: 400
    max_lat_mean_ms: 100
    min_iops: 3200
```

**When to use:** Storage write path validation; HSM/ILM tier benchmarking; backup storage qualification.

### Random Read

Measures peak random read IOPS at 4K — the standard metric for OLTP database read performance.

```yaml
profile:
  name: "Random Read"
  parameters:
    block_size: "4k"
    rw: "randread"
    io_engine: "libaio"
    io_depth: 32
    num_jobs: 4
    runtime_seconds: 300
  expected_thresholds:
    min_iops: 50000
    max_lat_mean_ms: 5
    max_lat_p99_ms: 20
```

**When to use:** Before deploying SQL Server, PostgreSQL, or other OLTP databases; cache effectiveness testing.

### Random Write

Measures peak random write IOPS at 4K — validates write endurance and journal/WAL performance.

```yaml
profile:
  name: "Random Write"
  parameters:
    block_size: "4k"
    rw: "randwrite"
    io_engine: "libaio"
    io_depth: 32
    num_jobs: 4
    runtime_seconds: 300
  expected_thresholds:
    min_iops: 30000
    max_lat_mean_ms: 8
    max_lat_p99_ms: 30
```

**When to use:** Write-intensive database validation; storage tier endurance tests.

### Mixed 70/30

Simulates a production OLTP read/write ratio (70% read, 30% write) at 4K — the closest to real-world database workloads.

```yaml
profile:
  name: "Mixed 70/30"
  parameters:
    block_size: "4k"
    rw: "randrw"
    rwmixread: 70
    io_engine: "libaio"
    io_depth: 32
    num_jobs: 4
    runtime_seconds: 300
  expected_thresholds:
    min_iops: 25000
    max_lat_mean_ms: 10
    max_lat_p99_ms: 40
```

**When to use:** General cluster validation; pre-production sign-off; mixed workload capacity planning.

## Running Profiles

### Single Profile

```powershell
.\tools\fio\scripts\Start-FioTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -Profile "random-read"
```

### Override Parameters at Runtime

```powershell
.\tools\fio\scripts\Start-FioTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1") `
    -Profile "random-read" `
    -RuntimeSeconds 600 `
    -IODepth 64
```

Explicit parameters override the profile values; profile values override `fio.json` defaults.

### Profile Sweep (All Profiles)

```powershell
$nodes = @("hci01-node1", "hci01-node2", "hci01-node3")
$profiles = @("sequential-read", "sequential-write", "random-read", "random-write", "mixed-70-30")

foreach ($profile in $profiles) {
    $result = .\tools\fio\scripts\Start-FioTest.ps1 `
        -ClusterName "hci01.corp.infiniteimprobability.com" `
        -Nodes $nodes `
        -Profile $profile

    .\tools\fio\scripts\Collect-FioResults.ps1 `
        -ClusterName "hci01.corp.infiniteimprobability.com" `
        -Nodes $nodes `
        -RunId $result.RunId
}
```

## Profile Schema

All profiles follow this schema:

```yaml
profile:
  name: string              # Human-readable name
  description: string       # One-line description
  category: string          # throughput | iops | mixed
  parameters:
    block_size: string      # e.g. "4k", "128k"
    rw: string              # read | write | randread | randwrite | randrw
    rwmixread: integer      # 0-100 (only for randrw)
    io_engine: string       # libaio (Linux)
    io_depth: integer       # Outstanding I/O operations per job
    num_jobs: integer       # Parallel fio job processes
    runtime_seconds: integer
    test_directory: string
  expected_thresholds:
    min_iops: integer
    min_throughput_mbps: number
    max_lat_mean_ms: number
    max_lat_p99_ms: number
```

## Creating Custom Profiles

Copy an existing profile YAML and adjust parameters:

```bash
cp tools/fio/config/profiles/random-read.yml tools/fio/config/profiles/my-profile.yml
```

Then reference it by stem name at runtime: `-Profile "my-profile"`.
