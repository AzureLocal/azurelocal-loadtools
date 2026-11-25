# VMFleet Deployment

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)
![Status: Not proven on hardware](https://img.shields.io/badge/Hardware-Not%20proven-yellow?style=flat-square)

> [!WARNING]
> **Not proven on a live cluster.** The scripts below create and remove VMs and copy the base image once per VM. They pass Pester tests against stubs that have the real VMFleet 2.1.0.0 parameter lists, not a run on a cluster. Try them on a non-production cluster first. See [status](../../reference/status.md).

This guide covers the base image, installing VMFleet on the cluster, deploying the fleet VMs and removing them again, from a management host that is **not domain-joined**.

## How the scripts reach the cluster

The management host reaches each node only by its **management IP** over WinRM (HTTP 5985, NTLM) with an explicit domain credential. It does not need to resolve the cluster or node names.

The VMFleet module must run **on a cluster node**: its cmdlets default to `-Cluster '.'` and use `Get-ClusterNode`, CSV paths and remoting to the other nodes. Inside an NTLM remoting session that second hop fails, and CredSSP is deliberately not used. So every VMFleet step (install, deploy, test, stop, collect, remove) runs as a **one-shot scheduled task on the first node**:

1. One remoting session to the first node, with `-Credential`.
2. A generated script, its arguments and a run folder are written below the Collect volume: `C:\ClusterStorage\Collect\loadtools\<run id>\<step>\`.
3. A task is registered with the same credential (logon type Password, run level Highest), started, and unregistered when it is done.
4. The task runs the script locally on the node, writes `transcript.log` and `result.json` to the run folder, and this host polls the task and reads the result.

The fleet VM password never touches a disk or a log: it travels through the encrypted remoting channel into an in-memory named pipe that only the task account can open, and the node script scrubs it from its transcript and result. The shared helper is `tools\vmfleet\scripts\VMFleet-Common.ps1`; the node-side scripts are in `tools\vmfleet\scripts\node\`.

## Prepare the management host

```powershell
# PowerShell 7.2+ and the YAML module
Install-Module powershell-yaml -Scope CurrentUser

# The node IPs must be trusted for NTLM over HTTP (run elevated; use your own addresses)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '192.0.2.11,192.0.2.12' -Concatenate

# Interactive prompts are for you, at the console. The scripts never prompt.
$cred       = Get-Credential -Message 'DOMAIN\user, an administrator on every node'
$fleetAdmin = Get-Credential -UserName 'Administrator' -Message 'Local administrator password for the fleet VMs'
```

Check it before you start (nothing is changed): `Test-WSMan -ComputerName 192.0.2.11 -Authentication Negotiate -Credential $cred`. Without `-Authentication`, `Test-WSMan` sends the request anonymously and ignores the credential; the scripts' own connectivity check passes `-Authentication Negotiate` for that reason.

## Cluster configuration

The environment's `infrastructure.yml` (schema 5) also works as `-ClusterConfigPath`: the scripts read `cluster.name` and `nodes[].name` from it (`management_ip` is used when a node entry has one), and the Azure scope and storage path for `Prepare-VMFleetBaseImage.ps1`. `nodes[].name` is the remoting target, so with that file the management host must resolve the node names. The per-cluster file below carries the management IPs for a host that cannot.

Copy `config\clusters\example-cluster.yml` to `config\clusters\cluster.yml` (git-ignored, it holds real IPs) and edit it:

```yaml
cluster:
  name: "azl-cluster-01"            # reports only; it is not resolved
nodes:
  - name: "192.0.2.11"              # management IP: the remoting target. The first node runs every step.
    hostname: "azl-node-01"         # optional, display only
  - name: "192.0.2.12"
    hostname: "azl-node-02"
storage:
  collect_path: "C:\\ClusterStorage\\Collect"          # the CSV named 'collect'
  node_volumes:                                         # one CSV per node, name starts with the node name
    - "C:\\ClusterStorage\\azl-node-01"
    - "C:\\ClusterStorage\\azl-node-02"
  base_vhd_path: "C:\\ClusterStorage\\Collect\\base\\vmfleet-base.vhdx"   # path ON THE NODE
```

The solution config `tools\vmfleet\config\vmfleet.json` (generated from `config\variables\variables.yml`) supplies the rest. These keys are read by the VMFleet scripts; a script parameter always wins:

```json
{
  "vmfleet_version": "2.1.0.0",
  "vm_count_per_node": 4,
  "vm_vcpu_count": 2,
  "vm_memory_gb": 2,
  "base_vhd_path": "",
  "test_duration_seconds": 300,
  "warmup_seconds": 60,
  "cooldown_seconds": 30
}
```

`vm_count_per_node` is the VM count **per node** (`New-Fleet -VMs`). A workload profile's `profile.parameters` (`duration_seconds`, `warmup_seconds`, ...) beat `test_duration_seconds` and `warmup_seconds`.

## Cluster prerequisites for VMFleet

- A CSV named `collect` (ReFS) and at least one CSV per node whose name starts with the node name. `Get-FleetVolumeEstimate` (on a node) recommends sizes. `Install-Fleet` stops with a message naming what is missing.
- Internet access from the first node to the PowerShell Gallery (the VMFleet module) and to `aka.ms/getdiskspd` (DiskSpd). Offline: copy the module to `C:\Program Files\WindowsPowerShell\Modules\VMFleet\2.1.0.0` and put `diskspd.exe` 2.1.0.0 or later in `<collect>\tools` before running the install step.
- `Install-Fleet` turns the CSV block cache **off for the whole cluster** (it is VMFleet's recommendation); pass `-KeepBlockCache` to Install-VMFleet.ps1 to keep it.
- Free space for the fleet: VMFleet copies the base VHD once per VM, as a fixed VHD, onto the node's own volume. Use a small base image.

## Base image

VMFleet needs one **Generation 2 Windows Server VHD(X)** on a path the first node can read. VMFleet creates plain Hyper-V VMs, not Azure Local VMs enabled by Azure Arc, so the image does not have to be an Arc gallery image.

Which Windows Server images Azure Local supports comes from Microsoft Learn ([Create Azure Local VM image using Azure Marketplace images](https://learn.microsoft.com/azure/azure-local/manage/virtual-machine-image-azure-marketplace), [Deploy Windows Server Azure Edition VMs on Azure Local](https://learn.microsoft.com/azure/azure-local/manage/windows-server-azure-edition-23h2)). Publisher `microsoftwindowsserver`, offer `windowsserver`:

| Image | SKUs |
|-------|------|
| Windows Server 2025 Datacenter: Azure Edition | `2025-datacenter-azure-edition-smalldisk`, `2025-datacenter-azure-edition-core`, `2025-datacenter-azure-edition` |
| Windows Server 2022 Datacenter: Azure Edition | `2022-datacenter-azure-edition-hotpatch`, `2022-datacenter-azure-edition-core`, `2022-datacenter-azure-edition` |
| Windows Server 2019 | `2019-datacenter-gensecond`, `2019-datacenter-core-g2` |

`2025-datacenter-azure-edition-smalldisk` is the recommended choice: the OS disk is about 32 GB, so the per-VM copy is small. The plain Windows Server 2019 SKUs are the alternative with no Azure Edition activation dependency.

### Route A (documented by Learn, recommended): export a plain VHD from Azure

Run this from a machine with the Azure CLI signed in (`az login`) and `azcopy` available, not from a cluster node unless the node has both. It creates a managed disk from the marketplace image, exports it as a VHD and deletes the disk again. Replace the placeholders; the SAS URL is a secret, do not paste it into a ticket or a log.

```powershell
$urn      = 'MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition-smalldisk:latest'
$diskName = '<disk name>'
$diskRG   = '<resource group>'

az disk create -g $diskRG -n $diskName --image-reference $urn
$sas = az disk grant-access --duration-in-seconds 36000 --access-level Read --name $diskName --resource-group $diskRG
$diskAccessSAS = ($sas | ConvertFrom-Json)[0].accessSas

# Download straight onto the cluster (run on a node, or download elsewhere and copy the VHD there)
azcopy copy $diskAccessSAS 'C:\ClusterStorage\Collect\base\vmfleet-base.vhd' --check-md5 NoCheck

az disk revoke-access --name $diskName --resource-group $diskRG
az disk delete --name $diskName --resource-group $diskRG --yes
```

Then, on a cluster node, convert the VHD to a fixed VHDX (VMFleet converts a dynamic disk to fixed itself, unless you pass `-KeepVHD` to `New-Fleet`) and set `storage.base_vhd_path` in the cluster YAML to the result:

```powershell
Convert-VHD -Path 'C:\ClusterStorage\Collect\base\vmfleet-base.vhd' -DestinationPath 'C:\ClusterStorage\Collect\base\vmfleet-base.vhdx' -VHDType Fixed
```

### Azure Edition: activation and Azure verification

Windows Server Azure Edition runs only on Azure infrastructure, including Azure Local, and relies on things Learn documents:

- **Azure verification for VMs** (an attestation service, on by default in Azure Local) must be working on the hosts. Check with `Get-AzureStackHCI` and `Get-AzureStackHCIAttestation` on a node; `Sync-AzureStackHCI` forces a sync. Azure Edition 2022 activates automatically with the April 2024 update (KB5036909) or later, so keep the base image current.
- **Guest Service Interface** must be enabled on each VM so it can talk to the host over VMBus. `New-Fleet` does not enable it; if you need activation, run `Get-VM -Name 'vm-*' | Enable-VMIntegrationService -Name 'Guest Service Interface'` on each node after the deploy.
- **Licensing still applies**: Windows Server subscription on the Azure Local resource (AVMA client keys) or bring your own license with Software Assurance (AVMA or KMS).
- Fleet VMs are **not Arc VMs**. Learn states that both Arc VMs and unmanaged VMs are supported for Azure Edition. If a VM does not get its license, a member of the Administrators group has to sign in to the host and run, in `FClip.exe` as administrator in the system context: `Schtasks /change /TN "\Microsoft\Windows\Clip\LicenseImdsIntegration" /RU "NT Authority\System"`.
- Learn does not say what an unactivated Azure Edition guest does after its grace period. A DiskSpd run only needs the guest to boot and run DiskSpd; if you do not want the dependency, use the Windows Server 2019 image or your own licensed Generation 2 VHDX.

### Route B (optional, unproven): an Azure Local marketplace image

`tools\vmfleet\infrastructure\Prepare-VMFleetBaseImage.ps1` creates an Azure Local marketplace gallery image through the ARM API (Az PowerShell, `Connect-AzAccount` first; prerequisites in the Learn article above: the `Microsoft.EdgeMarketplace` resource provider registered and the Azure Connected Machine Resource Manager role for the `Microsoft.AzureStackHCI` resource provider app) and then looks for the VHD(X) it left in the storage path. Learn does not document that file layout, so the script stops and lists what it found unless there is exactly one match.

```powershell
.\tools\vmfleet\infrastructure\Prepare-VMFleetBaseImage.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml -Credential $cred `
    -SubscriptionId '<subscription id>' -ResourceGroup '<resource group>' -Location '<region>' `
    -CustomLocationId '<custom location resource id>' -StoragePathId '<storage path resource id>' `
    -ImageName vmfleet-base-ws2025 -Sku 2025-datacenter-azure-edition-smalldisk
```

Nothing is committed: the IDs are parameters (or come from `-ConfigPath`, a YAML with `azure` and `azure_local` sections as in `variables.example.yml`). `-WhatIf` shows what would be submitted.

## Install VMFleet

```powershell
.\tools\vmfleet\scripts\Install-VMFleet.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred
```

Installs VMFleet `vmfleet_version` (2.1.0.0) on the first node (`Install-Module`, all users) and runs `Install-Fleet`. Parameters: `-VMFleetVersion`, `-KeepBlockCache`, `-NoTools`, `-Force`, `-RunId`, `-TimeoutMinutes`, `-WhatIf`.

## Deploy the fleet

```powershell
.\tools\vmfleet\scripts\Deploy-VMFleet.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred `
    -FleetAdminCredential $fleetAdmin -VMCount 4 -VMProcessorCount 2 -VMMemoryGB 2
```

On the node this runs `New-Fleet -BaseVHD <path> -VMs <count per node> -Admin <name> -AdminPass <password> -ConnectUser <user> -ConnectPass <password>`, then `Set-Fleet -ProcessorCount -MemoryStartupBytes`, `Start-Fleet`, and waits until `Get-FleetVM` reports every VM `Ok` (`-WaitMinutes`, default 30; a shortfall is an error). Running it again with the fleet already complete and `Ok` does nothing.

- `-FleetAdminCredential` is the **local administrator** of the fleet VMs. The domain part of the user name is dropped.
- The account the VMs use to reach the Collect volume (`-ConnectUser`) must be an administrator on every node. It defaults to `-Credential`; pass `-FleetConnectCredential` to use a dedicated account. VMFleet stores it inside the fleet VMs.
- `-DataDiskSizeGB` and `-DataDiskCount` are accepted for compatibility and **not applied**.

## Run a test

See [Workload profiles](workload-profiles.md) and the runbook in [VMFleet](index.md#run-this-test). `Start-VMFleetTest.ps1` runs `Start-FleetSweep -b <KB> -t <threads> -o <outstanding I/O> -w <write %> -p r|s -d <seconds> -Warm <seconds> -Cool <seconds> -AddSpec <run tag>`. The sweep runs one pattern, random or sequential: a profile's `random_ratio` of 50 or more means random, below 50 sequential, and a mix such as 70 is run as 100% random (the script logs a warning).

## Remove the fleet

```powershell
.\tools\vmfleet\scripts\Remove-VMFleet.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred -RemoveCollectData -Confirm:$false
```

Runs `Stop-Fleet` and `Remove-Fleet` (every fleet VM, its cluster role, its folder on the node volumes, the flag files and the `FleetInternal` switch), then checks that no `vm-*` VM and no `vm-*` folder is left and **fails if one is**. `-RemoveCollectData` also deletes the DiskSpd `result-*.xml` and `perfctr-*.blg` from `<collect>\result`. It never deletes the base image, the Collect volume or the VMFleet module. The task transcripts under `<collect>\loadtools\<run id>\` stay as evidence.

## First-time vs subsequent runs

- First time: prepare the image once, then install and deploy.
- Later: the install and deploy steps are safe to repeat; skip them with `-SkipInstall` and `-SkipDeploy` on the pipeline when the fleet exists and is `Ok`. Each run uses a new `-RunId`, which tags its result files, so an old result is never reused.

## Next steps

- [Workload Profiles](workload-profiles.md): run test workloads
- [Troubleshooting](troubleshooting.md)
