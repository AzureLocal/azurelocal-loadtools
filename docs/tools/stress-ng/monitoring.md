# stress-ng — Monitoring

![Tool: stress-ng](https://img.shields.io/badge/Tool-stress--ng-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

The stress-ng monitoring configuration lives at `monitoring/stress-ng/alert-rules.yml`. These rules fire during an active stress run and are evaluated by the monitoring side-car that polls Windows Performance Counters on each target node via WMI.

---

## Alert Rules

| Rule Name | Counter | Condition | Threshold | Severity |
|-----------|---------|-----------|-----------|----------|
| `stressng_cpu_throttling` | `\Processor Information(_Total)\% Processor Frequency` | `<` | 80% | warning |
| `stressng_system_hang` | `\System\Processor Queue Length` (normalised) | `>` | 20% idle equivalence | critical |
| `stressng_oom_risk` | `\Memory\Available MBytes` | `<` | 128 MB | critical |
| `stressng_high_pagefile` | `\Paging File(_Total)\% Usage` | `>` | 80% | warning |
| `stressng_disk_saturation` | `\LogicalDisk(_Total)\% Disk Time` | `>` | 98% | warning |
| `stressng_disk_error` | `\LogicalDisk(_Total)\Disk Transfers/sec` drops to 0 during active `hdd`/`iomix` run | `==` | 0 | critical |

---

## Rule Details

### `stressng_cpu_throttling` — Processor Frequency Drop

Monitors the processor's operating frequency relative to its rated maximum. A drop below 80% during a CPU stress run indicates thermal throttling — the host is reducing clock speed due to heat. This invalidates bogo-ops comparisons across nodes because throttled and unthrottled nodes produce incomparable results.

**Resolution:** Check chassis airflow, confirm thermal paste contact, and verify BIOS power profile is set to "Maximum Performance" (not "Balanced").

---

### `stressng_system_hang` — Processor Queue Saturation

A high normalised Processor Queue Length during a stress run can indicate that the OS scheduler is overwhelmed beyond what stress-ng workload alone would cause. This can point to other processes (antivirus, backup agents) competing for CPU time and interfering with bogo-ops measurement accuracy.

**Resolution:** Identify competing processes with `Get-Counter "\Process(*)\% Processor Time"` and apply exclusions or stop those services before the run.

---

### `stressng_oom_risk` — Available Memory Critical

With only 128 MB of available memory remaining, the OOM killer may terminate stress-ng workers mid-run. This produces incomplete metrics and a `stress-ng: error: [pid] OOM killer terminated process` entry in the output.

**Resolution:** Reduce `workers` in the memory-stress profile, or increase swap space: `sudo fallocate -l 8G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`.

---

### `stressng_high_pagefile` — Pagefile Usage

Paging activity above 80% during a memory stress run means the OS is swapping anonymous pages to disk. This converts what should be a pure memory test into a mixed memory+storage test, corrupting bogo-ops/sec measurements for memory stressors.

**Resolution:** Reduce `workers` in `memory-stress.yml`, or run memory profiling only on nodes where total RAM exceeds 4× the expected working set.

---

### `stressng_disk_saturation` — Disk Time at Limit

The `hdd` and `iomix` stressors write continuously to `/tmp`. When disk time hits 98%, the storage path is saturated. Unlike fio (which measures this intentionally), in a stress-ng run this alert indicates the storage subsystem cannot keep pace with the VFS layer, which may cause the `io-stress` run to complete but with artificially low bogo-ops counts.

---

### `stressng_disk_error` — I/O Transfer Rate Drops to Zero

If the disk transfer rate drops to zero while `hdd` or `iomix` workers are active, a storage error has occurred — either the backing disk is full (`df -h /tmp`) or an I/O error was returned to the kernel (`dmesg | grep -i error`). This is critical because stress-ng will continue incrementing its run timer while workers are blocked, producing misleadingly low bogo-ops values.

---

## Monitoring During a Live Run

```powershell
# Sample key counters every 10 seconds while a stress run is active
$nodes = @("hci01-node1", "hci01-node2")
$counters = @(
    "\Processor Information(_Total)\% Processor Frequency",
    "\Memory\Available MBytes",
    "\LogicalDisk(_Total)\% Disk Time",
    "\Paging File(_Total)\% Usage"
)

Get-Counter -ComputerName $nodes -Counter $counters -SampleInterval 10 -Continuous |
    ForEach-Object {
        $ts = $_.Timestamp.ToString("HH:mm:ss")
        $_.CounterSamples | ForEach-Object {
            [PSCustomObject]@{
                Time    = $ts
                Node    = $_.Path.Split("\\")[2]
                Counter = ($_.Path -split "\\")[-1]
                Value   = [math]::Round($_.CookedValue, 1)
            }
        }
    } | Format-Table -AutoSize
```

---

## Customising Alert Thresholds

Edit `monitoring/stress-ng/alert-rules.yml` to adjust thresholds for your hardware:

```yaml
alert_rules:
  - name: stressng_oom_risk
    counter: \Memory\Available MBytes
    condition: <
    threshold: 256        # raised from 128 MB for safety on 64 GB nodes
    severity: critical
    message: "Less than 256 MB available — OOM risk during memory stress"
    cooldown_seconds: 30
```
