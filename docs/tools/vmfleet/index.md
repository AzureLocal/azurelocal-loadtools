# VMFleet

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Status: Not proven on hardware](https://img.shields.io/badge/Hardware-Not%20proven-yellow?style=flat-square)
![VMFleet 2.1.0.0](https://img.shields.io/badge/VMFleet-2.1.0.0-blue?style=flat-square)

> [!NOTE]
> **Status: implemented and unit-tested, not proven on hardware.** See the [implementation status](../../reference/status.md) table. The scripts are tested against stubs that have the real VMFleet 2.1.0.0 parameter lists; nobody has run them on a live cluster yet, so expect to find problems on the first run. The `param` block of each script is the authority for parameter names.

VMFleet deploys a fleet of lightweight Windows Server VMs across your Azure Local cluster nodes, each running DiskSpd workloads to stress-test Storage Spaces Direct (S2D). It measures IOPS, throughput, and latency under realistic storage load.

The scripts are run from a management host that does **not** have to be domain-joined: it reaches each node by its management IP over WinRM with an explicit credential, and every VMFleet step runs as a one-shot scheduled task on the first node (VMFleet must run on a cluster node). How and why: [Deployment](deployment.md#how-the-scripts-reach-the-cluster).

---

## Run This Test

### Prerequisites

- Azure Local cluster with Storage Spaces Direct, a CSV named `collect` and one CSV per node named after the node ([Prerequisites](prerequisites.md))
- PowerShell 7.2+ and the `powershell-yaml` module on the management host; the node IPs in `TrustedHosts`
- A domain credential that is an administrator on every node (`-Credential`) and the local administrator password for the fleet VMs (`-FleetAdminCredential`)
- `config\clusters\cluster.yml`: copy `config\clusters\example-cluster.yml` and edit it ([Deployment](deployment.md#cluster-configuration))
- A Generation 2 base VHDX on the cluster: [Deployment: Base image](deployment.md#base-image)

```powershell
$cred       = Get-Credential -Message 'DOMAIN\user, an administrator on every node'
$fleetAdmin = Get-Credential -UserName 'Administrator' -Message 'Local administrator password for the fleet VMs'
```

### The runbook: Day2Smoke, General, cleanup

**(a) Day2Smoke, about 15 minutes.** Installs VMFleet, deploys the fleet, runs the profile, evaluates the result against the profile thresholds and keeps the fleet (`-SkipCleanup`):

```powershell
.\tools\vmfleet\scripts\Invoke-Day2Smoke.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml `
    -Credential $cred -FleetAdminCredential $fleetAdmin `
    -VMCount 4 -SkipCleanup -OutputPath out\day2smoke
```

It asks for confirmation (`-Confirm:$false` skips it) and exits 0 Pass, 1 Fail, 2 Error, 3 Skipped; `out\day2smoke\day2smoke-result.json` always holds the outcome ([Day-2 smoke](../../reference/day2-smoke.md)).

**(b) The General profile, the whole pipeline including the deploy phase.** The install and deploy phases are repeatable: with the fleet from (a) present they reuse it:

```powershell
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml `
    -ProfilePath tools\vmfleet\config\profiles\general.yml `
    -Credential $cred -FleetAdminCredential $fleetAdmin `
    -VMCount 4 -RunId general-001 -SkipCleanup
```

The reports are in `reports\general-001\`: the aggregate and per-VM JSON, an HTML report and a CSV (no extra tool needed), and a metrics dashboard. `-ReportFormats` also takes `PDF` (needs asciidoctor-pdf), `DOCX` (asciidoctor and pandoc) and `XLSX` (ImportExcel); a format whose tool is missing is skipped with a warning. If the run fails, `-Resume` continues from the last checkpoint.

**(c) Cleanup.** Removes every fleet VM and its files, then verifies that none is left:

```powershell
.\tools\vmfleet\scripts\Remove-VMFleet.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml -Credential $cred `
    -RemoveCollectData -Confirm:$false
```

(Leave out `-SkipCleanup` in (b) and the pipeline runs the same cleanup as its last phase.)

### Run each step manually

Every step takes `-ClusterConfigPath`, `-Credential` and an optional `-RunId`; run them in this order:

```powershell
# 1. Install the VMFleet module and run Install-Fleet on the first node
.\tools\vmfleet\scripts\Install-VMFleet.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred

# 2. Deploy the fleet VMs (New-Fleet, Set-Fleet, Start-Fleet)
.\tools\vmfleet\scripts\Deploy-VMFleet.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred `
    -FleetAdminCredential $fleetAdmin -VMCount 4

# 3. Run the workload (Start-FleetSweep). It blocks until the run is over; -NoWait returns at once.
.\tools\vmfleet\scripts\Start-VMFleetTest.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred `
    -ProfilePath tools\vmfleet\config\profiles\general.yml -RunId general-001

# 4. Live counters in a second window while it runs (optional)
.\tools\vmfleet\scripts\Watch-VMFleetMonitor.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred

# 5. Stop the fleet (Stop-Fleet shuts the fleet VMs down)
.\tools\vmfleet\scripts\Stop-VMFleetTest.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred

# 6. Collect the DiskSpd results of the run into reports\general-001\
.\tools\vmfleet\scripts\Collect-VMFleetResults.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred -RunId general-001

# 7. Remove the fleet
.\tools\vmfleet\scripts\Remove-VMFleet.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred -Confirm:$false
```

Use the same `-RunId` for the test and the collect step: it tags the DiskSpd result files, so a repeated run never picks up an old result.

---

## Available Workload Profiles

| Profile | Write % | Random % | Block Size | Use Case |
|---------|---------|----------|------------|----------|
| General | 30% | 70% | 8K | Balanced mixed workload baseline |
| Day2Smoke | 30% | 70% | 8K | General, shortened to about 15 minutes |
| Peak IOPS | 0% | 100% | 4K | Maximum random read throughput |
| VDI | 20% | 80% | 8K | Virtual desktop simulation |
| SQL OLTP | 30% | 100% | 8K | SQL Server transaction processing |
| Sequential Throughput | 100% | 0% | 512K | Sequential write ceiling |

Profile YAML files are in `tools/vmfleet/config/profiles/`. VMFleet's sweep runs a single pattern, random or sequential: a `random_ratio` of 50 or more runs random, below 50 sequential, so a mix such as 70% random runs as 100% random (the script warns).

---

## What You Get

After a test completes, you will have:

- **Raw DiskSpd XML** per VM on the Collect volume, in `<collect>\result` on the cluster (named `result-...-<run tag>-<vm>.xml`)
- **Aggregated JSON metrics** (`reports\<run id>\<run id>-aggregate.json` and `-per-vm.json`) with IOPS, throughput (MB/s) and latency (ms)
- **Reports**: HTML and CSV by default; PDF, DOCX and XLSX when their tools are installed
- **Transcripts** of every node-side step in `<collect>\loadtools\<run id>\<step>\transcript.log`, with `result.json`

---

## File Locations

| Component | Path |
|-----------|------|
| Orchestrator | `tools/vmfleet/Invoke-VMFleetPipeline.ps1` |
| Scripts | `tools/vmfleet/scripts/` |
| Shared remoting helper | `tools/vmfleet/scripts/VMFleet-Common.ps1` |
| Node-side scripts (run on the node) | `tools/vmfleet/scripts/node/` |
| Base image preparation | `tools/vmfleet/infrastructure/Prepare-VMFleetBaseImage.ps1` |
| Workload Profiles | `tools/vmfleet/config/profiles/` |
| Monitoring Collectors | `tools/vmfleet/monitoring/collectors/` |
| Alert Rules | `tools/vmfleet/monitoring/alerts/alert-rules.yml` |
| Azure Monitor Workbook | `tools/vmfleet/monitoring/workbooks/vmfleet-workbook.json` |
| Report Templates | `tools/vmfleet/reports/templates/` |
| Logs | `logs/vmfleet/` |

---

## Deep Dive

| Topic | Page |
|-------|------|
| Cluster and VMFleet requirements | [Prerequisites](prerequisites.md) |
| Base image, install, deploy, cleanup | [Deployment](deployment.md) |
| Profile parameters and tuning | [Workload Profiles](workload-profiles.md) |
| Metric collection and dashboards | [Monitoring](monitoring.md) |
| Report formats and templates | [Reporting](reporting.md) |
| Common errors and fixes | [Troubleshooting](troubleshooting.md) |

---

## Automate This Test

To run VMFleet on a schedule or as part of a CI/CD workflow, see [CI/CD Pipelines](../../operations/ci-cd.md). The pipeline needs the cluster YAML, `-Credential` and `-FleetAdminCredential` from secret variables; nothing prompts.

---

## More VMFleet guides

- [Failure injection (opt-in)](failure-injection.md): measure storage performance while one node is paused or one drive is out
- [Reports, comparison and regression gate](regression-gate.md): offline HTML and CSV report, baseline comparison with an exit code
- [Day-2 smoke](../../reference/day2-smoke.md): a 15-minute General run for a readiness gate, with a JSON result
- [Implementation status](../../reference/status.md)
