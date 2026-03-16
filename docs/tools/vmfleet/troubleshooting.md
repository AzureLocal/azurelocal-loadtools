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
.\Deploy-VMFleet.ps1 -VmCountPerNode 5 -VmMemoryGb 1
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
.\src\core\powershell\helpers\Initialize-Environment.ps1 -ValidateOnly
```

### Solution JSON Not Generated

**Symptom:** Files in `config/variables/solutions/` are empty or outdated.

**Resolution:**

```powershell
# Regenerate all solution configs
Import-Module ./src/core/powershell/modules/ConfigManager/ConfigManager.psm1
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
Get-Content logs/vmfleet/*.jsonl | ConvertFrom-Json | Where-Object Severity -eq "ERROR"
```
