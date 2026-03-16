# Cmdlet Reference

![Category: Reference](https://img.shields.io/badge/Category-Reference-7F8C8D?style=flat-square)

This document covers the custom PowerShell functions provided by the core modules.

## ConfigManager Module

### Export-SolutionConfig

Generates a solution-specific JSON configuration file from the master environment.

```powershell
Export-SolutionConfig [-Solution] <string> [-MasterConfigPath <string>] [-OutputPath <string>]
```

**Parameters**

| Parameter | Type | Description |
| --- | --- | --- |
| `-Solution` | string | Solution name: vmfleet, fio, iperf, hammerdb, stress-ng |
| `-MasterConfigPath` | string | Path to master-environment.yml (default: `config/variables/master-environment.yml`) |
| `-OutputPath` | string | Output path for generated JSON (default: `config/variables/solutions/{solution}.json`) |

### Get-ConfigValue

Retrieves a configuration value with override chain support.

```powershell
Get-ConfigValue [-Name] <string> [-Solution <string>] [-DefaultValue <object>] [-Override <object>]
```

## Logger Module

### Write-Log

Writes a structured log entry to the component log file.

```powershell
Write-Log [-Message] <string> [-Severity <string>] [-Component <string>] [-Data <hashtable>]
```

**Severity Levels**

- `DEBUG` — Detailed diagnostic information
- `INFO` — General operational messages
- `WARNING` — Potential issues that don't stop execution
- `ERROR` — Failures that affect the current operation
- `CRITICAL` — Fatal errors requiring immediate attention

### Start-LogSession / Stop-LogSession

Manages log session lifecycle with correlation IDs.

```powershell
$sessionId = Start-LogSession -Component "VMFleet" -RunId "run-001"
# ... operations ...
Stop-LogSession -SessionId $sessionId
```

## StateManager Module

### New-RunState

Creates a new run state file for tracking automation progress.

```powershell
New-RunState [-RunId] <string> [-Phases <string[]>]
```

### Update-RunPhase

Updates the status of a specific phase in the run state.

```powershell
Update-RunPhase [-RunId] <string> [-Phase] <string> [-Status] <string> [-Details <hashtable>]
```

**Phase Statuses**

- `pending` — Not yet started
- `running` — Currently executing
- `completed` — Successfully finished
- `failed` — Encountered an error
- `skipped` — Intentionally bypassed

### Test-PhaseCompleted

Checks if a phase has already completed (for resume support).

```powershell
Test-PhaseCompleted [-RunId] <string> [-Phase] <string>
```

## CredentialManager Module

### Get-ManagedCredential

Retrieves credentials from the configured source.

```powershell
Get-ManagedCredential [-Name] <string> [-Source <string>] [-VaultConfig <string>]
```

**Credential Sources**

- `KeyVault` — Retrieve from Azure Key Vault
- `Interactive` — Prompt user with `Get-Credential`
- `Parameter` — Expect credential passed as parameter

## MonitoringManager Module

### Start-MetricCollection

Begins background metric collection for the specified categories.

```powershell
Start-MetricCollection [-Categories <string[]>] [-SampleIntervalSeconds <int>] [-OutputPath <string>]
```

### Stop-MetricCollection

Stops background metric collection and finalizes output files.

```powershell
Stop-MetricCollection [-CollectionId] <string>
```

## ReportGenerator Module

### New-TestReport

Generates test reports in the specified formats.

```powershell
New-TestReport [-RunId] <string> [-ResultsPath <string>] [-OutputPath <string>]
             [-Formats <string[]>] [-IncludeMetrics] [-ClusterConfig <string>]
```
