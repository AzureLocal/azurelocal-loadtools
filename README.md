# azurelocal-loadtools

Automated performance and load testing for **Azure Local** clusters — storage, network, database, and system stress — with standardised reporting.

> **Note:** This repository is under active development. Scripts, templates, and automation are not guaranteed to work at this time. Use at your own risk and expect breaking changes.

---

## Repository Structure

```
azurelocal-loadtools/
├── config/                  # Central variable reference (variables.example.yml)
├── src/                     # Shared modules and helpers
├── tools/                   # One folder per test tool
│   ├── vmfleet/             #   Storage IOPS / throughput / latency (DiskSpd)
│   ├── fio/                 #   Fine-grained storage I/O benchmarking
│   ├── iperf/               #   Network bandwidth, jitter, packet loss
│   ├── hammerdb/            #   SQL Server OLTP / OLAP benchmarking
│   └── stress-ng/           #   CPU, memory, and system stress testing
├── docs/                    # Documentation (MkDocs source)
├── tests/                   # Validation scripts
├── monitoring/              # Monitoring dashboards and alerting
├── reports/                 # Generated test reports
└── .github/workflows/       # GitHub Actions workflows
```

---

## Quick Start

```powershell
# 1. Clone and configure
git clone https://github.com/AzureLocal/azurelocal-loadtools
cd azurelocal-loadtools
Copy-Item config\variables.example.yml config\variables.yml
# Edit config\variables.yml with your cluster details

# 2. Run a VMFleet storage benchmark
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ConfigPath "config\variables.yml" `
    -Profiles @("General") `
    -CredentialSource Interactive `
    -GenerateReports
```

See the [documentation site](https://azurelocal.github.io/azurelocal-loadtools/) for full instructions.

---

## Tools

Each tool targets a specific performance domain and runs independently from a PowerShell terminal.

| Tool | What It Tests | Target OS | Status |
|------|--------------|-----------|--------|
| VMFleet | Storage IOPS, throughput, latency via DiskSpd VM fleet | Windows (HCI host) | Fully Implemented |
| fio | Fine-grained storage I/O benchmarking | Linux VMs | Structure Ready |
| iPerf3 | Network bandwidth, jitter, packet loss | Linux / Windows | Structure Ready |
| HammerDB | SQL Server OLTP / OLAP benchmarking | Windows VMs | Structure Ready |
| stress-ng | CPU, memory, and system stress testing | Linux VMs | Structure Ready |

Every tool follows the same pattern: **Install → Run Test → Collect Results**.

---

## Documentation

- [Getting Started](./docs/getting-started/introduction.md)
- [Architecture Overview](./docs/architecture/overview.md)
- [Tools Overview](./docs/tools/index.md)
- [Variable Reference](./docs/reference/variables.md)
- [Contributing](./docs/contributing.md)

---

## Prerequisites

- **Azure Local** cluster (23H2+) registered with Azure Arc
- Azure subscription with appropriate RBAC
- PowerShell 7+
- See tool-specific requirements in the documentation

---

## Contributing

See [Contributing Guide](./docs/contributing.md) for coding standards, branch strategy, and PR guidelines.
