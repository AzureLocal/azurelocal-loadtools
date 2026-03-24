# VMFleet Overview

!!! note "This page has moved"
    The main VMFleet landing page with run instructions is now at [VMFleet](index.md). This page contains additional technical details.

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Status: Implemented](https://img.shields.io/badge/Status-Implemented-brightgreen?style=flat-square)
![VMFleet 2.1.0.0](https://img.shields.io/badge/VMFleet-2.1.0.0-blue?style=flat-square)

VMFleet is the primary storage load testing tool in the Azure Local Load Testing Framework. It deploys a fleet of VMs across Azure Local cluster nodes, each running DiskSpd workloads to stress-test Storage Spaces Direct (S2D).

## At a Glance

- **VMFleet Version:** 2.1.0.0
- **DiskSpd Version:** 2.2
- **What it tests:** Storage IOPS, throughput, latency under simulated workload
- **How it works:** Deploys lightweight Server Core VMs, each running DiskSpd to generate I/O
- **Status:** ✅ Fully Implemented

## Quick Start

```powershell
# Run the full VMFleet pipeline end-to-end
.\src\solutions\vmfleet\orchestrator\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -Profiles @("General", "Peak") `
    -CredentialSource Interactive `
    -GenerateReports
```

## Pipeline Phases

The VMFleet orchestrator executes the following phases:

1. **Pre-Check** — Validate cluster connectivity, S2D health, CSV availability, base VHD
2. **Install** — Install VMFleet PowerShell module, create Collect volume
3. **Deploy** — Create fleet VMs with configured vCPU and memory settings
4. **Test** — Execute workload profiles (General, Peak IOPS, VDI, SQL OLTP)
5. **Monitor** — Collect storage, network, and compute metrics in parallel
6. **Collect** — Parse DiskSpd XML results, aggregate metrics per profile per node
7. **Report** — Generate PDF, DOCX, and XLSX reports from collected data
8. **Cleanup** — (Optional) Remove fleet VMs and volumes

Each phase is checkpoint-tracked via `StateManager`, enabling resume after failure.

## Resume After Failure

If the pipeline fails mid-execution, resume from the last successful checkpoint:

```powershell
.\src\solutions\vmfleet\orchestrator\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -Resume
```

The `StateManager` tracks completed phases and skips them on resume.

## Running Individual Scripts

Every script can be executed independently:

```powershell
# Each script is self-contained — reads config, validates params, logs actions
.\src\solutions\vmfleet\scripts\Start-VMFleetTest.ps1 `
    -Profile "Peak" `
    -DurationSeconds 600 `
    -VerboseOutput
```

## VMFleet Documentation

| Document | Description |
| --- | --- |
| [Prerequisites](prerequisites.md) | VMFleet-specific requirements |
| [Deployment](deployment.md) | Install and deploy fleet VMs |
| [Workload Profiles](workload-profiles.md) | Test profiles and execution |
| [Monitoring](monitoring.md) | Metric collection during tests |
| [Reporting](reporting.md) | Report generation |
| [Troubleshooting](troubleshooting.md) | Common issues and solutions |
