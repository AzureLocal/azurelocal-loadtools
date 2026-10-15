# Day-2 Smoke (readiness gate step)

![Category: Reference](https://img.shields.io/badge/Category-Reference-95A5A6?style=flat-square)
![Status: Not proven on hardware](https://img.shields.io/badge/Hardware-Not%20proven-yellow?style=flat-square)

An optional, roughly 15-minute VMFleet run for a Day-2 readiness gate. It uses the `Day2Smoke` profile (the General workload: 8k blocks, 30% writes, 70% random, 2 minutes of warm-up and 10 minutes measured, plus about 3 minutes to start, collect and stop). It answers "does the storage path still perform in the range we expect", not "what is the maximum". It is a smoke test, not a benchmark.

> [!WARNING]
> Running it deploys a fleet of VMs on the cluster. It has not been run on a live cluster. See [status](status.md).

## Run it

```powershell
# Run the pipeline, then evaluate (asks for confirmation; -WhatIf prints the plan and exits 3)
.\tools\vmfleet\scripts\Invoke-Day2Smoke.ps1 -OutputPath out\smoke -NodeCount 4 -FleetAdminCredential $fleetCred

# Evaluate a run that already exists (no cluster access)
.\tools\vmfleet\scripts\Invoke-Day2Smoke.ps1 -ResultPath reports\<run-id>\<run-id>-aggregate.json -OutputPath out\smoke -NodeCount 4

# Add the regression check against an approved baseline
.\tools\vmfleet\scripts\Invoke-Day2Smoke.ps1 -ResultPath candidate.json -BaselinePath baseline.json -OutputPath out\smoke -NodeCount 4
```

Thresholds come from `tools/vmfleet/config/profiles/day2-smoke.yml` (`min_iops_per_node`, `max_latency_ms`, `min_throughput_mbps`); the values shipped are examples, set your own.

## Exit codes

| Code | status | Meaning |
|------|--------|---------|
| 0 | `Pass` | Every threshold holds (and no regression, when a baseline was given) |
| 1 | `Fail` | A threshold or the regression check failed |
| 2 | `Error` | Invalid or incomparable input, unknown node count, run failed. **Not a pass.** |
| 3 | `Skipped` | Nothing was run (plan only). **Not a pass.** |

A gate script must treat every non-zero code as "not passed". The script also writes `day2-smoke-result.json` to the output folder, whatever the outcome.

## JSON result

Schema: [`day2-smoke-result.schema.json`](day2-smoke-result.schema.json) (JSON Schema 2020-12). Validate with `Test-Json -Json (Get-Content day2-smoke-result.json -Raw) -SchemaFile docs/reference/day2-smoke-result.schema.json`. The tests validate the fixtures in `tests/fixtures/day2-smoke` (four valid, three invalid) and what the code emits for every status.

| Field | Type | Notes |
|-------|------|-------|
| `schema_version` | `"1.0"` | |
| `tool`, `profile` | string | `vmfleet`, `Day2Smoke` |
| `status` | `Pass` / `Fail` / `Error` / `Skipped` | The schema ties each status to its exit code |
| `exit_code` | 0 / 1 / 2 / 3 | Same as the process exit code |
| `proven_on_hardware` | boolean | Always `false` until the owner proves the run path |
| `started_at`, `finished_at` | date-time | UTC |
| `duration_seconds` | integer | |
| `run_id`, `cluster_name` | string | Empty when no result was read |
| `node_count` | integer | Needed for the per-node IOPS check; 0 means unknown, which is an `Error` |
| `baseline_run_id` | string or null | |
| `metrics` | object or null | `total_iops`, `total_throughput_mbps`, `avg_latency_ms`, and the read/write and percentile values the result carries |
| `checks[]` | array | `metric`, `kind` (`min`, `max`, `regression`), `limit`, `actual`, `status` (`Pass`, `Fail`, `Error`) |
| `notes[]` | array of string | Reasons, including why a comparison was refused |

Example (abridged):

```json
{
  "schema_version": "1.0",
  "tool": "vmfleet",
  "profile": "Day2Smoke",
  "status": "Pass",
  "exit_code": 0,
  "proven_on_hardware": false,
  "run_id": "fixture-candidate-ok-002",
  "node_count": 4,
  "baseline_run_id": "fixture-baseline-001",
  "checks": [
    { "metric": "iops_per_node", "kind": "min", "limit": 5000, "actual": 28875, "status": "Pass" }
  ],
  "notes": []
}
```

## Using it from a gate script

```powershell
& .\tools\vmfleet\scripts\Invoke-Day2Smoke.ps1 -ResultPath $aggregate -OutputPath $out -NodeCount 4
$r = Get-Content (Join-Path $out 'day2-smoke-result.json') -Raw | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $r.status -ne 'Pass') { throw "Day-2 smoke did not pass: $($r.status)" }
```
