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
Copy-Item config\variables\variables.example.yml config\variables\variables.yml
# Edit config\variables\variables.yml with your cluster details (example values only in the repo)

# 2. Run a VMFleet storage benchmark with the General profile
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath "config\clusters\my-cluster.yml" `
    -ProfilePath "tools\vmfleet\config\profiles\general.yml" `
    -FleetAdminCredential (Get-Credential -Message "Fleet VM admin")
```

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

- **Azure Local** cluster registered with Azure Arc (the docs target 12.2609 (latest))
- Azure subscription with appropriate RBAC
- PowerShell 7.2+
- See tool-specific requirements in the documentation

---

## Contributing

See [Contributing Guide](./docs/contributing.md) for coding standards, branch strategy, and PR guidelines. Run `pwsh -File tests/Invoke-CiChecks.ps1 -Check All` before you open a pull request.
