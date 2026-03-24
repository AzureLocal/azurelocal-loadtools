# fio — Troubleshooting

![Tool: fio](https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

## SSH Connection Failures

**Symptom:** `Start-FioTest.ps1` exits with `SSH connection refused` or `Permission denied (publickey)`.

**Resolution:**

1. Verify the target node is reachable: `Test-NetConnection hci01-node1 -Port 22`
2. Confirm the SSH key is loaded: `ssh -i ~/.ssh/id_rsa user@hci01-node1 "echo ok"`
3. Check that the `linux_ssh` credential contains the correct private key path
4. Ensure `BatchMode=yes` is supported — password auth will fail silently in non-interactive mode

---

## fio Not Found on Remote Node

**Symptom:** `Start-FioTest.ps1` fails with `bash: fio: command not found`.

**Resolution:**

Run `Install-Fio.ps1` first:

```powershell
.\tools\fio\scripts\Install-Fio.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2")
```

After installation, confirm: `ssh user@hci01-node1 "fio --version"`

---

## fio Version Too Old

**Symptom:** `Collect-FioResults.ps1` fails with JSON parse errors or missing `lat_ns` keys.

**Cause:** fio older than 3.28 uses a different JSON schema — `lat_ns` was introduced in 3.0 but `percentile` keys changed in 3.28.

**Resolution:** Upgrade fio on the target nodes. Use the Ansible playbook to force re-installation:

```yaml
# In your Ansible inventory or playbook, pin the required version
- name: Install fio
  apt:
    name: fio
    state: latest
```

---

## SCP Retrieval Fails

**Symptom:** `Collect-FioResults.ps1` exits with `No such file or directory: /tmp/fio-results/<RunId>/`.

**Cause:** `Start-FioTest.ps1` did not complete successfully, or the remote results directory was already cleaned up.

**Resolution:**

```bash
# SSH to the node and check if the directory exists
ssh user@hci01-node1 "ls -la /tmp/fio-results/"

# If missing, re-run Start-FioTest.ps1 with the same RunId
# If you need to preserve RunId, pass -RunId explicitly
```

---

## Results Show Zero IOPS

**Symptom:** Aggregate JSON shows `read_iops: 0` or `write_iops: 0` for a profile expecting non-zero values.

**Possible Causes:**

- Wrong `rw` mode in the profile (e.g., `write` profile run when checking read IOPS)
- fio ran but hit an error mid-test; the result JSON is partially written
- Test directory `/tmp/fio-test/` is on `tmpfs` (memory) rather than the target block device

**Resolution:**

```bash
# Verify the test directory targets a real block device, not tmpfs
ssh user@hci01-node1 "df -hT /tmp/fio-test/"
# Should show ext4 or xfs, not tmpfs
```

---

## High Latency Despite Low IOPS

**Symptom:** Profile shows both low IOPS and high latency simultaneously — more than just a threshold miss.

**Possible Causes:**

- S2D storage not optimally configured (dirty region tracking, cache tier exhausted)
- Thermal throttling on NVMe drives
- Cluster nodes reporting `fio_high_disk_latency` alert (see [Monitoring](monitoring.md))

**Resolution:**

```powershell
# Check S2D cache health on the cluster
Invoke-Command -ComputerName "hci01-node1" -ScriptBlock {
    Get-PhysicalDisk | Select-Object FriendlyName, HealthStatus, Usage, Size
    Get-StorageTier | Select-Object FriendlyName, Size, RemainingSize
}
```

---

## Test Produces Inconsistent Results Across Runs

**Symptom:** Sequential IOPS vary by more than 20% between identical runs.

**Possible Causes:**

- Insufficient warmup — fio starts measurement too quickly
- Other workloads active on the cluster during the test
- NVMe SLC cache saturation between runs (NVMe drives in SLC mode initially, then drops to QLC speed)

**Resolution:** Add 60-second warmup (the profiles use `runtime_seconds` only for the measured window — ensure no pre-existing workload is running):

```powershell
# Check for competing I/O on the cluster before running
Invoke-Command -ComputerName "hci01-node1" -ScriptBlock {
    Get-Counter '\PhysicalDisk(_Total)\Disk Transfers/sec' -SampleInterval 5 -MaxSamples 3
}
```

---

## For Additional Help

See the [Operations Troubleshooting Guide](../../operations/troubleshooting.md) for cross-tool issues including WinRM/SSH connectivity, credential resolution, and log correlation.
