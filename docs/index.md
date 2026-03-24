# Azure Local Load Testing Framework

Automated performance and load testing for Azure Local clusters — storage, network, database, and system stress — with standardised reporting.

## Quick Start

```powershell
# 1. Clone and configure
git clone https://github.com/AzureLocal/azurelocal-loadtools
Copy-Item config\variables.example.yml config\variables.yml
# Edit config\variables.yml with your cluster details

# 2. Run a storage benchmark
.\scripts\Start-FioTest.ps1 -RunId "fio-$(Get-Date -f yyyyMMddHHmm)" -Profile "sequential-read"
.\scripts\Collect-FioResults.ps1 -RunId "fio-$(Get-Date -f yyyyMMddHHmm)"

# 3. Generate a report
.\scripts\New-LoadReport.ps1 -RunId "fio-$(Get-Date -f yyyyMMddHHmm)" -Tool fio
```

## Architecture at a Glance

The framework is organised into five layers:

```
Configuration → Automation → Execution → Monitoring → Reporting
```

All scripts consume ConfigManager-generated JSON (never the raw YAML). Results flow from target nodes via SSH/SCP or WinRM to JSON aggregates, then into AsciiDoc report templates. See the [Architecture Overview](architecture/overview.md) for the full breakdown.

## Tools

| Tool | Target OS | Category | Status | Profiles |
|------|-----------|----------|--------|---------|
| [fio](tools/fio/overview.md) | Linux | Storage I/O | ![Implemented](https://img.shields.io/badge/-Implemented-brightgreen?style=flat-square) | 5 |
| [iPerf3](tools/iperf/overview.md) | Linux / Windows | Network | ![Implemented](https://img.shields.io/badge/-Implemented-brightgreen?style=flat-square) | 3 |
| [HammerDB](tools/hammerdb/overview.md) | Windows | Database | ![Implemented](https://img.shields.io/badge/-Implemented-brightgreen?style=flat-square) | 2 |
| [stress-ng](tools/stress-ng/overview.md) | Linux | CPU / Memory / I/O | ![Implemented](https://img.shields.io/badge/-Implemented-brightgreen?style=flat-square) | 3 |
| [VMFleet](tools/vmfleet/overview.md) | Windows (HCI) | VM fleet | ![Implemented](https://img.shields.io/badge/-Implemented-brightgreen?style=flat-square) | — |

## Navigation

| Section | Description |
|---------|-------------|
| [Getting Started](getting-started/introduction.md) | Prerequisites, installation, and first run |
| [Architecture](architecture/overview.md) | Five-layer stack, tool selection, data flow |
| [Tools](tools/fio/overview.md) | Per-tool installation, profiles, monitoring, reporting, troubleshooting |
| [Operations](operations/ci-cd.md) | CI/CD pipelines, runner setup, troubleshooting |
| [Reference](reference/cmdlet-reference.md) | Cmdlet reference, variables, tool comparison |
| [Roadmap](roadmap.md) | Milestone tracker and planned features |

## Repository

- **GitHub**: [AzureLocal/azurelocal-loadtools](https://github.com/AzureLocal/azurelocal-loadtools)
- **Issues**: [Report a bug or request a feature](https://github.com/AzureLocal/azurelocal-loadtools/issues)
