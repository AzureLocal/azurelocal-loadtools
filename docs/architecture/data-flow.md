# Data Flow

![Category: Architecture](https://img.shields.io/badge/Category-Architecture-8E44AD?style=flat-square)

This page traces the three primary data flows through the framework: configuration, results, and monitoring. Understanding these paths helps when diagnosing failures, extending the framework, or integrating with external systems.

---

## Configuration Data Flow

```
config/variables.yml
        │
        ▼
  ConfigManager.psm1
  ┌────────────────────────┐
  │ 1. Load master YAML    │
  │ 2. Filter by solution  │
  │ 3. Validate vs schema  │
  │ 4. Apply overrides     │
  └────────────────────────┘
        │
        ├──► config/json/fio.json
        ├──► config/json/iperf.json
        ├──► config/json/hammerdb.json
        ├──► config/json/stress-ng.json
        └──► config/json/vmfleet.json
                 │
                 ▼
        scripts/Start-*.ps1
        (consumes only generated JSON)
```

### Key Rules

- Downstream scripts **never read** `variables.yml` directly. They only consume the generated JSON files.
- Variables are tagged by solution name in the master YAML (`solutions: [fio, iperf]`). `ConfigManager` emits only variables tagged for the target solution.
- Override chain (lowest wins): master YAML → environment variable → `-Variables` parameter → profile YAML

---

## Results Data Flow

```
Target Nodes (Linux / Windows)
        │
        │  (SSH/WinRM — batch execution)
        ▼
scripts/Start-<Tool>.ps1
        │
        │  Tool runs on node: writes raw output to /tmp or C:\
        │
        ▼
Raw results on node:
  /tmp/fio-results/<RunId>/<node>-<job>.json          (fio)
  /tmp/iperf-results/<RunId>/<client>-to-<server>.json (iPerf3)
  /tmp/stress-ng-results/<RunId>/stress-ng-results.yml (stress-ng)
  C:\hammerdb-results\<RunId>\hammerdb-output.log      (HammerDB)
        │
        │  (SCP / WinRM copy)
        ▼
scripts/Collect-<Tool>.ps1
  ┌─────────────────────────────────────┐
  │ 1. Copy raw files from all nodes    │
  │ 2. Parse tool-specific format       │
  │ 3. Normalise metric fields          │
  │ 4. Compute aggregate statistics     │
  │ 5. Write aggregate + per-node JSON  │
  └─────────────────────────────────────┘
        │
        ▼
logs\<tool>\<RunId>\
  ├── <RunId>-aggregate.json     ← Primary report input
  ├── <RunId>-per-<node|job>.json
  └── <node>-raw-output.*        (preserved for audit)
        │
        ▼
scripts/New-LoadReport.ps1
  ┌──────────────────────────────────────────────┐
  │ 1. Read aggregate JSON                       │
  │ 2. Populate reports/templates/<tool>-*.adoc  │
  │ 3. Invoke asciidoctor-pdf / pandoc           │
  │ 4. Write PDF / DOCX / XLSX to reports/       │
  └──────────────────────────────────────────────┘
        │
        ▼
reports/<RunId>.<pdf|docx|xlsx>
```

### Aggregate JSON Contract

Every tool's `Collect-*.ps1` writes a JSON file conforming to the same top-level envelope:

```json
{
  "run_id": "string",
  "tool": "string",
  "profile": "string",
  "node_count": int,
  "<tool_specific_metrics>": { ... },
  "collected_at": "ISO 8601 UTC"
}
```

Report templates rely on this envelope structure; adding a new tool requires a corresponding template that maps its specific metric fields.

---

## Monitoring Data Flow

```
Target Nodes
        │
        │  (WMI / WinRM)
        ▼
MonitoringManager.psm1
  ┌────────────────────────────────────────┐
  │ Runs in parallel with Start-<Tool>.ps1 │
  │ 1. Read monitoring/<tool>/alert-rules  │
  │ 2. Sample PerfMon counters every N sec │
  │ 3. Evaluate each rule condition        │
  │ 4. On trigger: log alert + send        │
  └────────────────────────────────────────┘
        │
        ├──► logs\<tool>\<RunId>\monitor-<node>.jsonl  (all samples)
        ├──► logs\<tool>\<RunId>\alerts-<node>.jsonl   (triggered alerts only)
        └──► Azure Monitor (if configured)
                 │
                 ▼
            Grafana Dashboard
            (reads from Azure Monitor workspace)
```

### Alert Rule Evaluation

Alert rules are defined in `monitoring/<tool>/alert-rules.yml`. Each rule specifies:

| Field | Description |
|-------|-------------|
| `counter` | Windows Performance Counter path |
| `condition` | `<`, `>`, or `==` |
| `threshold` | Numeric value |
| `cooldown_seconds` | Minimum seconds between repeated alerts for the same rule |
| `severity` | `warning` or `critical` |

When a rule fires, `MonitoringManager` appends a structured JSON line to `alerts-<node>.jsonl` with the rule name, counter value, node name, and UTC timestamp. The `Collect-*.ps1` scripts include a threshold violation review step that surfaces any alerts recorded during the run.

---

## Correlation IDs

Every log line written by the `Logger` module includes a `correlation_id` field set to the `RunId` passed to `Start-*.ps1`. This allows correlating entries across:

- `monitor-<node>.jsonl` — PerfMon samples
- `alerts-<node>.jsonl` — Alert triggers
- `<RunId>-aggregate.json` — Parsed results
- `state/<RunId>.json` — Checkpoint state

When investigating a failed or anomalous run, filter all log files by `"correlation_id": "<RunId>"` to reconstruct the full timeline.
