# fio — Flexible I/O Tester

![Tool: fio](https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square)
![Status: Structure Ready](https://img.shields.io/badge/Status-Structure%20Ready-yellow?style=flat-square)

fio provides fine-grained storage I/O benchmarking with precise control over block sizes, queue depths, I/O engines, and workload patterns. It runs inside Linux VMs on the Azure Local cluster via Ansible deployment.

---

## Run This Test

### Prerequisites

- Linux VMs deployed on your Azure Local cluster
- Ansible 2.14+ installed on your management workstation
- SSH key-based access to Linux VMs
- [Framework prerequisites](../../getting-started/prerequisites.md) completed

### Step 1 — Install fio on target VMs

```powershell
.\tools\fio\scripts\Install-Fio.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2")
```

This triggers an Ansible playbook that installs the `fio` package on the specified Linux VMs.

### Step 2 — Run a workload profile

```powershell
.\tools\fio\scripts\Start-FioTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -Profile "random-read" `
    -DurationSeconds 300
```

### Step 3 — Collect results

```powershell
.\tools\fio\scripts\Collect-FioResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -RunId "<run-id-from-previous-step>"
```

---

## When to Use fio vs VMFleet

| Scenario | Use fio | Use VMFleet |
|----------|---------|-------------|
| Linux VM storage performance | :white_check_mark: | |
| Fine-grained I/O parameter control | :white_check_mark: | |
| Fleet-scale Windows HCI storage load | | :white_check_mark: |
| Data integrity verification | :white_check_mark: | |
| I/O scheduler / queue depth testing | :white_check_mark: | |

## Key Capabilities

- **Job file-based** workload definition for reproducible tests
- **Multiple I/O engines** — libaio, io_uring, Windows IOCP
- **JSON output** for automated parsing and reporting
- **Verification mode** for data integrity testing
- **Client/server mode** for distributed I/O testing across nodes

---

## What You Get

After a test completes, you will have:

- **JSON output** per node with IOPS, bandwidth (KB/s), and latency percentiles
- **Aggregated metrics** across all nodes
- **Reports** in PDF, DOCX, and/or XLSX format

---

## File Locations

| Component | Path |
|-----------|------|
| Scripts | `tools/fio/scripts/` |
| Workload Profiles | `tools/fio/config/profiles/` |
| Ansible Playbooks | `tools/fio/playbooks/` |
| Alert Rules | `tools/fio/monitoring/alert-rules.yml` |
| Report Templates | `tools/fio/reports/templates/` |
| Tests | `tools/fio/tests/` |
| Logs | `tools/fio/logs/` |

---

## Deep Dive

| Topic | Page |
|-------|------|
| Ansible deployment details | [Installation](installation.md) |
| Profile parameters and tuning | [Workload Profiles](workload-profiles.md) |
| Alert rules during test runs | [Monitoring](monitoring.md) |
| Report formats and templates | [Reporting](reporting.md) |
| Common errors and fixes | [Troubleshooting](troubleshooting.md) |

---

## Automate This Test

To run fio tests on a schedule or as part of a CI/CD workflow, see [CI/CD Pipelines](../../operations/ci-cd.md). The pipeline calls the same scripts listed above.
