# stress-ng — Troubleshooting

![Tool: stress-ng](https://img.shields.io/badge/Tool-stress--ng-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

## stress-ng Not Found on Target Node

**Symptom:** `Start-StressNgTest.ps1` returns `bash: stress-ng: command not found` from one or more nodes.

**Resolution:**

```bash
# Ubuntu
sudo apt-get install -y stress-ng

# Rocky Linux / RHEL
sudo dnf install -y epel-release && sudo dnf install -y stress-ng
```

See [Installation](installation.md) for the version verification procedure across all nodes.

---

## OOM Killer Terminates Workers Mid-Run

**Symptom:** The run completes but the per-node YAML contains fewer stressor entries than expected, or `Collect-StressNgResults.ps1` reports a `node_count` mismatch.

**Diagnostic:**

```bash
ssh azurelocaladmin@hci01-node1 "dmesg | grep -i 'Killed process' | tail -5"
```

If `stress-ng` appears in the output, the OOM killer fired.

**Resolution:**

```bash
# Check available memory before the run
ssh azurelocaladmin@hci01-node1 "free -h"
```

Then either reduce `workers` in `memory-stress.yml` (e.g. from 4 → 2) or add temporary swap:

```bash
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## Bogo-ops Count Is Zero for One Stressor

**Symptom:** The aggregate JSON shows `total_bogo_ops: 0` for a specific stressor (e.g., `hdd`).

**Cause:** The `hdd` stressor writes temporary files to `/tmp`. If that filesystem is full, every write returns an error and no operations complete.

**Diagnostic:**

```bash
ssh azurelocaladmin@hci01-node1 "df -h /tmp"
```

**Resolution:**

```bash
# Clean up residual test files from previous runs
ssh azurelocaladmin@hci01-node1 "rm -rf /tmp/stress-ng-results/ && df -h /tmp"
```

If `/tmp` is a separate tmpfs, increase its size in `/etc/fstab`:

```
tmpfs  /tmp  tmpfs  defaults,size=16G  0 0
```

---

## CPU Throttling — Low Bogo-ops Compared to Baseline

**Symptom:** `avg_bogo_ops_per_sec` for the `cpu` stressor is 20%+ below a previous baseline run on identical hardware.

**Investigation:**

```powershell
# Check CPU frequency counter on the affected node
Get-Counter "\Processor Information(_Total)\% Processor Frequency" `
    -ComputerName "hci01-node1" -SampleInterval 5 -MaxSamples 6 |
    ForEach-Object { $_.CounterSamples | Select-Object CookedValue }
```

If the frequency is below 80% of rated, the `stressng_cpu_throttling` alert will have fired. Review:

- BIOS power profile (set to Maximum Performance, not Balanced)
- Chassis airflow / fan curves
- `turbostat` on the Linux node: `sudo turbostat --quiet --show CPU,Bzy_MHz,Avg_MHz --interval 5`

---

## YAML Parse Failure — PowerShell Key Access Error

**Symptom:** `Collect-StressNgResults.ps1` throws `The property 'stress-ng' cannot be found on this object`.

**Cause:** PowerShell cannot access a property with a hyphen using dot notation.

**Resolution:** Use single-quote notation for the hyphenated key:

```powershell
# Wrong
$metrics = $parsed."stress-ng".metrics

# Correct
$metrics = $parsed.'stress-ng'.metrics
```

This is documented in [Reporting](reporting.md#yaml-key-note). If you customised the collection script and introduced dot notation, revert to quoted access.

---

## SSH Connectivity Issues

**Symptom:** `Start-StressNgTest.ps1` fails with `Permission denied (publickey)`.

See the [Operations Troubleshooting Guide](../../operations/troubleshooting.md) for full SSH key resolution steps. Quick check:

```powershell
ssh -i "$env:USERPROFILE\.ssh\azurelocal_rsa" -o BatchMode=yes `
    "azurelocaladmin@hci01-node1" "echo ok"
```

If this returns `ok`, the key is correct. If it hangs or returns `Permission denied`, the key has not been distributed to that node — re-run `ssh-copy-id`.

---

## Inconsistent Bogo-ops Across Nodes (Same Hardware)

**Symptom:** Node bogo-ops/sec values differ by more than 10% across nodes with identical CPU and RAM.

**Common Causes:**

| Cause | Diagnostic | Fix |
|-------|-----------|-----|
| Background process (backup, AV scan) | `Get-Process -ComputerName node` sorted by CPU | Schedule maintenance windows outside test runs |
| NUMA imbalance | `numactl --hardware` on each node | Pin `workers` to specific NUMA nodes: `stress-ng --cpu 16 --taskset 0-15` |
| Different BIOS power profiles per node | `powercfg /query` | Set consistent BIOS/hypervisor policy across all nodes |
| VM density difference | One node running extra VMs | Drain excess VMs before running stress-ng tests |
