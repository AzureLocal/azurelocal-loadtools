# Solution Architecture

![Category: Getting Started](https://img.shields.io/badge/Category-Getting%20Started-2ECC71?style=flat-square)

> **This page is a summary.** For the full architecture documentation, see the [Architecture](../architecture/overview.md) section.

The framework consists of five major layers:

- **Configuration Layer** — Master environment variables, cluster configs, workload profiles, credential management
- **Automation Layer** — PowerShell modules, Ansible roles, orchestrator scripts
- **Execution Layer** — Load testing tools (VMFleet, fio, iPerf3, HammerDB, stress-ng) running on cluster nodes and VMs
- **Monitoring Layer** — PerfMon counter collection, Azure Monitor integration, real-time dashboards
- **Reporting Layer** — Metric aggregation, AsciiDoc template population, multi-format output generation

## Architecture Guides

| Guide | Description |
|-------|-------------|
| [Architecture Overview](../architecture/overview.md) | Five-layer stack, component table, and common workflow lifecycle |
| [Tool Selection](../architecture/tool-selection.md) | Decision flowchart and comparison matrix for choosing the right tool |
| [Data Flow](../architecture/data-flow.md) | End-to-end config, results, and monitoring data paths |

## Configuration Flow

<!-- TODO: Export from docs/diagrams/config-flow.drawio -->
<!-- image: config-flow.svg -->

**Configuration Pipeline**

```text
master-environment.yml    →    ConfigManager Module    →    vmfleet.json
  (all variables,               (filters by              (only VMFleet
   tagged by solution)           solution tag)             variables)
```

The `ConfigManager` PowerShell module reads the master environment file, filters variables by their solution tags, and generates solution-specific JSON files. Downstream scripts consume only the generated JSON — never the master YAML directly.

## Component Diagram

**Core Components**

| Component | Responsibility | Location |
|-----------|---------------|----------|
| ConfigManager | Variable management, filtering, override chain | `common/modules/ConfigManager/` |
| Logger | Structured JSON-lines logging with correlation IDs | `common/modules/Logger/` |
| StateManager | Run state tracking, checkpoints, resume capability | `common/modules/StateManager/` |
| CredentialManager | KeyVault, interactive, or parameter-based credential retrieval | `common/modules/CredentialManager/` |
| MonitoringManager | PerfMon collection, Azure Monitor push | `common/modules/MonitoringManager/` |
| ReportGenerator | PDF, DOCX, XLSX report generation | `common/modules/ReportGenerator/` |

## Tool Automation Workflows

Each tool follows a common workflow pattern, adapted to its specific requirements:

1. **Pre-Check** — Validate cluster connectivity, tool-specific prerequisites
2. **Install** — Install required modules and dependencies on target nodes
3. **Deploy** — Deploy test workloads (VMs, containers, services)
4. **Test** — Execute workload profiles
5. **Monitor** — Collect metrics in parallel with test execution
6. **Collect** — Parse results, aggregate metrics
7. **Report** — Generate PDF, DOCX, and XLSX reports
8. **Cleanup** — (Optional) Remove test workloads

Each phase is checkpoint-tracked via `StateManager`, enabling resume after failure.

See individual tool guides for tool-specific workflow details:

- [VMFleet Workflow](../tools/vmfleet/overview.md)
- [fio Workflow](../tools/fio/overview.md)
- [iPerf3 Workflow](../tools/iperf/overview.md)
- [HammerDB Workflow](../tools/hammerdb/overview.md)
- [stress-ng Workflow](../tools/stress-ng/overview.md)

## Network Topology

<!-- TODO: Export from docs/diagrams/network-topology.drawio -->
<!-- image: network-topology.svg -->

A typical Azure Local cluster deployment includes:

- **Management Network** — Cluster management, PowerShell remoting, monitoring traffic
- **Storage Network** — RDMA/SMB Direct traffic between cluster nodes (dedicated NICs)
- **Compute/VM Network** — Virtual machine workload traffic
- **Management Station** — Automation execution host with line-of-sight to management network

## Security Model

All credential handling follows the principle of least privilege:

- Credentials are **never hardcoded** in scripts or configuration files
- Three credential retrieval modes: Azure Key Vault, interactive prompt, or parameter injection
- Key Vault access via managed identity or service principal
- CI/CD pipelines use GitHub Secrets / Azure DevOps Service Connections / GitLab CI Variables
- All credential access is logged (value masked) for audit trail

See [Credential Management](../operations/credential-management.md) for full details.
