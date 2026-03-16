# VMFleet Deployment

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers installing the VMFleet module and deploying fleet VMs across your Azure Local cluster.

## Install VMFleet

Installs the VMFleet PowerShell module and prepares the cluster:

```powershell
.\src\solutions\vmfleet\scripts\Install-VMFleet.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -CredentialSource Interactive
```

## Deploy Fleet VMs

Creates fleet VMs across all cluster nodes:

```powershell
.\src\solutions\vmfleet\scripts\Deploy-VMFleet.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -VmCountPerNode 10 `
    -VmVcpuCount 2 `
    -VmMemoryGb 2
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
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -CredentialSource Interactive `
    -Confirm
```

## Next Steps

- [Workload Profiles](workload-profiles.md) — Run test workloads
