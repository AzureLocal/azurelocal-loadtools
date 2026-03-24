# fio — Flexible I/O Tester

!!! note "This page has moved"
    The main fio landing page with run instructions is now at [fio](index.md). This page contains additional technical details.

![Tool: fio](https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square)
![Status: Implemented](https://img.shields.io/badge/Status-Implemented-brightgreen?style=flat-square)

## Purpose

Fine-grained storage I/O benchmarking with extensive control over workload parameters. Runs inside Linux VMs on the cluster.

## When to Use

- Need precise control over I/O patterns beyond VMFleet's profiles
- Testing Linux VM storage performance specifically
- Validating I/O scheduler behavior, queue depths, or specific block sizes
- Client/server mode for distributed I/O testing

## Key Capabilities

- Job file-based workload definition
- Multiple I/O engines (libaio, io_uring, Windows IOCP)
- JSON output for automated parsing
- Verification mode for data integrity testing

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- Linux VMs deployed on the Azure Local cluster
- Ansible 2.14+ for deployment (see [Ansible Requirements](../../getting-started/prerequisites.md#ansible-requirements-for-linux-based-tools))
- fio package installed on target VMs (automated via Ansible role)

## Quick Start

```powershell
# 1. Deploy fio to Linux VMs
.\tools\fio\scripts\Install-Fio.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2")

# 2. Run a workload profile
.\tools\fio\scripts\Start-FioTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -Profile "random-read"

# 3. Collect and normalize results
.\tools\fio\scripts\Collect-FioResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -RunId "<run-id-from-previous-step>"
```

## File Locations

| Component | Path |
| --- | --- |
| Scripts | `tools/fio/scripts/` |
| Profiles | `tools/fio/config/profiles/` |
| Alert Rules | `tools/fio/monitoring/alerts/alert-rules.yml` |
| Report Templates | `tools/fio/reports/templates/` |
| Tests | `tools/fio/tests/` |

## fio Documentation

| Document | Description |
| --- | --- |
| [Installation](installation.md) | Deploy fio to Linux VMs via Ansible |
| [Workload Profiles](workload-profiles.md) | Built-in profiles and profile configuration |
| [Monitoring](monitoring.md) | Alert rules active during fio runs |
| [Reporting](reporting.md) | Result collection and report generation |
| [Troubleshooting](troubleshooting.md) | Common issues and resolutions |
