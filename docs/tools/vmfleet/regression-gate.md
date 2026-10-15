# Reports, Comparison and Regression Gate

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Status: Tested on fixtures](https://img.shields.io/badge/Hardware-Not%20proven-yellow?style=flat-square)

Three offline helpers work on the aggregate result JSON that the collect phase writes (`<run-id>-aggregate.json`). They read files only: no cluster, no network, no extra module.

| Script | What it does |
|--------|--------------|
| `tools/vmfleet/scripts/New-VMFleetReport.ps1` | Writes a self-contained HTML report and a CSV file from one result, optionally against a baseline |
| `tools/vmfleet/scripts/Compare-VMFleetResults.ps1` | Compares a candidate with a baseline and exits 0 / 1 / 2 |
| `Get-ResultTrend` (ResultAnalysis module) | Orders several results by time and compares each run with the previous one |

PDF, DOCX and XLSX reports stay with the pipeline's ReportGenerator module (asciidoctor-pdf, pandoc, ImportExcel). They are not exercised by the unit tests.

## Report

```powershell
.\tools\vmfleet\scripts\New-VMFleetReport.ps1 -ResultPath reports\run-2\run-2-aggregate.json -BaselinePath reports\run-1\run-1-aggregate.json -OutputPath out\run-2
```

The HTML has no scripts and no external resources, and every value is encoded. The CSV neutralises text cells that start with `=`, `+`, `-` or `@` so a spreadsheet does not evaluate them.

## Regression gate

```powershell
.\tools\vmfleet\scripts\Compare-VMFleetResults.ps1 -BaselinePath baseline.json -CandidatePath candidate.json -OutputPath out
$LASTEXITCODE
```

| Exit code | Meaning |
|-----------|---------|
| 0 | No regression beyond the thresholds |
| 1 | Regression: at least one gated metric is worse than its limit |
| 2 | Not comparable or invalid input. **Never a pass.** |

Gated metrics: `total_iops` and `total_throughput_mbps` (a drop of more than 10% fails), `avg_latency_ms` (a rise of more than 15% plus 0.1 ms of noise allowance fails), and `p95_latency_ms` / `p99_latency_ms` when the baseline has them. Override per metric with `-Threshold @{ total_iops = 5 }`. Higher-is-better limits must be below 100, so a threshold cannot disable the gate.

The gate fails closed (exit 2) when:

- a required metric is missing, or the candidate dropped a tail-latency metric the baseline had;
- a value is not a finite, non-negative number;
- the profile, VM count, cluster name or any workload parameter (block size, write and random ratio, queue depth, threads, duration, warm-up) differs, or the parameters are recorded on one side only;
- the baseline and candidate are the same run or the same file;
- the baseline shows no I/O at all, or a limit overflows.

`-AllowMismatch` compares anyway and still lists the mismatch. Pick the baseline deliberately (an approved, recent run on the same cluster and profile). The gate cannot tell a stale or cherry-picked baseline from a good one.

## Limits

These checks are unit-tested on fixtures in `tests/fixtures/results`. They have not been run against results from a real cluster. A relative gate says "no worse than the baseline", not "good enough for the workload": pair it with absolute thresholds, as the [Day-2 smoke](../../reference/day2-smoke.md) does.
