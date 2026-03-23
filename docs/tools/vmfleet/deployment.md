# VMFleet Deployment

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers installing the VMFleet module and deploying fleet VMs across your Azure Local cluster.

## Phase 0: Prepare Base Image (first run only)

Before deployment, prepare the base image from Azure Local marketplace (or verify it already exists):

```powershell
.\src\infrastructure\Prepare-VMFleetBaseImage.ps1 `
    -ConfigPath "config/variables.yml" `
    -ClusterConfigPath "config/clusters/my-cluster.yml"
```

After completion, set the resolved VHDX path in `storage.base_vhd_path` in `config/variables.yml`.

## Install VMFleet

Installs the VMFleet PowerShell module and prepares the cluster:

```powershell
.\src\solutions\vmfleet\scripts\Install-VMFleet.ps1 `
    -ClusterConfigPath "config/clusters/my-cluster.yml"
```

## Deploy Fleet VMs

Creates fleet VMs across all cluster nodes:

```powershell
.\src\solutions\vmfleet\scripts\Deploy-VMFleet.ps1 `
    -ClusterConfigPath "config/clusters/my-cluster.yml" `
    -VMCount 10 `
    -VMProcessorCount 2 `
    -VMMemoryGB 2
```

The number of VMs, vCPUs, and memory per VM are configurable via:

- Explicit parameters (as shown above) — highest priority
- Solution JSON (`config/variables/solutions/vmfleet.json`)
- Master environment defaults (`config/variables/master-environment.yml`)

See [Configuration](../../getting-started/configuration.md) for details on the override chain.

## Cleanup

To remove fleet VMs and restore the cluster to its pre-test state:

```powershell
.\src\solutions\vmfleet\scripts\Remove-VMFleet.ps1 `
    -ClusterConfigPath "config/clusters/my-cluster.yml" `
    -Confirm
```

## First-Time vs Subsequent Runs

- First-time environment bootstrap: run Phase 0 image prep once, then Install and Deploy.
- Subsequent test cycles: skip Phase 0 unless you want to force-refresh image download.
- Day-2 operations: run test, monitor, collect, report, and optional cleanup.

## Next Steps

- [Workload Profiles](workload-profiles.md) — Run test workloads
