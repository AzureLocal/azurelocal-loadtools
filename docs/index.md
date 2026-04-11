# Azure Local Load Testing Framework

![Azure Local Load Testing Framework](assets/images/azurelocal-loadtools-banner.svg)

Automated performance and load testing for Azure Local clusters — storage, network, database, and system stress — with standardised reporting.

!!! warning "Under Active Development"
    This repository is a work in progress. Scripts, templates, and automation are not guaranteed to work at this time. Use at your own risk and expect breaking changes.

!!! tip "Each test is standalone"
    Every tool in this framework runs independently from a PowerShell terminal. No CI/CD pipeline is required. Pick a tool, follow the steps on its page, and run your test.

## Quick Start

```powershell
# 1. Clone and configure
git clone https://github.com/AzureLocal/azurelocal-loadtools
cd azurelocal-loadtools
Copy-Item config\variables.example.yml config\variables.yml
# Edit config\variables.yml with your cluster details

# 2. Run a VMFleet storage benchmark (fully implemented)
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ConfigPath "config\variables.yml" `
    -Profiles @("General") `
    -CredentialSource Interactive `
    -GenerateReports

# Or run individual steps for any tool:
.\tools\vmfleet\scripts\Install-VMFleet.ps1 -ClusterName "hci01.corp.infiniteimprobability.com" -Nodes @("hci01-node1")
.\tools\vmfleet\scripts\Start-VMFleetTest.ps1 -Profile "General" -DurationSeconds 600
.\tools\vmfleet\scripts\Collect-VMFleetResults.ps1 -Nodes @("hci01-node1") -RunId "<run-id>"
```

## Pick a Test

Each tool targets a specific performance domain. Click a tool to see exactly how to run it.

| Tool | What It Tests | Target OS | Status |
|------|--------------|-----------|--------|
| [VMFleet](tools/vmfleet/index.md) | Storage IOPS, throughput, latency via DiskSpd VM fleet | Windows (HCI host) | :white_check_mark: Fully Implemented |
| [fio](tools/fio/index.md) | Fine-grained storage I/O benchmarking | Linux VMs | :construction: Structure Ready |
| [iPerf3](tools/iperf/index.md) | Network bandwidth, jitter, packet loss | Linux / Windows | :construction: Structure Ready |
| [HammerDB](tools/hammerdb/index.md) | SQL Server OLTP / OLAP benchmarking | Windows VMs | :construction: Structure Ready |
| [stress-ng](tools/stress-ng/index.md) | CPU, memory, and system stress testing | Linux VMs | :construction: Structure Ready |

For a detailed comparison and selection guide, see [Tools Overview](tools/index.md).

## How It Works

Every tool follows the same three-step pattern:

```
Install → Run Test → Collect Results
```

All scripts are in `tools/<tool>/scripts/` and can be called directly from PowerShell. No pipeline setup required.

For the full architecture breakdown, see [Architecture Overview](architecture/overview.md).

## Want to Automate?

CI/CD pipelines are available as an **optional addition** if you want to run tests on a schedule, trigger them from pull requests, or integrate into your deployment workflow. See [CI/CD Pipelines](operations/ci-cd.md).

## Navigation

| Section | Description |
|---------|-------------|
| [Getting Started](getting-started/introduction.md) | Prerequisites, installation, and first run |
| [Tools Overview](tools/index.md) | All tools at a glance with selection guide |
| [Architecture](architecture/overview.md) | Five-layer stack, tool selection, data flow |
| [Operations](operations/ci-cd.md) | CI/CD pipelines (optional), runner setup, troubleshooting |
| [Reference](reference/cmdlet-reference.md) | Cmdlet reference, variables, tool comparison |
| [Roadmap](roadmap.md) | Milestone tracker and planned features |

## Repository

- **GitHub**: [AzureLocal/azurelocal-loadtools](https://github.com/AzureLocal/azurelocal-loadtools)
- **Issues**: [Report a bug or request a feature](https://github.com/AzureLocal/azurelocal-loadtools/issues)
