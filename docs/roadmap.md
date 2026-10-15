# Roadmap

![Category: Project](https://img.shields.io/badge/Category-Project-95A5A6?style=flat-square)

This page tracks the feature roadmap for the Azure Local Load Testing Framework. It uses the same vocabulary as the [implementation status](reference/status.md) table, which is the single source of truth: **Implemented** (scripts exist), **Unit-tested** (Pester with mocks and fixtures) and **Proven on hardware** (run end to end on a real cluster).

> [!IMPORTANT]
> Earlier versions of this page marked every item "Complete". That meant "code written", not "proven". No tool has been proven on a live cluster yet, so no item below is marked as hardware-proven.

Legend: ✅ done, 🟡 partly done (see the note), 🔲 planned.

---

## Milestone 1: Core tool implementation (implemented and unit-tested, not proven on hardware)

| Item | Implemented | Unit-tested | Proven on hardware |
|------|-------------|-------------|--------------------|
| fio storage benchmarking (Linux VMs) | ✅ | ✅ | 🔲 |
| iPerf3 network throughput (TCP, UDP, mesh); not RDMA | ✅ | ✅ | 🔲 |
| HammerDB (SQL Server TPC-C, TPC-H profiles) | ✅ | ✅ | 🔲 |
| stress-ng (CPU, memory, I/O) | ✅ | ✅ | 🔲 |
| VMFleet fleet workload simulation | ✅ | ✅ | 🔲 |
| ConfigManager, Logger, StateManager | ✅ | ✅ | 🔲 |
| CredentialManager, MonitoringManager | ✅ | 🔲 (no tests yet) | 🔲 |

## Milestone 2: Documentation overhaul ✅

Tool pages, architecture, reference and operations pages exist. Known gap: some command examples on tool pages use parameter names the scripts do not have (for example `-CredentialSource`); the script `param` blocks are the authority until the pages are rewritten. The [status](reference/status.md) page lists the known gaps.

## Milestone 3: Reporting enhancements 🟡

| Item | Status |
|------|--------|
| Offline report from result fixtures: HTML and CSV (`New-VMFleetReport.ps1`) | ✅ unit-tested on fixtures |
| Trend comparison: compare two result sets and highlight regressions (`Get-ResultTrend`, `Compare-LoadTestResult`) | ✅ unit-tested on fixtures |
| PDF (asciidoctor-pdf), DOCX (pandoc) and XLSX (ImportExcel) reports | 🟡 code exists in ReportGenerator; the external tools are not exercised by the tests |
| Report templates for all five tools (AsciiDoc) | 🟡 templates exist; only VMFleet has a result collector that feeds the offline report |
| Azure Monitor workbook integration | 🟡 a VMFleet workbook JSON exists; not tested |
| Grafana dashboard JSON export | 🔲 planned |

## Milestone 4: CI/CD maturity 🟡

| Item | Status |
|------|--------|
| GitHub Actions `ci.yml`: analyzer (errors fail, more than 50 warnings fail), Pester per suite, link check; actions pinned to SHAs | ✅ |
| Release automation: release-please workflow, CHANGELOG, module version 0.1.0 | ✅ wired; no release has been cut yet |
| Azure DevOps validate pipeline with parity to GitHub Actions (`tests/Invoke-CiChecks.ps1`) | ✅ |
| Regression gate: `Compare-VMFleetResults.ps1` (exit 0 / 1 / 2) and the Day-2 smoke JSON | ✅ unit-tested, 🔲 not wired into a workflow (needs a cluster) |
| Pester coverage for all PowerShell modules | 🟡 Config, Logger, State, Report, ResultAnalysis, FaultInjection covered; Credential and Monitoring not |
| GitLab CI pipeline | 🔲 planned (an earlier version of the docs described one; it was never built) |
| Container-based runner image | 🔲 planned |
| Signed commits enforcement and branch protection | 🔲 planned |

## Milestone 5: Extended tool support 🟡

| Item | Status |
|------|--------|
| Opt-in failure injection for VMFleet runs (node pause, drive fault) | ✅ implemented, mocked tests, not proven on hardware: [Failure injection](tools/vmfleet/failure-injection.md) |
| Day-2 smoke profile and result schema for a readiness gate | ✅ implemented, tested on fixtures, not proven on hardware: [Day-2 smoke](reference/day2-smoke.md) |
| DiskSpd Windows storage benchmarking (equivalent to fio for Windows targets) | 🔲 planned (VMFleet uses DiskSpd inside the fleet VMs) |
| RDMA-specific network tests | 🔲 planned; see the [network guidance](tools/iperf/azure-local-network-guidance.md) for what iPerf3 cannot test |
| PostgreSQL TPC-C profile in HammerDB | 🔲 planned |
| fio RDMA I/O engine support | 🔲 planned |
| Kubernetes workload profile (K8s on AKS Arc) | 🔲 planned |

---

## Proving it on a cluster

Suggested order for the owner, cheapest and safest first. Record the date, Azure Local release and outcome in the [status](reference/status.md) table after each step.

1. Read-only: the fault preflight and the health snapshot against a healthy cluster (no change made).
2. VMFleet pipeline with the General profile, end to end, including the deploy phase (fleet VMs; supply `-FleetAdminCredential`).
3. Day-2 smoke (`Invoke-Day2Smoke.ps1`) and a comparison against the first run as the baseline.
4. fio, iPerf3 and stress-ng on a few Linux VMs; HammerDB on a Windows VM.
5. Failure injection, last: `DriveFault` with `Retire` on a non-production cluster, then `NodePause`.

## Contributing

If you want to work on a 🔲 planned item, open an issue on GitHub to claim it before starting. See [Contributing](contributing.md) for the full contribution guide.
