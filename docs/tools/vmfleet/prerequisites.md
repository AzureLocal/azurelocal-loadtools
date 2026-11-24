# VMFleet Prerequisites

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

In addition to the [common prerequisites](../../getting-started/prerequisites.md), VMFleet requires the following.

## Management host

| Requirement | Details |
| --- | --- |
| PowerShell | 7.2 or later, with the `powershell-yaml` module. The management host does **not** need to be domain-joined. |
| WinRM to the nodes | Each node by its **management IP**, HTTP 5985, NTLM. The IPs are in `TrustedHosts` (`Set-Item WSMan:\localhost\Client\TrustedHosts -Value '<ip>,<ip>' -Concatenate`). Names are not resolved. |
| Credentials | `-Credential`: a domain account (`DOMAIN\user`) that is an administrator on every node. `-FleetAdminCredential`: the local administrator password for the fleet VMs. Nothing prompts; build them in your session or take them from the environment or Key Vault ([credential management](../../operations/credential-management.md)). |
| Cluster YAML | `config\clusters\cluster.yml` from `config\clusters\example-cluster.yml`: the cluster name, the nodes as IPs, the Collect volume and the per-node volumes ([Deployment](deployment.md#cluster-configuration)). |

## Cluster Storage Requirements

| Requirement | Details |
| --- | --- |
| Base VHD | One Generation 2 Windows Server VHD(X) readable from the first node; see [Base image](deployment.md#base-image). A small image (the 32 GB `smalldisk` SKU) keeps the per-VM copy small. |
| Collect volume | A CSV named `collect`, ReFS (VMFleet default 200 GB; `Get-FleetVolumeEstimate` recommends a size) |
| Node volumes | At least one CSV per node whose name starts with the node name; VMs and their VHDs live there |
| CSV space | A full copy of the base VHD per VM on the node's own volume |

`Install-Fleet` checks the Collect volume and the node volumes and stops with a message naming what is missing.

## Software on the first node

| Requirement | Details |
| --- | --- |
| VMFleet module | 2.1.0.0 from the PowerShell Gallery; the install step runs `Install-Module -RequiredVersion` (the node needs internet, or pre-stage the module) |
| DiskSpd | 2.1.0.0 or later in `<collect>\tools`; `Install-Fleet` downloads it from `aka.ms/getdiskspd`, or place it there first |
| Windows PowerShell 5.1 | The scheduled tasks run `powershell.exe`; the VMFleet and FailoverClusters modules need it |

## Validation

Nothing in these checks changes the cluster:

```powershell
# WinRM, by IP, with the credential (Negotiate = NTLM for an IP address)
Test-WSMan -ComputerName 192.0.2.11 -Authentication Negotiate -Credential $cred

# The cluster YAML parses and the nodes are what you expect
. .\tools\vmfleet\scripts\VMFleet-Common.ps1
Get-VMFleetClusterConfig -ClusterConfigPath config\clusters\cluster.yml

# What the install step would do
.\tools\vmfleet\scripts\Install-VMFleet.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred -WhatIf
```
