# stress-ng — Installation

![Tool: stress-ng](https://img.shields.io/badge/Tool-stress--ng-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

stress-ng is a Linux kernel stress tool installed directly on target nodes using the standard package manager. There is no dedicated `Install-StressNg.ps1` script; the runner orchestrates test execution over SSH once the package is installed.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Target OS | Ubuntu 22.04 / Rocky Linux 9 (or any systemd Linux with `apt` or `dnf`) |
| stress-ng version | 0.15.00 or later |
| Runner OS | Windows Server 2022 with PowerShell 7.3+ |
| SSH access | Key-based auth; `linux_ssh` credential in variables file |
| Results directory | Created automatically at `/tmp/stress-ng-results/<RunId>/` |
| Ansible | Not required — SSH commands issued directly from PowerShell via `ssh.exe` |

---

## Installing stress-ng on Target Nodes

### Ubuntu / Debian

```bash
sudo apt-get update -qq
sudo apt-get install -y stress-ng

# Verify
stress-ng --version
# stress-ng, version 0.15.06
```

### Rocky Linux / RHEL

```bash
sudo dnf install -y epel-release
sudo dnf install -y stress-ng

stress-ng --version
```

### Verify Across All Cluster Nodes

From the runner, iterate over all target nodes defined in your variables file:

```powershell
$nodes = @("hci01-node1", "hci01-node2", "hci01-node3", "hci01-node4")
$sshUser = "azurelocaladmin"

foreach ($node in $nodes) {
    $ver = ssh -i "$env:USERPROFILE\.ssh\azurelocal_rsa" `
               -o BatchMode=yes `
               "$sshUser@$node" "stress-ng --version 2>&1"
    Write-Host "$node: $ver"
}
```

Expected output:

```
hci01-node1: stress-ng, version 0.15.06
hci01-node2: stress-ng, version 0.15.06
hci01-node3: stress-ng, version 0.15.06
hci01-node4: stress-ng, version 0.15.06
```

---

## SSH Key Configuration

`Start-StressNgTest.ps1` connects to each node as the non-root SSH user defined in your cluster variables file. The key pair must be pre-distributed.

```powershell
# Generate key pair once on the runner (if not already present)
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\azurelocal_rsa" -C "azurelocal-loadtools"

# Distribute to each node
foreach ($node in @("hci01-node1","hci01-node2","hci01-node3","hci01-node4")) {
    ssh-copy-id -i "$env:USERPROFILE\.ssh\azurelocal_rsa.pub" `
                "azurelocaladmin@$node"
}
```

Set the `linux_ssh` credential block in your variables file:

```yaml
# config/variables.yml
credentials:
  linux_ssh:
    username: azurelocaladmin
    private_key_path: C:\Users\RunnerUser\.ssh\azurelocal_rsa
```

---

## Remote Paths Created at Runtime

| Path | Purpose |
|------|---------|
| `/tmp/stress-ng-results/<RunId>/` | Per-run results directory (created by `Start-StressNgTest.ps1`) |
| `/tmp/stress-ng-results/<RunId>/stress-ng-results.yml` | Raw stress-ng YAML output per node |

These directories are created on each target node by the test script via SSH; no manual creation is required.

---

## Verifying readiness before a run

```powershell
# Quick pre-flight: confirm stress-ng responds and sudo is passwordless for kill signals
ssh -i "$env:USERPROFILE\.ssh\azurelocal_rsa" `
    -o BatchMode=yes `
    "azurelocaladmin@hci01-node1" `
    "stress-ng --cpu 1 --timeout 2s --metrics-brief 2>&1 | tail -3"
```

A healthy response ends with a line similar to:

```
stress-ng: info:  [12345] successful run completed in 2.00s (1 stressor spawned)
```
