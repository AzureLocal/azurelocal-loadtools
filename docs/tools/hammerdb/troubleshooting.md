# HammerDB — Troubleshooting

![Tool: HammerDB](https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

## HammerDB Not Found on Remote Node

**Symptom:** `Start-HammerDBTest.ps1` fails with `hammerdbcli.exe not found`.

**Resolution:**

Run `Install-HammerDB.ps1` first, or verify the install path:

```powershell
Invoke-Command -ComputerName "hci01-node1" -ScriptBlock {
    Test-Path "C:\HammerDB\hammerdbcli.exe"
}
```

If the path is custom, pass `-HammerDBPath` to `Start-HammerDBTest.ps1`.

---

## Database Connection Refused

**Symptom:** The HammerDB run exits immediately with a Tcl error like `couldn't connect to SQL Server`.

**Resolution:**

1. Verify the database server is reachable from the HammerDB node:

```powershell
Invoke-Command -ComputerName "hci01-node1" -ScriptBlock {
    Test-NetConnection "sql01.corp.infiniteimprobability.com" -Port 1433
}
```

2. Confirm credentials are valid:

```powershell
# Test SQL Server auth from the HammerDB node
Invoke-Command -ComputerName "hci01-node1" -ScriptBlock {
    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = "Server=sql01;Database=master;User Id=sa;Password=<pwd>;Connect Timeout=5"
    try { $conn.Open(); "Connected OK" } catch { $_.Exception.Message } finally { $conn.Close() }
}
```

3. For PostgreSQL, check `pg_hba.conf` allows the HammerDB node IP.

---

## Zero NOPM in Results

**Symptom:** `Collect-HammerDBResults.ps1` returns `peak_nopm: 0` and `samples: 0`.

**Possible Causes:**

- HammerDB ran but the database schema was not loaded (TPC-C build step missing)
- The test ran for less than one `ramp_up_seconds` interval — no measurement window was reached
- The log file is present but empty — hammerdbcli.exe crashed silently

**Resolution:**

```powershell
# Read the raw log to see what HammerDB actually reported
Get-Content "logs\hammerdb\<RunId>\<RunId>-hammerdb.log" | Select-Object -First 50
```

Look for `Vuser 1:FINISHED` and `System achieved` lines. If absent, the virtual users never completed a transaction cycle.

To load the TPC-C schema (one-time step before benchmarking):

```powershell
.\tools\hammerdb\scripts\Start-HammerDBTest.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -PrimaryNode "hci01-node1" `
    -Profile "tpc-c" `
    -DBServer "sql01" `
    -BuildSchema    # Loads warehouse data before running the test
```

---

## Test Duration Too Short — Ramp-Up Exceeds Duration

**Symptom:** Log shows warm-up messages but no `NOPM` measurement lines.

**Cause:** `ramp_up_seconds >= test_duration_seconds`.

**Resolution:** Ensure `test_duration_seconds > ramp_up_seconds`. The recommended minimum test window is 5 minutes (300s) after ramp:

```powershell
.\tools\hammerdb\scripts\Start-HammerDBTest.ps1 `
    -Profile "tpc-c" `
    -RampUpSeconds 120 `
    -TestDurationSeconds 420    # Total duration = 120s ramp + 300s measured
```

---

## High Variance Between NOPM Samples

**Symptom:** Peak NOPM is 2× average NOPM; results are inconsistent.

**Possible Causes:**

- Auto-growth events on the SQL Server database file — space allocation pauses write I/O
- SQL Server checkpoint storms during the test window
- Disk latency spikes (see [Monitoring](monitoring.md))

**Resolution:**

Pre-grow the database before running the benchmark:

```sql
-- SQL Server: pre-allocate to avoid auto-growth during test
USE tpcc;
DBCC SHRINKFILE (tpcc, TRUNCATEONLY);
ALTER DATABASE tpcc MODIFY FILE (NAME = tpcc, SIZE = 20GB, FILEGROWTH = 0);
```

---

## PowerShell Remoting Failures

**Symptom:** `Install-HammerDB.ps1` or `Collect-HammerDBResults.ps1` fails with `WinRM connection refused`.

See the [Operations Troubleshooting Guide](../../operations/troubleshooting.md) for WinRM connectivity resolution steps.
