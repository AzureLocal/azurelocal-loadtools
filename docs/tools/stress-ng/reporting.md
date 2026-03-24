# stress-ng — Reporting

![Tool: stress-ng](https://img.shields.io/badge/Tool-stress--ng-E74C3C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

`Collect-StressNgResults.ps1` retrieves the raw YAML output written by stress-ng on each target node, parses the per-stressor metrics, and writes normalised aggregate JSON to the `logs\stress-ng\<RunId>\` directory.

---

## Collection Steps

```powershell
.\scripts\Collect-StressNgResults.ps1 -RunId "stressng-cpu-202412011430"
```

The script performs the following in sequence:

1. **SCP retrieval** — Copies `/tmp/stress-ng-results/<RunId>/stress-ng-results.yml` from each target node to `logs\stress-ng\<RunId>\<node>-stress-ng-results.yml`
2. **YAML parse** — Loads the YAML using `ConvertFrom-Yaml`; accesses metrics via `$stressData.'stress-ng'.metrics` (note: the hyphen in the key requires single-quote wrapping in PowerShell)
3. **Per-stressor normalisation** — Extracts `bogo-ops`, `bogo-ops-per-second-usr-sys-time`, `real-time`, `usr-time`, and `sys-time` for every stressor in every node's output
4. **Aggregate computation** — Calculates mean bogo-ops/sec and total bogo-ops across all nodes per stressor
5. **Write output** — Saves `<RunId>-aggregate.json` and `<RunId>-per-node.json` to `logs\stress-ng\<RunId>\`

---

## Output Files

| File | Content |
|------|---------|
| `logs\stress-ng\<RunId>\<RunId>-aggregate.json` | Cross-node aggregate metrics per stressor |
| `logs\stress-ng\<RunId>\<RunId>-per-node.json` | Per-node, per-stressor raw metrics |
| `logs\stress-ng\<RunId>\<node>-stress-ng-results.yml` | Raw YAML from stress-ng on each node (preserved for audit) |

---

## Aggregate JSON Schema

```json
{
  "run_id": "stressng-cpu-202412011430",
  "profile": "cpu-stress",
  "node_count": 4,
  "stressor_results": [
    {
      "stressor": "cpu",
      "avg_bogo_ops_per_sec": 185432.6,
      "total_bogo_ops": 3708652,
      "node_count": 4
    },
    {
      "stressor": "cpu-cache",
      "avg_bogo_ops_per_sec": 94211.0,
      "total_bogo_ops": 1884220,
      "node_count": 4
    }
  ],
  "collected_at": "2024-12-01T14:45:00Z"
}
```

### Aggregate Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `run_id` | string | Matches the `-RunId` parameter |
| `profile` | string | Profile name from the YAML definition |
| `node_count` | int | Number of nodes that produced results |
| `stressor_results[].stressor` | string | stress-ng stressor name (`cpu`, `vm`, `hdd`, etc.) |
| `stressor_results[].avg_bogo_ops_per_sec` | float | Mean bogo-ops/sec across all nodes for this stressor |
| `stressor_results[].total_bogo_ops` | int | Sum of bogo-ops across all nodes |
| `stressor_results[].node_count` | int | Nodes that reported this stressor (may be < total if OOM killed) |
| `collected_at` | ISO 8601 | UTC timestamp when collection completed |

---

## Per-Node JSON Schema

```json
{
  "run_id": "stressng-cpu-202412011430",
  "nodes": [
    {
      "node": "hci01-node1",
      "stressors": [
        {
          "stressor": "cpu",
          "bogo_ops": 927163,
          "bogo_ops_per_sec_usr_sys": 185432.6,
          "real_time_s": 300.1,
          "usr_time_s": 4800.4,
          "sys_time_s": 0.3
        }
      ]
    }
  ]
}
```

---

## YAML Key Note

The raw stress-ng output nests metrics under the `stress-ng` key, which contains a hyphen. In PowerShell, accessing this key requires single-quote notation:

```powershell
$raw     = Get-Content "hci01-node1-stress-ng-results.yml" -Raw
$parsed  = $raw | ConvertFrom-Yaml
$metrics = $parsed.'stress-ng'.metrics   # Must quote the hyphenated key
```

---

## Interpreting Results

### Bogo-ops vs. Bogo-ops/sec

- **`total_bogo_ops`** is the raw operation count over the full `timeout` window. Use this for absolute throughput comparisons across runs of equal duration.
- **`avg_bogo_ops_per_sec`** normalises for wall-clock time. Use this when comparing results where one node throttled and finished fewer operations than expected.

### Identifying Outlier Nodes

```powershell
$perNode = Get-Content "logs\stress-ng\stressng-cpu-202412011430\*-per-node.json" |
    ConvertFrom-Json

$perNode.nodes | ForEach-Object {
    $node = $_.node
    $_.stressors | Where-Object { $_.stressor -eq "cpu" } |
        Select-Object @{n="Node";e={$node}}, bogo_ops_per_sec_usr_sys
} | Sort-Object bogo_ops_per_sec_usr_sys
```

A node reporting bogo-ops/sec more than 15% below the cluster mean likely experienced throttling or interference. Review monitoring logs for `stressng_cpu_throttling` alert events recorded during that run window.

---

## Report Generation

Aggregate results are available as input for the reporting template:

```powershell
.\scripts\New-LoadReport.ps1 -RunId "stressng-cpu-202412011430" -Tool stress-ng `
    -TemplatePath "reports\templates\stress-ng-report.adoc" `
    -OutputPath "reports\stressng-cpu-202412011430.pdf"
```

The template uses the following aggregate JSON fields as placeholders:

| Placeholder | Source Field |
|-------------|-------------|
| `{run_id}` | `run_id` |
| `{profile}` | `profile` |
| `{node_count}` | `node_count` |
| `{cpu_avg_bogo_ops_per_sec}` | `stressor_results[stressor=cpu].avg_bogo_ops_per_sec` |
| `{memory_avg_bogo_ops_per_sec}` | `stressor_results[stressor=vm].avg_bogo_ops_per_sec` |
| `{io_avg_bogo_ops_per_sec}` | `stressor_results[stressor=hdd].avg_bogo_ops_per_sec` |
| `{collected_at}` | `collected_at` |
