# iPerf3 — Network Performance Testing

!!! note "This page has moved"
    The main iPerf3 landing page with run instructions is now at [iPerf3](index.md). This page contains additional technical details.

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square)
![Status: Implemented](https://img.shields.io/badge/Status-Implemented-brightgreen?style=flat-square)

## Purpose

Network bandwidth, jitter, and packet loss measurement between cluster nodes and VMs.

## When to Use

- Validating RDMA/SMB Direct network paths between cluster nodes
- Measuring east-west bandwidth between VMs
- Testing Switch Embedded Teaming (SET) throughput
- Baseline network performance before deploying workloads

## Key Capabilities

- TCP, UDP, and SCTP protocol support
- Multi-stream parallel connections
- JSON output for automated parsing
- Server daemon mode for persistent testing endpoints

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- iPerf3 binaries on target nodes (Windows or Linux)
- RDMA configuration validated (for RDMA testing)
- Ansible 2.14+ for Linux VM deployment

## Quick Start

```powershell
# Run TCP throughput between all nodes
.\tools\iperf\scripts\Start-IperfTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3") `
    -Profile "tcp-throughput"

# Collect and normalize results
.\tools\iperf\scripts\Collect-IperfResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3") `
    -RunId "<run-id-from-previous-step>"
```

## File Locations

| Component | Path |
| --- | --- |
| Scripts | `tools/iperf/scripts/` |
| Profiles | `tools/iperf/config/profiles/` |
| Alert Rules | `tools/iperf/monitoring/alerts/alert-rules.yml` |
| Report Templates | `tools/iperf/reports/templates/` |
| Tests | `tools/iperf/tests/` |

## iPerf3 Documentation

| Document | Description |
| --- | --- |
| [Installation](installation.md) | Install iPerf3 on cluster nodes |
| [Workload Profiles](workload-profiles.md) | TCP, UDP, and mesh profile configuration |
| [Monitoring](monitoring.md) | Alert rules active during iPerf3 runs |
| [Reporting](reporting.md) | Result collection and report generation |
| [Troubleshooting](troubleshooting.md) | Common issues and resolutions |
