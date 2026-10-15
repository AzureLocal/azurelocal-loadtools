# VMFleet

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Status: Not proven on hardware](https://img.shields.io/badge/Hardware-Not%20proven-yellow?style=flat-square)
![VMFleet 2.1.0.0](https://img.shields.io/badge/VMFleet-2.1.0.0-blue?style=flat-square)

> [!NOTE]
> **Status: implemented and unit-tested, not proven on hardware.** See the [implementation status](../../reference/status.md) table. Command examples on this page show the intended workflow; the `param` block of each script is the authority for parameter names. Not proven on a live cluster.

VMFleet deploys a fleet of lightweight Server Core VMs across your Azure Local cluster nodes, each running DiskSpd workloads to stress-test Storage Spaces Direct (S2D). It measures IOPS, throughput, and latency under realistic storage load.

---

## Run This Test

### Prerequisites

- Azure Local cluster with Storage Spaces Direct enabled
- PowerShell 7.2+ on your management workstation
- WinRM access to all cluster nodes
- A Server Core base VHD on the cluster CSV
- [Framework prerequisites](../../getting-started/prerequisites.md) completed

### Option A — Run the Full Pipeline (Recommended)

The VMFleet orchestrator runs all phases end-to-end with checkpoint-based resume:

```powershell
# From the repository root
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath "config\clusters\my-cluster.yml" `
    -ProfilePath "tools\vmfleet\config\profiles\general.yml" `
    -FleetAdminCredential (Get-Credential -Message "Fleet VM admin")
```

If the pipeline fails mid-run, resume from the last checkpoint:

```powershell
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath "config\clusters\my-cluster.yml" `
    -Resume
```

### Option B — Run Each Step Manually

Run each phase independently. This is useful for debugging, re-running a single phase, or learning how the pipeline works.

**1. Install VMFleet on the cluster**

```powershell
.\tools\vmfleet\scripts\Install-VMFleet.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2")
```

**2. Deploy fleet VMs**

```powershell
.\tools\vmfleet\scripts\Deploy-VMFleet.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -VMCountPerNode 4 `
    -VMMemoryGB 2
```

**3. Start a workload test**

```powershell
.\tools\vmfleet\scripts\Start-VMFleetTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Profile "General" `
    -DurationSeconds 600
```

**4. Monitor in real-time** (run in a separate terminal)

```powershell
.\tools\vmfleet\scripts\Watch-VMFleetMonitor.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com"
```

**5. Stop the test** (if needed before duration completes)

```powershell
.\tools\vmfleet\scripts\Stop-VMFleetTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com"
```

**6. Collect and aggregate results**

```powershell
.\tools\vmfleet\scripts\Collect-VMFleetResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -RunId "<run-id>"
```

**7. Clean up fleet VMs** (optional)

```powershell
.\tools\vmfleet\scripts\Remove-VMFleet.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com"
```

---

## Available Workload Profiles

| Profile | Write % | Random % | Block Size | Target IOPS | Use Case |
|---------|---------|----------|------------|-------------|----------|
| General | 30% | 70% | 8K | ~5,000 | Balanced mixed workload baseline |
| Peak IOPS | 0% | 100% | 4K | ~50,000 | Maximum random read throughput |
| VDI | 20% | 80% | 8K | ~3,000 | Virtual desktop simulation |
| SQL OLTP | 30% | 100% | 8K | ~10,000 | SQL Server transaction processing |
| Sequential Throughput | 100% | 0% | 512K | N/A (MB/s) | Sequential write ceiling |

Profile YAML files are in `tools/vmfleet/config/profiles/`.

---

## What You Get

After a test completes, you will have:

- **Raw DiskSpd XML** per VM per node in `tools/vmfleet/logs/`
- **Aggregated JSON metrics** with IOPS, throughput (MB/s), and latency (ms) per profile
- **Reports** in PDF, DOCX, and/or XLSX format (if `--GenerateReports` was used)

---

## File Locations

| Component | Path |
|-----------|------|
| Orchestrator | `tools/vmfleet/Invoke-VMFleetPipeline.ps1` |
| Scripts | `tools/vmfleet/scripts/` |
| Workload Profiles | `tools/vmfleet/config/profiles/` |
| Monitoring Collectors | `tools/vmfleet/monitoring/collectors/` |
| Alert Rules | `tools/vmfleet/monitoring/alerts/alert-rules.yml` |
| Azure Monitor Workbook | `tools/vmfleet/monitoring/workbooks/vmfleet-workbook.json` |
| Report Templates | `tools/vmfleet/reports/templates/` |
| Logs | `tools/vmfleet/logs/` |

---

## Deep Dive

| Topic | Page |
|-------|------|
| Cluster and VMFleet requirements | [Prerequisites](prerequisites.md) |
| VM deployment details | [Deployment](deployment.md) |
| Profile parameters and tuning | [Workload Profiles](workload-profiles.md) |
| Metric collection and dashboards | [Monitoring](monitoring.md) |
| Report formats and templates | [Reporting](reporting.md) |
| Common errors and fixes | [Troubleshooting](troubleshooting.md) |

---

## Automate This Test

To run VMFleet on a schedule or as part of a CI/CD workflow, see [CI/CD Pipelines](../../operations/ci-cd.md). The `run-vmfleet.yml` GitHub Actions workflow calls the same `Invoke-VMFleetPipeline.ps1` script above with parameters from workflow dispatch inputs.

---

## More VMFleet guides

- [Failure injection (opt-in)](failure-injection.md): measure storage performance while one node is paused or one drive is out
- [Reports, comparison and regression gate](regression-gate.md): offline HTML and CSV report, baseline comparison with an exit code
- [Day-2 smoke](../../reference/day2-smoke.md): a 15-minute General run for a readiness gate, with a JSON result
- [Implementation status](../../reference/status.md)
