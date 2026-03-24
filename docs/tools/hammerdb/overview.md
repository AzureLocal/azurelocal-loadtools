# HammerDB — Database Benchmarking

!!! note "This page has moved"
    The main HammerDB landing page with run instructions is now at [HammerDB](index.md). This page contains additional technical details.

![Tool: HammerDB](https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square)
![Status: Implemented](https://img.shields.io/badge/Status-Implemented-brightgreen?style=flat-square)

## Purpose

Database workload benchmarking for SQL Server running on Azure Local VMs.

## When to Use

- Validating SQL Server performance on the cluster
- OLTP (TPROC-C) workload benchmarking
- OLAP/analytics (TPROC-H) workload benchmarking
- Combined storage + compute performance validation

## Key Capabilities

- Supports SQL Server, PostgreSQL, MySQL, Oracle, and more
- TPC-C and TPC-H benchmark profiles
- GUI, CLI, and web interfaces
- Docker images for reproducible CI/CD runs

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- SQL Server instance deployed on an Azure Local VM
- HammerDB installed on the management station or target VM
- Ansible 2.14+ for automated deployment

## Quick Start

```powershell
# 1. Install HammerDB on the target Windows VM
.\tools\hammerdb\scripts\Install-HammerDB.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1")

# 2. Run the TPC-C benchmark
.\tools\hammerdb\scripts\Start-HammerDBTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1" `
    -Profile "tpc-c"

# 3. Collect NOPM/TPM results
.\tools\hammerdb\scripts\Collect-HammerDBResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1" `
    -RunId "<run-id-from-previous-step>"
```

## File Locations

| Component | Path |
| --- | --- |
| Scripts | `tools/hammerdb/scripts/` |
| Profiles | `tools/hammerdb/config/profiles/` |
| Alert Rules | `tools/hammerdb/monitoring/alerts/alert-rules.yml` |
| Report Templates | `tools/hammerdb/reports/templates/` |
| Tests | `tools/hammerdb/tests/` |

## HammerDB Documentation

| Document | Description |
| --- | --- |
| [Installation](installation.md) | Install HammerDB on Windows VMs via PowerShell remoting |
| [Workload Profiles](workload-profiles.md) | TPC-C and TPC-H profile configuration |
| [Monitoring](monitoring.md) | Alert rules active during HammerDB runs |
| [Reporting](reporting.md) | Result collection and report generation |
| [Troubleshooting](troubleshooting.md) | Common issues and resolutions |
