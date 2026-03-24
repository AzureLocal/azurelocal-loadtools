# HammerDB — Installation

![Tool: HammerDB](https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers deploying HammerDB onto Windows VMs on the Azure Local cluster via PowerShell remoting.

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- Windows VMs deployed on the Azure Local cluster with WinRM enabled
- The `cluster_admin` credential available via Key Vault or interactively — see [Credential Management](../../operations/credential-management.md)
- Outbound internet access from the target node (to download the HammerDB installer from GitHub), **or** a local copy of the installer placed at a UNC path
- A SQL Server or PostgreSQL instance deployed and accessible from the target VM

## Install HammerDB via PowerShell Remoting

`Install-HammerDB.ps1` downloads and silently installs HammerDB on the target node:

```powershell
.\tools\hammerdb\scripts\Install-HammerDB.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1") `
    -HammerDBVersion "4.6"
```

### What the Script Does

1. Connects to each node via PowerShell remoting (`Invoke-RemoteCommand`)
2. Checks if HammerDB is already installed at the default path — skips if present (use `-Force` to reinstall)
3. Downloads the GitHub release installer: `HammerDB-<Version>-Win.exe`
4. Runs silent install: `Start-Process -FilePath installer -ArgumentList "/S /D=C:\HammerDB"`
5. Returns `@{ ClusterName; Nodes; Version; InstallPath; Status }`

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ClusterName` | string | required | Cluster display name |
| `-Nodes` | string[] | required | Target Windows VM hostnames |
| `-HammerDBVersion` | string | `4.6` | GitHub release version to download |
| `-InstallPath` | string | `C:\HammerDB` | Destination install directory |
| `-Force` | switch | false | Re-install even if already present |
| `-CredentialSource` | string | `Interactive` | `KeyVault`, `Interactive`, or `Parameter` |

## Verify Installation

```powershell
# Confirm hammerdbcli.exe is present on the target node
Invoke-Command -ComputerName "hci01-node1" -ScriptBlock {
    Test-Path "C:\HammerDB\hammerdbcli.exe"
    & "C:\HammerDB\hammerdbcli.exe" --version
}
```

## Supported HammerDB Version

The framework targets **HammerDB 4.6**. The Tcl script generation in `Start-HammerDBTest.ps1` uses the `diset`/`vuset` API present in 4.x. Versions earlier than 4.0 use a different CLI interface and are not supported.

## Database Prerequisites

| Database | Required Configuration |
|----------|----------------------|
| SQL Server | Named instance accessible from the HammerDB node; `SA` or admin credentials available; `tempdb` on fast storage |
| PostgreSQL | `pg_hba.conf` allows connections from the HammerDB node; superuser or `pg_monitor` role available |

Set the database server via the profile's `db_server` parameter or `-DBServer` at runtime.

## Remote Working Directories

| Path | Purpose |
|------|---------|
| `C:\hammerdb-results\<RunId>\` | Test output, generated Tcl scripts, and raw log |

Results are retrieved by `Collect-HammerDBResults.ps1` via PowerShell remoting (file read) and are not automatically deleted — retain for audit purposes.

## Next Steps

- [Workload Profiles](workload-profiles.md) — Choose TPC-C or TPC-H and configure parameters
- [Monitoring](monitoring.md) — Review CPU and memory alert thresholds during HammerDB runs
