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
# Check available memory per node
Invoke-Command -ComputerName $ClusterNodes -ScriptBlock {
    Get-Counter '\Memory\Available MBytes' | Select-Object -ExpandProperty CounterSamples
}

# Reduce VM count or memory per VM
.\src\solutions\vmfleet\scripts\Deploy-VMFleet.ps1 `
    -ClusterConfigPath "config/clusters/my-cluster.yml" `
    -VMCount 5 `
    -VMMemoryGB 1
```

## Base VHD Not Found

**Symptom:** Deployment fails with `Base VHD not found` in `Deploy-VMFleet.ps1`.

**Resolution:**

1. Run image preparation:

```powershell
.\src\infrastructure\Prepare-VMFleetBaseImage.ps1 `
        -ConfigPath "config/variables.yml" `
        -ClusterConfigPath "config/clusters/my-cluster.yml"
```

2. Copy returned VHDX path into `storage.base_vhd_path` in `config/variables.yml`.
3. Re-run deployment.

## Marketplace Image API Returns 400

**Symptom:** `Invoke-AzRestMethod` PUT to `marketplaceGalleryImages` returns HTTP 400.

**Resolution:**

- Verify `azure_local.custom_location_id` uses full ARM resource ID format.
- Verify `azure_local.storage_path_id` points to an existing `Microsoft.AzureStackHCI/storageContainers` resource.
- Confirm image identifier values are valid for Azure Local marketplace:
    - `publisher`: `MicrosoftWindowsServer`
    - `offer`: `WindowsServer`
    - `sku`: `2022-datacenter-core-g2`

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

```powershell
# Verify fleet status
Get-FleetVM | Format-Table Name, State, ComputerName

# Check Collect volume
Get-ClusterSharedVolume | Where-Object Name -like "*Collect*"
```

## Pipeline Fails Mid-Execution

**Symptom:** Orchestrator exits with an error during a specific phase.

**Resolution:**

1. Check the orchestration log: `logs/orchestrator/`
2. Check the phase-specific log: `logs/vmfleet/`
3. Review the state file: `state/run-state.json` to identify the failed phase
4. Fix the issue and resume:

```powershell
.\Invoke-VMFleetPipeline.ps1 -ClusterConfig "config/clusters/my-cluster.yml" -Resume
```

## Configuration Issues

### Schema Validation Fails

**Symptom:** `Export-SolutionConfig` reports schema validation errors.

**Resolution:**

1. Check `master-environment.yml` for syntax errors (use `yamllint`)
2. Verify all required fields are present for each variable
3. Run schema validation:

```powershell
.\common\helpers\Initialize-Environment.ps1 -ValidateOnly
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

### Interactive Credential Prompt Not Appearing

**Symptom:** Script hangs when using `-CredentialSource Interactive` in non-interactive context.

**Resolution:**

- Use `-CredentialSource KeyVault` or `-CredentialSource Parameter` in CI/CD pipelines
- Pass credentials explicitly: `-Credential (Get-Credential)`

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
