# VMFleet Overview

> [!NOTE]
> **This page has moved**
> The main VMFleet landing page with run instructions is now at [VMFleet](index.md). This page contains additional technical details.
>
![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Status: Not proven on hardware](https://img.shields.io/badge/Hardware-Not%20proven-yellow?style=flat-square)
![VMFleet 2.1.0.0](https://img.shields.io/badge/VMFleet-2.1.0.0-blue?style=flat-square)

VMFleet is the primary storage load testing tool in the Azure Local Load Testing Framework. It deploys a fleet of VMs across Azure Local cluster nodes, each running DiskSpd workloads to stress-test Storage Spaces Direct (S2D).

## At a Glance

- **VMFleet Version:** 2.1.0.0 (PowerShell Gallery)
- **DiskSpd Version:** 2.1.0.0 or later (VMFleet downloads it into `<collect>\tools`)
- **What it tests:** Storage IOPS, throughput, latency under simulated workload
- **How it works:** Deploys lightweight Windows Server VMs, each running DiskSpd to generate I/O
- **Where it runs:** the VMFleet module runs on the first cluster node, as a one-shot scheduled task started from the management host ([how](deployment.md#how-the-scripts-reach-the-cluster))
- **Status:** implemented and unit-tested, not proven on hardware (see [status](../../reference/status.md))

## Quick Start

```powershell
# Run the full VMFleet pipeline end-to-end (cluster YAML, credentials: see the runbook in index.md)
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml `
    -ProfilePath tools\vmfleet\config\profiles\general.yml `
    -Credential $cred -FleetAdminCredential $fleetAdmin
```

## Pipeline Phases

The VMFleet orchestrator executes the following phases:

1. **PreCheck**: validate the config files and the WinRM connection to every node (by IP, with the credential)
2. **Install**: install the VMFleet module and run `Install-Fleet`
3. **Deploy**: `New-Fleet`, `Set-Fleet`, `Start-Fleet`; wait until every VM is `Ok`
4. **StartTest**: start `Start-FleetSweep` with the profile's parameters (it does not block the pipeline)
5. **Monitor**: collect storage, network and compute metrics while the sweep runs; wait for the sweep to end (profile duration, warm-up and cool-down, not a fixed time)
6. **StopTest**: `Stop-Fleet`
7. **Collect**: read the DiskSpd XML results of the run, aggregate them to JSON
8. **Report**: HTML and CSV by default; PDF, DOCX, XLSX when their tools are installed (otherwise skipped with a warning)
9. **Cleanup**: `Remove-Fleet` and a check that nothing is left (skip with `-SkipCleanup`)

Each phase is checkpoint-tracked via `StateManager`, enabling resume after failure (`-Resume`).

## Resume After Failure

```powershell
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml `
    -Credential $cred -FleetAdminCredential $fleetAdmin -Resume
```

The `StateManager` tracks completed phases and skips them on resume.

## Running Individual Scripts

Every step script can be executed independently:

```powershell
.\tools\vmfleet\scripts\Start-VMFleetTest.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml -Credential $cred `
    -ProfilePath tools\vmfleet\config\profiles\general.yml -RunId general-001
```

## VMFleet Documentation

| Document | Description |
| --- | --- |
| [Prerequisites](prerequisites.md) | VMFleet-specific requirements |
| [Deployment](deployment.md) | Base image, install, deploy fleet VMs, cleanup |
| [Workload Profiles](workload-profiles.md) | Test profiles and execution |
| [Monitoring](monitoring.md) | Metric collection during tests |
| [Reporting](reporting.md) | Report generation |
| [Troubleshooting](troubleshooting.md) | Common issues and solutions |
