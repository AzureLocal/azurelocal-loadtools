# azurelocal-loadtools

![Azure Local Load Testing Framework](docs/assets/images/azurelocal-loadtools-banner.svg)

[![Azure Local](https://img.shields.io/badge/Azure%20Local-azurelocal.cloud-0078D4?logo=microsoft-azure)](https://azurelocal.cloud)

Documentation: [azurelocal.cloud](https://azurelocal.cloud) | Solutions: [Azure Local Solutions](https://azurelocal.cloud)

Automated performance and load testing for **Azure Local** clusters — storage, network, database, and system stress — with standardised reporting.

> **Status: pre-release (0.1.0), not proven on a live cluster.** The scripts are implemented and unit-tested with mocks and fixtures. None of the tools has been run end to end on a real Azure Local cluster yet. Expect breaking changes and prove each tool on a non-production cluster before you rely on it. The single truth table is [Implementation status](docs/reference/status.md).

---

## Repository Structure

```
azurelocal-loadtools/
├── common/                  # Shared PowerShell modules, helpers, Ansible role, Bicep
│   └── modules/             #   ConfigManager, Logger, StateManager, CredentialManager,
│                            #   MonitoringManager, ReportGenerator, ResultAnalysis, FaultInjection
├── config/                  # Central variable reference (variables.example.yml, JSON schema)
├── tools/                   # One folder per test tool (scripts, config/profiles, monitoring, reports, tests)
│   ├── vmfleet/             #   Storage IOPS / throughput / latency (DiskSpd)
│   ├── fio/                 #   Fine-grained storage I/O benchmarking
│   ├── iperf/               #   Network bandwidth, jitter, packet loss (TCP/UDP, not RDMA)
│   ├── hammerdb/            #   SQL Server OLTP / OLAP benchmarking
│   └── stress-ng/           #   CPU, memory, and system stress testing
├── docs/                    # Documentation (VitePress source)
├── tests/                   # Pester tests for the common modules, CI check script, fixtures
├── repo-management/         # How the repository is configured
└── .github/workflows/       # ci.yml, release-please.yml, deploy-docs.yml
```

Monitoring collectors and report templates live inside each tool (`tools/<tool>/monitoring`, `tools/<tool>/reports/templates`). Generated reports go to `reports/<run-id>` at run time and are not committed.

---

## Quick Start

```powershell
# 1. Clone and configure
git clone https://github.com/AzureLocal/azurelocal-loadtools
cd azurelocal-loadtools
# The cluster (name, nodes, domain, volume, Azure scope, Key Vault) comes from the environment's infrastructure.yml,
# the one file every Azure Local tool reads (azurelocal-toolkit config/variables registry, schema 5).
# config\variables\variables.yml is committed and holds the test settings only.
.\common\helpers\Initialize-Environment.ps1 -Solution VMFleet -InfrastructureFile ".\infrastructure.yml"

# 2. Describe the cluster: nodes by management IP, the Collect volume, the base VHD
Copy-Item config\clusters\example-cluster.yml config\clusters\cluster.yml   # git-ignored; edit it

# 3. Run a VMFleet storage benchmark with the General profile (not yet proven on hardware)
$cred       = Get-Credential -Message 'DOMAIN\user, an administrator on every node'
$fleetAdmin = Get-Credential -UserName 'Administrator' -Message 'Local administrator password of the fleet VMs'
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml `
    -ProfilePath tools\vmfleet\config\profiles\general.yml `
    -Credential $cred -FleetAdminCredential $fleetAdmin
```

The management host does not have to be domain-joined; it reaches the nodes by IP. The base image, the Day-2 smoke run and the cleanup are in the [VMFleet runbook](docs/tools/vmfleet/index.md).

The parameter names above come from the script `param` blocks. See the [documentation site](https://azurelocal.github.io/azurelocal-loadtools/) for the rest.

---

## Tools and status

Every tool follows the same pattern: **Install → Run Test → Collect Results**.

| Tool | What It Tests | Target OS | Implemented | Unit-tested | Proven on hardware |
|------|--------------|-----------|-------------|-------------|--------------------|
| VMFleet | Storage IOPS, throughput, latency via DiskSpd VM fleet | Windows (HCI host) | Yes | Yes | **No** |
| fio | Fine-grained storage I/O benchmarking | Linux VMs | Yes | Yes | **No** |
| iPerf3 | Network bandwidth, jitter, packet loss (not RDMA) | Linux / Windows | Yes | Yes | **No** |
| HammerDB | SQL Server OLTP / OLAP benchmarking | Windows VMs | Yes | Yes | **No** |
| stress-ng | CPU, memory, and system stress testing | Linux VMs | Yes | Yes | **No** |

"Unit-tested" means Pester tests with mocks and fixtures, no cluster. Details, test counts and known gaps: [Implementation status](docs/reference/status.md). The [roadmap](docs/roadmap.md) agrees with this table.

---

## Where Load Tools fits in the Azure Local tool chain

Load Tools is a **day 2** tool: it measures a cluster that is already deployed. It reads the same `infrastructure.yml` (schema 5) as every other Azure Local tool, and writes nothing back to it.

```text
Surveyor (sizing handoff) -> Trailwright (infrastructure.yml) -> hardware discovery -> ZTP -> toolkit OS configuration, gate, ARM deploy -> Ranger / Sonar / Load Tools
```

| Step | Tool | Hands over |
|------|------|-----------|
| Plan | [Surveyor](https://azurelocal.cloud/azurelocal-surveyor/), [Trailwright](https://azurelocal.cloud/azurelocal-trailwright/) | `azure-local-sizing-handoff-*.json`, then `infrastructure.yml` |
| Deploy | [azurelocal-toolkit](https://github.com/AzureLocal/azurelocal-toolkit), [azurelocal-ztp](https://github.com/AzureLocal/azurelocal-ztp) | The deployed cluster; the file stays the record of what was built |
| Day 2 | **Load Tools** | Reads `cluster.name`, `nodes[].name`, `identity.active_directory.domain_fqdn`, `storage.paths` or `storage.volumes` (the cluster shared volume), `azure.*` and `key_vaults[]`; writes results to `reports/<run-id>` |

Pass the file as `-InfrastructureFile` (`Initialize-Environment.ps1`, `Export-SolutionConfig`) or as `-ClusterConfigPath` (every tool script). A per-cluster file of the earlier layout (`config/clusters/*.yml`) is still read, with a warning; the VMFleet scripts read their own per-cluster file (`config/clusters/example-cluster.yml`: nodes by management IP) without one. `config/variables/variables.yml` holds the test settings (profiles, durations, VMFleet sizing, monitoring, reporting, fault injection) and no cluster facts.

## What is in this release

- **Storage tests that account for the CSV cache.** Learn warns that DiskSpd and VMFleet "may produce worse results with the CSV in-memory read cache enabled than without it". The [VMFleet profile guide](docs/tools/vmfleet/workload-profiles.md) explains how to record and compare results.
- **Opt-in failure injection.** Measure storage under one paused node or one drive out, as the Azure Well-Architected Framework guidance for Azure Local recommends. Never a default, needs `-AllowFault` and a confirmation, prints the undo command first, refuses when the cluster is unhealthy: [Failure injection](docs/tools/vmfleet/failure-injection.md).
- **Offline reports and a regression gate.** HTML and CSV from a result file, baseline comparison with exit code 0 / 1 / 2, trend: [Reports and regression gate](docs/tools/vmfleet/regression-gate.md).
- **Day-2 smoke.** A 15-minute General run with an exit code and a JSON result for a readiness gate: [Day-2 smoke](docs/reference/day2-smoke.md).
- **CI.** Analyzer, Pester per suite and a link check on every pull request: [CI/CD](docs/operations/ci-cd.md).

---

## Documentation

- [Implementation status](./docs/reference/status.md)
- [Getting Started](./docs/getting-started/introduction.md)
- [Architecture Overview](./docs/architecture/overview.md)
- [Tools Overview](./docs/tools/index.md)
- [Variable Reference](./docs/reference/variables.md)
- [Roadmap](./docs/roadmap.md)
- [Contributing](./docs/contributing.md)

---

## Prerequisites

- **Azure Local** 2605 or later (OS build 26100) registered with Azure Arc; the docs target 12.2611.1004.9 (OS 26100.33822), the latest release
- The environment's `infrastructure.yml` (schema 5), written by Trailwright and filled by hardware discovery, so the cluster name, the nodes, the domain and the Azure scope are never typed twice
- Azure subscription with appropriate RBAC
- PowerShell 7.2+ on a Windows management station (Windows 10/11 or Windows Server 2019+); Windows PowerShell 5.1 is not supported
- Required module: `powershell-yaml`; for VMFleet also the `VMFleet` module. Optional: `Az.KeyVault`, `Az.Monitor`, `ImportExcel`, plus `asciidoctor-pdf` and `pandoc` for PDF and DOCX reports
- WinRM (TCP 5985/5986) from the station to every cluster node; HTTPS 443 to Azure Resource Manager, Key Vault and Azure Monitor when those features are used; SSH 22 to Linux VMs and Ansible 2.14+ for fio, iPerf3, HammerDB and stress-ng
- Credentials come from a parameter, an environment variable or Azure Key Vault (Key Vault Secrets User role), never from files in the repo; no script prompts, and a missing credential stops the script with a message
- Full list and per-tool requirements: [Prerequisites](docs/getting-started/prerequisites.md)

---

## Contributing

See [Contributing Guide](./docs/contributing.md) for coding standards, branch strategy, and PR guidelines. Run `pwsh -File tests/Invoke-CiChecks.ps1 -Check All` before you open a pull request.
