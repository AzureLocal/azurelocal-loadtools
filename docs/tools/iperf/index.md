# iPerf3 — Network Performance Testing

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square)
![Status: Structure Ready](https://img.shields.io/badge/Status-Structure%20Ready-yellow?style=flat-square)

iPerf3 measures network bandwidth, jitter, and packet loss between cluster nodes and VMs. Use it to validate RDMA/SMB Direct paths, east-west VM bandwidth, and Switch Embedded Teaming (SET) throughput.

---

## Run This Test

### Prerequisites

- iPerf3 binaries available on target nodes (Windows or Linux)
- RDMA configuration validated (for RDMA-specific tests)
- [Framework prerequisites](../../getting-started/prerequisites.md) completed

### Step 1 — Install iPerf3 on target nodes

```powershell
.\tools\iperf\scripts\Install-Iperf.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3")
```

### Step 2 — Run a network test

```powershell
.\tools\iperf\scripts\Start-IperfTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3") `
    -Profile "tcp-throughput" `
    -DurationSeconds 60
```

This runs iPerf3 in server mode on each node in turn, with all other nodes as clients, creating a full-mesh bandwidth test.

### Step 3 — Collect results

```powershell
.\tools\iperf\scripts\Collect-IperfResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3") `
    -RunId "<run-id-from-previous-step>"
```

---

## When to Use iPerf3

| Scenario | iPerf3 |
|----------|--------|
| Validate RDMA / SMB Direct network paths | :white_check_mark: |
| Measure east-west bandwidth between VMs | :white_check_mark: |
| Test Switch Embedded Teaming throughput | :white_check_mark: |
| Baseline network before deploying workloads | :white_check_mark: |
| Detect packet loss or jitter issues | :white_check_mark: |

## Key Capabilities

- **TCP, UDP, and SCTP** protocol support
- **Multi-stream** parallel connections for saturating links
- **JSON output** for automated parsing
- **Server daemon mode** for persistent testing endpoints
- **Full-mesh** testing across all cluster nodes

---

## What You Get

After a test completes, you will have:

- **JSON output** per node-pair with bandwidth (Mbps), jitter (ms), and packet loss (%)
- **Mesh bandwidth matrix** showing throughput between every node pair
- **Reports** in PDF, DOCX, and/or XLSX format

---

## File Locations

| Component | Path |
|-----------|------|
| Scripts | `tools/iperf/scripts/` |
| Workload Profiles | `tools/iperf/config/profiles/` |
| Alert Rules | `tools/iperf/monitoring/alert-rules.yml` |
| Report Templates | `tools/iperf/reports/templates/` |
| Tests | `tools/iperf/tests/` |
| Logs | `tools/iperf/logs/` |

---

## Deep Dive

| Topic | Page |
|-------|------|
| Installation on Windows and Linux | [Installation](installation.md) |
| TCP, UDP, and mesh profiles | [Workload Profiles](workload-profiles.md) |
| Alert rules during test runs | [Monitoring](monitoring.md) |
| Report formats and templates | [Reporting](reporting.md) |
| Common errors and fixes | [Troubleshooting](troubleshooting.md) |

---

## Automate This Test

To run iPerf3 tests on a schedule or as part of a CI/CD workflow, see [CI/CD Pipelines](../../operations/ci-cd.md). The pipeline calls the same scripts listed above.
