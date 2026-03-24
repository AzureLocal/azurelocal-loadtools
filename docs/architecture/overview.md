# Architecture Overview

![Category: Architecture](https://img.shields.io/badge/Category-Architecture-8E44AD?style=flat-square)

The Azure Local Load Testing Framework is organised into five layers that take a declarative configuration file as input and produce validated, auditable test reports as output. Each layer has a clear responsibility boundary and communicates with adjacent layers through well-defined file contracts and PowerShell module APIs.

---

## Five-Layer Stack

```
┌──────────────────────────────────────────────────────────────┐
│  5. Reporting Layer                                          │
│     AsciiDoc templates → PDF / DOCX / XLSX reports          │
├──────────────────────────────────────────────────────────────┤
│  4. Monitoring Layer                                         │
│     PerfMon counters, Azure Monitor, real-time alerts        │
├──────────────────────────────────────────────────────────────┤
│  3. Execution Layer                                          │
│     fio · iPerf3 · HammerDB · stress-ng · VMFleet           │
├──────────────────────────────────────────────────────────────┤
│  2. Automation Layer                                         │
│     PowerShell orchestrators, Ansible roles, modules         │
├──────────────────────────────────────────────────────────────┤
│  1. Configuration Layer                                      │
│     Master YAML → ConfigManager → solution JSON              │
└──────────────────────────────────────────────────────────────┘
```

---

## Layer Responsibilities

### Layer 1 — Configuration

The configuration layer holds all cluster-specific, credentials, and workload parameters. A single `variables.yml` file acts as the source of truth.

| Component | Location | Responsibility |
|-----------|----------|---------------|
| Master variables file | `config/variables.yml` | All environment parameters, tagged by solution |
| Workload profiles | `config/profiles/<tool>/` | Per-tool YAML profile definitions |
| ConfigManager module | `src/common/modules/ConfigManager/` | Filters, validates, and emits solution-scoped JSON |
| Schema validation | `config/schema/` | JSON Schema files that gate `ConfigManager` output |

### Layer 2 — Automation

The automation layer orchestrates pre-checks, installation, and execution across cluster nodes. All scripts consume only the ConfigManager-emitted JSON — never the raw YAML.

| Component | Location | Responsibility |
|-----------|----------|---------------|
| Orchestrator scripts | `scripts/*.ps1` | Top-level `Start-*` / `Collect-*` / `Install-*` entry points |
| Logger module | `src/common/modules/Logger/` | Structured JSON-lines logging with correlation IDs |
| StateManager module | `src/common/modules/StateManager/` | Checkpoint-based resume-after-failure |
| CredentialManager module | `src/common/modules/CredentialManager/` | Key Vault, interactive, or parameter credential retrieval |
| Ansible roles | `src/ansible/roles/<tool>/` | Linux-target deployment (fio) |

### Layer 3 — Execution

The execution layer is the load-testing tools themselves, running on cluster nodes or inside guest VMs.

| Tool | Target OS | Install Method |
|------|-----------|---------------|
| fio | Linux VMs | Ansible (`Install-Fio.ps1`) |
| iPerf3 | Linux nodes | `apt` / `dnf` (manual) |
| HammerDB | Windows nodes | PowerShell remoting (`Install-HammerDB.ps1`) |
| stress-ng | Linux nodes | `apt` / `dnf` (manual) |
| VMFleet | Windows (HCI host) | `Install-VMFleet.ps1` |

### Layer 4 — Monitoring

The monitoring layer runs in parallel with execution, capturing Windows Performance Counter data and evaluating alert rules.

| Component | Location | Responsibility |
|-----------|----------|---------------|
| MonitoringManager module | `src/common/modules/MonitoringManager/` | PerfMon collection, Azure Monitor push |
| Alert rules files | `monitoring/<tool>/alert-rules.yml` | Per-tool alert definitions |
| Grafana dashboards | `monitoring/dashboards/` | Real-time visualisation |

### Layer 5 — Reporting

The reporting layer aggregates raw JSON results, populates AsciiDoc templates, and renders final reports.

| Component | Location | Responsibility |
|-----------|----------|---------------|
| ReportGenerator module | `src/common/modules/ReportGenerator/` | Template population, `asciidoctor-pdf` invocation |
| Report templates | `reports/templates/` | Per-tool AsciiDoc templates |
| Generated reports | `reports/` | Output PDF / DOCX / XLSX files |

---

## Common Workflow Pattern

Every tool follows the same eight-phase lifecycle:

| Phase | Script Action | StateManager Checkpoint |
|-------|-------------|------------------------|
| Pre-Check | Validate connectivity, prerequisites | `pre-check-complete` |
| Install | Deploy tool binaries on target nodes | `install-complete` |
| Deploy | Configure test environment | `deploy-complete` |
| Test | Execute workload profile | `test-complete` |
| Monitor | Collect PerfMon counters (parallel) | `monitor-complete` |
| Collect | Parse and aggregate results | `collect-complete` |
| Report | Render PDF/DOCX/XLSX | `report-complete` |
| Cleanup | (Optional) Remove test artefacts | `cleanup-complete` |

Any phase can be resumed from its checkpoint if the run is interrupted.

---

## Security Model

- Credentials are **never hardcoded** in scripts or configuration files
- Three retrieval modes: Azure Key Vault (production), interactive prompt (development), parameter injection (CI/CD)
- All credential access is logged with values masked
- CI/CD pipelines use GitHub Secrets / Azure DevOps Service Connections

See [Credential Management](../operations/credential-management.md) for implementation details.

---

## Further Reading

- [Tool Selection Guide](tool-selection.md) — Choosing the right tool for your workload
- [Data Flow](data-flow.md) — End-to-end config, results, and monitoring data paths
