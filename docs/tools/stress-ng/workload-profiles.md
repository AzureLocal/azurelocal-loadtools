# stress-ng — Workload Profiles

![Tool: stress-ng](https://img.shields.io/badge/Tool-stress--ng-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

Workload profiles are YAML files stored in `config/profiles/stress-ng/`. They define the stressor mix, worker count, and timeout for each test scenario. `Start-StressNgTest.ps1` loads the selected profile and translates its settings into stress-ng command-line arguments sent over SSH to each target node.

---

## Available Profiles

| Profile File | Category | Stressors | Workers | Timeout |
|---|---|---|---|---|
| `cpu-stress.yml` | CPU | `cpu`, `cpu-cache` | 0 (auto) | 5 min |
| `memory-stress.yml` | Memory | `vm`, `mmap`, `memrate` | 4 | 5 min |
| `io-stress.yml` | Storage I/O | `hdd`, `iomix` | 4 | 5 min |

---

## Profile Details

### CPU Stress (`cpu-stress.yml`)

```yaml
# config/profiles/stress-ng/cpu-stress.yml
name: cpu-stress
description: Saturate all logical CPUs using compute and cache stressors
category: cpu
stressors:
  - cpu
  - cpu-cache
workers: 0          # 0 = one worker per logical CPU (auto-detected by stress-ng)
timeout: 5m
metrics: true
```

**When to use:** Validate CPU performance under sustained full load — thermal throttling detection, scheduler latency, NUMA topology verification. A `workers: 0` value instructs stress-ng to spawn one worker per logical CPU, fully saturating all cores without manual node-size configuration.

**Stressor breakdown:**

| Stressor | Purpose |
|----------|---------|
| `cpu` | General compute: math, bitwise, string ops |
| `cpu-cache` | L1/L2/L3 cache pressure; exercises prefetch and branch prediction |

---

### Memory Stress (`memory-stress.yml`)

```yaml
# config/profiles/stress-ng/memory-stress.yml
name: memory-stress
description: Exercise virtual memory, anonymous mappings, and memory bandwidth
category: memory
stressors:
  - vm
  - mmap
  - memrate
workers: 4
timeout: 5m
metrics: true
```

**When to use:** Validate memory bandwidth and the OS's ability to handle high anonymous page pressure. Useful for confirming NUMA memory affinity configurations and validating ARC/buffer pool behaviour before database workloads. `workers: 4` balances load across NUMA nodes on a 4-node ring topology.

**Stressor breakdown:**

| Stressor | Purpose |
|----------|---------|
| `vm` | `mmap`/`munmap` allocation loops; triggers page-fault path |
| `mmap` | Large anonymous mappings; stress virtual address space |
| `memrate` | Sequential read/write at configurable byte rates; measures memory bandwidth |

---

### I/O Stress (`io-stress.yml`)

```yaml
# config/profiles/stress-ng/io-stress.yml
name: io-stress
description: Stress disk I/O with mixed sequential and random patterns using hdd and iomix stressors
category: storage
stressors:
  - hdd
  - iomix
workers: 4
timeout: 5m
metrics: true
```

**When to use:** Complement fio storage benchmarks with sustained I/O pressure that exercises the OS VFS and scheduler layers. Use this profile before a fio run to confirm the storage stack can sustain load over a multi-minute window without errors.

**Stressor breakdown:**

| Stressor | Purpose |
|----------|---------|
| `hdd` | Sequential write to temporary files; measures write throughput via VFS |
| `iomix` | Mixed read/write/mmap; mimics application-level mixed workload |

---

## Running a Profile

```powershell
# Single profile on all nodes
.\scripts\Start-StressNgTest.ps1 -RunId "stressng-cpu-$(Get-Date -f yyyyMMddHHmm)" `
    -Profile "cpu-stress"

# Override timeout at runtime (useful for quick smoke tests)
.\scripts\Start-StressNgTest.ps1 -RunId "smoke-$(Get-Date -f yyyyMMddHHmm)" `
    -Profile "cpu-stress" -Timeout "60s"
```

## Profile Sweep Example

Run all three profiles in sequence to get a full-system stress picture:

```powershell
$runDate = Get-Date -Format "yyyyMMddHHmm"
$profiles = @("cpu-stress", "memory-stress", "io-stress")

foreach ($profile in $profiles) {
    $runId = "stressng-$profile-$runDate"
    Write-Host "Starting profile: $profile (RunId: $runId)"
    .\scripts\Start-StressNgTest.ps1 -RunId $runId -Profile $profile
    .\scripts\Collect-StressNgResults.ps1 -RunId $runId
    Write-Host "Profile $profile complete. Results in logs\stress-ng\$runId\"
}
```

---

## Profile Schema Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Profile identifier; passed to `-Profile` |
| `description` | string | no | Human-readable summary |
| `category` | string | yes | `cpu` / `memory` / `storage` |
| `stressors` | list[string] | yes | stress-ng stressor names (e.g. `cpu`, `vm`, `hdd`) |
| `workers` | int | yes | Worker count per stressor; `0` = one per logical CPU |
| `timeout` | string | yes | Duration string accepted by stress-ng (e.g. `5m`, `300s`) |
| `metrics` | bool | no | Write YAML metrics to `--metrics-brief`; default `true` |
