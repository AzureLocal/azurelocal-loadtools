# iPerf3 — Installation

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers deploying iPerf3 on Azure Local cluster nodes (Windows or Linux) and configuring SSH access required by the automation scripts.

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- Cluster nodes (Windows or Linux VMs) reachable via SSH (port 22)
- SSH key-based authentication configured — the `linux_ssh` credential must be available via Key Vault or interactively
- `iperf3` binary installed on each node (see below)
- Firewall rules permitting TCP/UDP on port 5201 between all cluster nodes (the default iPerf3 port)

## Install iPerf3

### Linux Nodes (Ubuntu/Debian)

```bash
# Install via package manager
sudo apt-get update && sudo apt-get install -y iperf3
iperf3 --version
```

### Linux Nodes (RHEL/Rocky/AlmaLinux)

```bash
sudo dnf install -y iperf3
iperf3 --version
```

### Windows Nodes

Download the iPerf3 Windows binary from the [iperf3 releases page](https://github.com/ar51an/iperf3-win-builds/releases) and place `iperf3.exe` in a directory on `$env:PATH` (e.g., `C:\tools\iperf3\`):

```powershell
# On the target Windows node (via PowerShell remoting)
Invoke-Command -ComputerName "hci01-node1" -ScriptBlock {
    $uri = "https://github.com/ar51an/iperf3-win-builds/releases/download/3.17.1/iperf3.exe"
    Invoke-WebRequest -Uri $uri -OutFile "C:\tools\iperf3\iperf3.exe"
    [System.Environment]::SetEnvironmentVariable("PATH",
        $env:PATH + ";C:\tools\iperf3", "Machine")
}
```

## Verify Installation

```bash
# From management station — SSH to each node
ssh user@hci01-node1 "iperf3 --version"
```

Expected: `iperf 3.x.x` on all nodes.

## SSH Key Configuration

`Start-IperfTest.ps1` uses SSH/SCP with `BatchMode=yes` (no password prompts). The `linux_ssh` credential must contain a path to a private key that is authorized on all target nodes.

```powershell
# Interactive credential prompt (for local runs)
.\tools\iperf\scripts\Start-IperfTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -Profile "tcp-throughput" `
    -CredentialSource Interactive   # Prompts for SSH username and key path
```

For CI/CD, store the private key path in Key Vault as the `linux_ssh` secret.

## Firewall Configuration

By default, iPerf3 uses **port 5201** for both the server listener and the data stream. All cluster nodes must allow inbound and outbound TCP/UDP on this port from each other:

```powershell
# Windows: add firewall rule on each cluster node
Invoke-Command -ComputerName @("hci01-node1", "hci01-node2", "hci01-node3") -ScriptBlock {
    New-NetFirewallRule `
        -Name "iPerf3" `
        -DisplayName "iPerf3 network test" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 5201 `
        -Action Allow
}
```

For Linux nodes, use `ufw allow 5201/tcp && ufw allow 5201/udp`.

## Remote Directory Structure

| Path | Purpose |
|------|---------|
| `/tmp/iperf-results/<RunId>/<client>-to-<server>.json` | Per-pair JSON result file |

Results are SCP-copied by `Collect-IperfResults.ps1` and removed from the remote node after successful collection.

## Next Steps

- [Workload Profiles](workload-profiles.md) — TCP throughput, UDP latency, or mesh all-to-all testing
- [Monitoring](monitoring.md) — Network and CPU alert thresholds during iPerf3 runs
