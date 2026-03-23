# VMFleet Prerequisites

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

In addition to the [common prerequisites](../../getting-started/prerequisites.md), VMFleet requires the following.

## Cluster Storage Requirements

| Requirement | Details |
| --- | --- |
| Base VHD | Windows Server 2022 Datacenter Core Gen2 VHDX for fleet VMs |
| Collect Volume | 200GB+ ReFS volume named "Collect" for VMFleet result aggregation |
| CSV Space | Sufficient free space on CSVs for fleet VMs (count × memory + data disk) |
| Azure Local marketplace pathing | Valid `azure_local.custom_location_id` and `azure_local.storage_path_id` in `config/variables.yml` |

## Software Requirements

| Requirement | Details |
| --- | --- |
| VMFleet Module | PowerShell VMFleet module (`Install-Module -Name VMFleet`) |
| DiskSpd | Included with VMFleet; no separate installation required |
| Az PowerShell | `Az.Accounts` and `Az.Resources` for marketplace image REST operations |
| WinRM access | Working PowerShell remoting from management station to all cluster nodes |

## Base Image Preparation

Run the image preparation script before first deployment. It checks whether the image already exists on cluster storage, and if not, triggers a marketplace download and tracks progress until completion.

```powershell
.\src\infrastructure\Prepare-VMFleetBaseImage.ps1 `
    -ConfigPath "config/variables.yml" `
    -ClusterConfigPath "config/clusters/my-cluster.yml"
```

On success, the script prints the resolved VHDX path. Copy that value into `storage.base_vhd_path` in `config/variables.yml` before running `Deploy-VMFleet.ps1`.

## Validation

Run pre-checks to verify VMFleet-specific readiness:

```powershell
.\src\solutions\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath "config/clusters/my-cluster.yml" `
    -WhatIf
```

Checks performed:

- Cluster node connectivity via WinRM
- Storage Spaces Direct health status
- Required CSV volumes exist and are online
- Base VHD file exists and is accessible
- Sufficient disk space for fleet VMs
- VMFleet PowerShell module availability
