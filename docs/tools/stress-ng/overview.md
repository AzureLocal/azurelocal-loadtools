# stress-ng — System Stress Testing

![Tool: stress-ng](https://img.shields.io/badge/Tool-stress--ng-F39C12?style=flat-square)
![Status: Implemented](https://img.shields.io/badge/Status-Implemented-brightgreen?style=flat-square)

## Purpose

CPU, memory, cache, and system stress testing for capacity planning and burn-in validation.

## When to Use

- CPU stress testing for thermal and power validation
- Memory stress testing for stability under pressure
- Burn-in testing of new cluster nodes
- Capacity planning — determine maximum safe utilization levels

## Key Capabilities

- 370+ stress tests across CPU, memory, filesystem, network categories
- YAML job files for reproducible configurations
- Metrics: bogo ops/s, thermal zones, power measurement
- Stressor class system for targeted testing

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- Linux VMs deployed on the Azure Local cluster
- Ansible 2.14+ for deployment
- stress-ng package installed on target VMs (automated via Ansible role)

## Quick Start

```powershell
# Run all-core CPU stress on every node
.\tools\stress-ng\scripts\Start-StressNgTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -Profile "cpu-stress"

# Collect bogo-ops metrics
.\tools\stress-ng\scripts\Collect-StressNgResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2") `
    -RunId "<run-id-from-previous-step>"
```

## File Locations

| Component | Path |
| --- | --- |
| Scripts | `tools/stress-ng/scripts/` |
| Profiles | `tools/stress-ng/config/profiles/` |
| Alert Rules | `tools/stress-ng/monitoring/alerts/alert-rules.yml` |
| Report Templates | `tools/stress-ng/reports/templates/` |
| Tests | `tools/stress-ng/tests/` |

## stress-ng Documentation

| Document | Description |
| --- | --- |
| [Installation](installation.md) | Install stress-ng on Linux VMs |
| [Workload Profiles](workload-profiles.md) | CPU, memory, and I/O profile configuration |
| [Monitoring](monitoring.md) | Alert rules active during stress-ng runs |
| [Reporting](reporting.md) | Result collection and report generation |
| [Troubleshooting](troubleshooting.md) | Common issues and resolutions |
