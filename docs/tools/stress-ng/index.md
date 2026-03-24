# stress-ng — System Stress Testing

![Tool: stress-ng](https://img.shields.io/badge/Tool-stress--ng-F39C12?style=flat-square)
![Status: Structure Ready](https://img.shields.io/badge/Status-Structure%20Ready-yellow?style=flat-square)

stress-ng performs CPU, memory, cache, and I/O stress testing for capacity planning and burn-in validation. It includes 370+ stressors and runs on Linux VMs via Ansible deployment.

---

## Run This Test

### Prerequisites

- Linux VMs deployed on your Azure Local cluster
- Ansible 2.14+ installed on your management workstation
- SSH key-based access to Linux VMs
- [Framework prerequisites](../../getting-started/prerequisites.md) completed

### Step 1 — Install stress-ng on target VMs

```powershell
.\tools\stress-ng\scripts\Install-StressNg.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2")
```

### Step 2 — Run a stress test

```powershell
.\tools\stress-ng\scripts\Start-StressNgTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -Profile "cpu-stress" `
    -DurationSeconds 600
```

### Step 3 — Collect results

```powershell
.\tools\stress-ng\scripts\Collect-StressNgResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -RunId "<run-id-from-previous-step>"
```

---

## When to Use stress-ng

| Scenario | stress-ng |
|----------|-----------|
| CPU thermal and power validation | :white_check_mark: |
| Memory stability under pressure | :white_check_mark: |
| Burn-in testing of new cluster nodes | :white_check_mark: |
| Determine maximum safe CPU utilization | :white_check_mark: |
| Cache and TLB stress testing | :white_check_mark: |

## Key Capabilities

- **370+ stressors** across CPU, memory, filesystem, network, and OS categories
- **YAML job files** for reproducible configurations
- **Metrics** — bogo ops/s, thermal zone readings, power measurement
- **Stressor classes** for targeted testing (cpu, memory, io, network, etc.)
- **Verification** mode for checking compute accuracy under load

---

## What You Get

After a test completes, you will have:

- **Bogo ops/s** (bogus operations per second) per stressor per node
- **Thermal readings** if available on hardware
- **Aggregated metrics** across all nodes
- **Reports** in PDF, DOCX, and/or XLSX format

---

## File Locations

| Component | Path |
|-----------|------|
| Scripts | `tools/stress-ng/scripts/` |
| Workload Profiles | `tools/stress-ng/config/profiles/` |
| Ansible Playbooks | `tools/stress-ng/playbooks/` |
| Alert Rules | `tools/stress-ng/monitoring/alert-rules.yml` |
| Report Templates | `tools/stress-ng/reports/templates/` |
| Tests | `tools/stress-ng/tests/` |
| Logs | `tools/stress-ng/logs/` |

---

## Deep Dive

| Topic | Page |
|-------|------|
| Ansible deployment details | [Installation](installation.md) |
| CPU, memory, and I/O profiles | [Workload Profiles](workload-profiles.md) |
| Alert rules during test runs | [Monitoring](monitoring.md) |
| Report formats and templates | [Reporting](reporting.md) |
| Common errors and fixes | [Troubleshooting](troubleshooting.md) |

---

## Automate This Test

To run stress-ng on a schedule or as part of a CI/CD workflow, see [CI/CD Pipelines](../../operations/ci-cd.md). The pipeline calls the same scripts listed above.
