# HammerDB — Database Benchmarking

![Tool: HammerDB](https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square)
![Status: Structure Ready](https://img.shields.io/badge/Status-Structure%20Ready-yellow?style=flat-square)

HammerDB benchmarks SQL Server performance on Azure Local VMs using industry-standard TPC-C (OLTP) and TPC-H (OLAP) workloads. It measures transactions per minute (TPM) and new orders per minute (NOPM).

---

## Run This Test

### Prerequisites

- SQL Server instance deployed on an Azure Local VM
- HammerDB installed on the management station or target VM
- WinRM access to the target VM
- [Framework prerequisites](../../getting-started/prerequisites.md) completed

### Step 1 — Install HammerDB on the target VM

```powershell
.\tools\hammerdb\scripts\Install-HammerDB.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1")
```

### Step 2 — Run the TPC-C benchmark

```powershell
.\tools\hammerdb\scripts\Start-HammerDBTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1" `
    -Profile "tpc-c" `
    -Warehouses 100 `
    -VirtualUsers 16
```

### Step 3 — Collect results

```powershell
.\tools\hammerdb\scripts\Collect-HammerDBResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1" `
    -RunId "<run-id-from-previous-step>"
```

### Step 4 — Stop the test (if needed)

```powershell
.\tools\hammerdb\scripts\Stop-HammerDBTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1"
```

---

## When to Use HammerDB

| Scenario | HammerDB |
|----------|----------|
| Validate SQL Server OLTP performance | :white_check_mark: |
| TPC-C transaction benchmarking | :white_check_mark: |
| TPC-H analytics query benchmarking | :white_check_mark: |
| Combined storage + compute validation | :white_check_mark: |
| Database sizing and capacity planning | :white_check_mark: |

## Key Capabilities

- **TPC-C** (TPROC-C) — OLTP transaction processing simulation
- **TPC-H** (TPROC-H) — Decision support / analytics query workload
- **Supports** SQL Server, PostgreSQL, MySQL, Oracle, and more
- **GUI, CLI, and web** interfaces for flexibility
- **Docker images** available for reproducible CI/CD runs

---

## What You Get

After a test completes, you will have:

- **NOPM** (New Orders Per Minute) — the primary TPC-C metric
- **TPM** (Transactions Per Minute) — total throughput
- **TPC-H query times** for analytics workloads
- **Reports** in PDF, DOCX, and/or XLSX format

---

## File Locations

| Component | Path |
|-----------|------|
| Scripts | `tools/hammerdb/scripts/` |
| Workload Profiles | `tools/hammerdb/config/profiles/` |
| Alert Rules | `tools/hammerdb/monitoring/alert-rules.yml` |
| Report Templates | `tools/hammerdb/reports/templates/` |
| Tests | `tools/hammerdb/tests/` |
| Logs | `tools/hammerdb/logs/` |

---

## Deep Dive

| Topic | Page |
|-------|------|
| Installation via PowerShell remoting | [Installation](installation.md) |
| TPC-C and TPC-H profile configuration | [Workload Profiles](workload-profiles.md) |
| Alert rules during test runs | [Monitoring](monitoring.md) |
| Report formats and templates | [Reporting](reporting.md) |
| Common errors and fixes | [Troubleshooting](troubleshooting.md) |

---

## Automate This Test

To run HammerDB on a schedule or as part of a CI/CD workflow, see [CI/CD Pipelines](../../operations/ci-cd.md). The pipeline calls the same scripts listed above.
