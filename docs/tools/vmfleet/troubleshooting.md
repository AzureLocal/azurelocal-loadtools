# VMFleet Troubleshooting

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers common VMFleet issues and their resolutions.

## Fleet VMs Fail to Start

**Symptom:** `New-Fleet` completes but VMs remain in "Off" state.

**Possible Causes:**

- Insufficient memory on cluster nodes for the configured VM count
- Base VHD file is corrupted or inaccessible
- CSV volume is full

**Resolution:**

```powershell
# Check available memory per node (by IP, with the explicit credential)
Invoke-Command -ComputerName 192.0.2.11 -Credential $cred -ScriptBlock {
    Get-Counter '\Memory\Available MBytes' | Select-Object -ExpandProperty CounterSamples
}

# Reduce VM count or memory per VM
.\tools\vmfleet\scripts\Deploy-VMFleet.ps1 `
    -ClusterConfigPath config\clusters\cluster.yml -Credential $cred -FleetAdminCredential $fleetAdmin `
    -VMCount 2 -VMMemoryGB 1
```

## A step fails: read the node transcript

Every VMFleet step runs as a one-shot scheduled task on the first node. The error message of the script names the transcript. The same files are always there:

```text
C:\ClusterStorage\Collect\loadtools\<run id>\<step>\transcript.log   what the step printed (secrets are scrubbed)
C:\ClusterStorage\Collect\loadtools\<run id>\<step>\result.json      Succeeded or Failed, the error, the output
C:\ClusterStorage\Collect\loadtools\<run id>\<step>\run.ps1          the generated script that ran
```

`<step>` is `Install`, `Deploy`, `Test`, `Stop`, `Collect` or `Remove`. The task is unregistered when the step ends; if a script was killed, remove a leftover task on the node with `Get-ScheduledTask -TaskPath '\LoadTools\' | Unregister-ScheduledTask`.

## Cannot Reach a Node

**Symptom:** `Cannot reach nodes: 192.0.2.11` or a remoting error that mentions TrustedHosts or authentication.

**Resolution:**

- The nodes are reached by IP with NTLM. Add the IPs to `TrustedHosts` on the management host: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value '192.0.2.11,192.0.2.12' -Concatenate`.
- Use `DOMAIN\user` for the credential, and an account that is an administrator on every node.
- Test with `Test-WSMan -ComputerName 192.0.2.11 -Authentication Negotiate -Credential $cred`. `Test-WSMan` without `-Authentication` sends the request anonymously and ignores the credential.
- Do not enable CredSSP; the scripts do not need it.

## Install-Fleet Reports a Missing Volume

**Symptom:** the Install step fails with `No collect CSV found` or `No CSV found for node`.

**Resolution:** VMFleet needs a CSV named `collect` and at least one CSV per node whose name starts with the node name. Create them (`Get-FleetVolumeEstimate` on a node recommends sizes) and run the install step again.

## Base VHD Not Found

**Symptom:** the Deploy step fails with `The base VHD was not found on the node` or the script stops with `No base VHD`.

**Resolution:**

1. Create the base image: [Deployment: Base image](deployment.md#base-image).
2. Put the path of the VHDX **on the node** into `storage.base_vhd_path` in `config\clusters\cluster.yml`, or pass `-BaseVHDPath`.
3. Run the deploy step again.

## Marketplace Image API Returns 400

**Symptom:** `Invoke-AzRestMethod` PUT to `marketplaceGalleryImages` returns HTTP 400.

**Resolution:**

- Verify `azure_local.custom_location_id` uses full ARM resource ID format.
- Verify `azure_local.storage_path_id` points to an existing `Microsoft.AzureStackHCI/storageContainers` resource.
- Confirm image identifier values are valid for Azure Local marketplace:
    - `publisher`: `MicrosoftWindowsServer`
    - `offer`: `WindowsServer`
    - `sku`: one of the Windows Server SKUs in [Deployment: Base image](deployment.md#base-image), for example `2025-datacenter-azure-edition-smalldisk` (the script's `-Sku`)

## provisioningState Stuck at Downloading

**Symptom:** Image download remains in `Downloading` state for extended time.

**Resolution:**

- This can be normal for large image transfers (30 to 90 minutes depending on bandwidth and storage).
- Keep polling instead of re-issuing PUT operations.
- If timeout occurs, rerun with a larger timeout:

```powershell
.\tools\vmfleet\infrastructure\Prepare-VMFleetBaseImage.ps1 -TimeoutMinutes 120
```

## DiskSpd Results Show Zero IOPS

**Symptom:** Test completes but IOPS, throughput, and latency are all zero.

**Possible Causes:**

- Fleet VMs have no data disk or DiskSpd target file
- VMFleet Collect volume is not properly configured
- DiskSpd binary is not accessible inside VMs

**Resolution:**

Run on the first node (RDP or an interactive remoting session; the VMFleet cmdlets must run on a node):

```powershell
# Verify fleet status (State 'Ok' = running with a heartbeat)
Get-FleetVM | Format-Table Name, OwnerNode, State

# Check Collect volume
Get-ClusterSharedVolume | Where-Object Name -like "*collect*"
```

A run whose result files are missing shows as `No DiskSpd result files for tag <tag>` in the Collect step: use the same `-RunId` for `Start-VMFleetTest.ps1` and `Collect-VMFleetResults.ps1`.

## Pipeline Fails Mid-Execution

**Symptom:** Orchestrator exits with an error during a specific phase.

**Resolution:**

1. Check the orchestration log: `logs/orchestrator/`
2. Check the phase-specific log: `logs/vmfleet/`
3. Review the state file: `state/run-state.json` to identify the failed phase
4. Fix the issue and resume:

```powershell
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 -ClusterConfigPath config\clusters\cluster.yml -Credential $cred -FleetAdminCredential $fleetAdmin -Resume
```

## Configuration Issues

### Schema Validation Fails

**Symptom:** `Export-SolutionConfig` reports schema validation errors.

**Resolution:**

1. Check `variables.yml` for syntax errors (use `yamllint`)
2. Verify all required fields are present for each variable
3. Run schema validation:

```powershell
.\common\helpers\Initialize-Environment.ps1 -Solution VMFleet
```

### Solution JSON Not Generated

**Symptom:** Files in `config/variables/solutions/` are empty or outdated.

**Resolution:**

```powershell
# Regenerate all solution configs
Import-Module ./common/modules/ConfigManager/ConfigManager.psm1
Export-SolutionConfig -Solution "vmfleet"
```

## Credential Issues

### Key Vault Access Denied

**Symptom:** `Get-ManagedCredential -Source KeyVault` returns 403 Forbidden.

**Resolution:**

- Verify the service principal or managed identity has `Get` secret permission on the Key Vault
- Check `config/credentials/keyvault-config.yml` for correct vault name
- Ensure Azure authentication: `Connect-AzAccount`

### Script Stops with "No credential found"

**Symptom:** A script stops with exit code 2 and the message `No credential found for 'cluster_admin'. Pass -Credential, set the environment variables CLUSTER_ADMIN_USERNAME and CLUSTER_ADMIN_PASSWORD, or map 'cluster_admin_password' ...`. No script prompts for a credential.

**Resolution:** supply the credential one of these ways:

- Pass `-Credential` (a `PSCredential` built by your pipeline or session)
- Set `CLUSTER_ADMIN_USERNAME` and `CLUSTER_ADMIN_PASSWORD` in the environment
- Map `cluster_admin_password` (and `cluster_admin_username`) under `keyvault.secrets` in `config/credentials/keyvault-config.yml` and sign in to Azure

## Monitoring Issues

### No Metrics Collected

**Symptom:** Metric files in `results/{run-id}/metrics/` are empty.

**Possible Causes:**

- WinRM connectivity lost during collection
- Performance counter set not available on target nodes
- Insufficient permissions for remote `Get-Counter`

**Resolution:**

```powershell
# Test remote counter access
Invoke-Command -ComputerName $NodeName -ScriptBlock {
    Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
}
```

## Log Locations

| Component | Log Path |
| --- | --- |
| Orchestrator | `logs/orchestrator/` |
| VMFleet | `logs/vmfleet/` |
| Monitoring | `logs/monitoring/` |
| Report Generation | `logs/reports/` |
| Configuration | `logs/orchestrator/` (config operations logged with orchestration) |

All logs use JSON-lines format. Use PowerShell to filter:

```powershell
# Find all errors in VMFleet logs
Get-Content tools/vmfleet/logs/*.jsonl | ConvertFrom-Json | Where-Object Severity -eq "ERROR"
```
