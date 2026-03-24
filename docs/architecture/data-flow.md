# Data Flow

![Category: Architecture](https://img.shields.io/badge/Category-Architecture-8E44AD?style=flat-square)

This page traces the three primary data flows through the framework: configuration, results, and monitoring. Understanding these paths helps when diagnosing failures, extending the framework, or integrating with external systems.

---

## Configuration Data Flow

![Configuration Data Flow](../assets/diagrams/config-flow.drawio)

### Key Rules

- Downstream scripts **never read** `variables.yml` directly. They only consume the generated JSON files.
- Variables are tagged by solution name in the master YAML (`solutions: [fio, iperf]`). `ConfigManager` emits only variables tagged for the target solution.
- Override chain (lowest wins): master YAML → environment variable → `-Variables` parameter → profile YAML

---

## Results Data Flow

![Results Data Flow](../assets/diagrams/data-flow-results.drawio)

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

![Monitoring Data Flow](../assets/diagrams/data-flow-monitoring.drawio)

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
