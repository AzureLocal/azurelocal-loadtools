# HammerDB — Workload Profiles

![Tool: HammerDB](https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers the built-in HammerDB workload profiles and how to execute them.

## Built-in Profiles

| Profile | File | Benchmark | Database | Primary Threshold |
|---------|------|-----------|----------|-----------------|
| TPC-C SQL Server | `tpc-c.yml` | OLTP (TPC-C / TPROC-C) | SQL Server | ≥ 5,000 NOPM |
| TPC-H PostgreSQL | `tpc-h.yml` | Decision Support (TPC-H / TPROC-H) | PostgreSQL | ≥ 500 NOPM |

## Profile Details

### TPC-C SQL Server (OLTP)

Simulates an order-entry OLTP workload across multiple warehouses. The primary metric is **NOPM** (New Orders Per Minute) — the HammerDB-normalized equivalent of tpmC.

```yaml
profile:
  name: "TPC-C SQL Server"
  description: "OLTP TPC-C benchmark targeting SQL Server — NOPM/TPM measurement"
  category: "oltp"
  parameters:
    benchmark_type: "tpcc"
    db_type: "mssql"
    db_server: ""           # Override with target DB server hostname/IP
    db_name: "tpcc"
    warehouse_count: 10
    virtual_users: 4
    ramp_up_seconds: 120
    test_duration_seconds: 300
  expected_thresholds:
    min_nopm: 5000
    min_tpm: 8000
```

**When to use:** SQL Server OLTP capacity planning; pre-production SQL Server performance sign-off; storage subsystem validation under realistic DB write patterns.

**NOPM vs TPM:**
- **TPM** (Transactions Per Minute) — raw HammerDB transaction count; includes all transaction types
- **NOPM** (New Orders Per Minute) — the "new order" subset; more comparable across runs and systems

### TPC-H PostgreSQL (Decision Support)

Simulates complex analytical query workloads using the TPC-H decision-support schema. Uses PostgreSQL as the target database.

```yaml
profile:
  name: "TPC-H PostgreSQL"
  description: "Decision-support TPC-H benchmark targeting PostgreSQL — query throughput measurement"
  category: "dss"
  parameters:
    benchmark_type: "tpch"
    db_type: "postgresql"
    db_server: ""           # Override with target DB server hostname/IP
    db_name: "tpch"
    warehouse_count: 5      # scale factor
    virtual_users: 2
    ramp_up_seconds: 60
    test_duration_seconds: 600
  expected_thresholds:
    min_tpm: 1000
    min_nopm: 500
```

**When to use:** PostgreSQL analytical workload validation; storage read throughput assessment for DSS; query parallelism validation.

## Running Profiles

### Single Profile

```powershell
.\tools\hammerdb\scripts\Start-HammerDBTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1" `
    -Profile "tpc-c" `
    -DBServer "sql01.corp.infiniteimprobability.com"
```

### Override Parameters at Runtime

```powershell
.\tools\hammerdb\scripts\Start-HammerDBTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1" `
    -Profile "tpc-c" `
    -DBServer "sql01" `
    -WarehouseCount 50 `
    -VirtualUsers 8 `
    -TestDurationSeconds 600
```

Explicit parameters override profile values; profile values override `hammerdb.json` defaults.

### Running Both Benchmark Types

```powershell
$node = "hci01-node1"
$sqlServer = "sql01.corp.infiniteimprobability.com"

# OLTP — TPC-C against SQL Server
$tpcc = .\tools\hammerdb\scripts\Start-HammerDBTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode $node `
    -Profile "tpc-c" `
    -DBServer $sqlServer

.\tools\hammerdb\scripts\Collect-HammerDBResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode $node `
    -RunId $tpcc.RunId

# DSS — TPC-H against PostgreSQL
$pgServer = "pg01.corp.infiniteimprobability.com"
$tpch = .\tools\hammerdb\scripts\Start-HammerDBTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode $node `
    -Profile "tpc-h" `
    -DBServer $pgServer

.\tools\hammerdb\scripts\Collect-HammerDBResults.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode $node `
    -RunId $tpch.RunId
```

## Profile Schema

```yaml
profile:
  name: string                # Human-readable name
  description: string
  category: string            # oltp | dss
  parameters:
    benchmark_type: string    # tpcc | tpch
    db_type: string           # mssql | postgresql | mysql | oracle
    db_server: string         # Hostname or IP of the database server
    db_name: string           # Database/schema name to use
    warehouse_count: integer  # TPC-C: warehouse count; TPC-H: scale factor
    virtual_users: integer    # HammerDB virtual user (VU) count
    ramp_up_seconds: integer  # Driver warm-up period before measurement
    test_duration_seconds: integer
  expected_thresholds:
    min_nopm: integer
    min_tpm: integer
```

## Sizing Guidance

| Environment | Warehouse Count (TPC-C) | Virtual Users |
|-------------|------------------------|---------------|
| Development / small validation | 5–10 | 2–4 |
| Pre-production sign-off | 50–100 | 8–16 |
| Production capacity planning | 100–500 | 16–64 |

Start with the defaults in the profile; scale up only if the system sustains > 80% CPU and the NOPM ceiling is not yet reached.
