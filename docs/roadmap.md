# Roadmap

![Category: Project](https://img.shields.io/badge/Category-Project-95A5A6?style=flat-square)

This page tracks the feature roadmap for the Azure Local Load Testing Framework using milestone-based groupings. Items link to GitHub Issues where available.

---

## Milestone 1 — Core Tool Implementation ✅

Initial implementation of all five load-testing tools with PowerShell orchestration, test execution, and basic result collection.

| Item | Status |
|------|--------|
| fio storage benchmarking (Linux VMs) | ✅ Complete |
| iPerf3 network throughput (TCP + UDP + mesh) | ✅ Complete |
| HammerDB DB benchmarking (SQL Server TPC-C, PostgreSQL TPC-H) | ✅ Complete |
| stress-ng OS-level stress (CPU, memory, I/O) | ✅ Complete |
| VMFleet VM fleet workload simulation | ✅ Complete |
| ConfigManager module (master YAML → solution JSON) | ✅ Complete |
| Logger module (structured JSON-lines + correlation IDs) | ✅ Complete |
| StateManager module (checkpoint-based resume) | ✅ Complete |
| CredentialManager module (Key Vault + interactive + param) | ✅ Complete |
| MonitoringManager module (PerfMon collection + alert rules) | ✅ Complete |

---

## Milestone 2 — Documentation Overhaul ✅

Full documentation redesign covering all tools, architecture, and operations.

| Item | Status |
|------|--------|
| Fix placeholder badges and stale status indicators | ✅ Complete |
| Add installation, workload-profiles, monitoring, reporting, troubleshooting pages for all 4 tools | ✅ Complete |
| Promote architecture to top-level section (overview, tool-selection, data-flow) | ✅ Complete |
| Add runner-setup guide for self-hosted CI/CD runners | ✅ Complete |
| Add cross-tool operations troubleshooting guide | ✅ Complete |
| Add tool comparison matrix to reference section | ✅ Complete |
| Rewrite index.md with Quick Start and enhanced tool table | ✅ Complete |
| Update mkdocs.yml navigation to reflect all new sections | ✅ Complete |

---

## Milestone 3 — Reporting Enhancements 🔲

Improve report quality, add trend analysis, and integrate with Azure Monitor workbooks.

| Item | Status |
|------|--------|
| PDF report templates for all 5 tools (AsciiDoc → asciidoctor-pdf) | 🔲 Planned |
| XLSX export with raw metrics per node | 🔲 Planned |
| Trend comparison: compare two RunIds and highlight regressions | 🔲 Planned |
| Azure Monitor workbook integration for live dashboards | 🔲 Planned |
| Grafana dashboard JSON export for all tools | 🔲 Planned |

---

## Milestone 4 — CI/CD Maturity 🔲

Harden the CI/CD pipeline and add automated regression detection.

| Item | Status |
|------|--------|
| Automated threshold regression gate in GitHub Actions | 🔲 Planned |
| Pester test coverage for all PowerShell modules (>80%) | 🔲 Planned |
| Azure DevOps pipeline parity with GitHub Actions | 🔲 Planned |
| GitLab CI pipeline parity with GitHub Actions | 🔲 Planned |
| Container-based runner image (pre-installed modules) | 🔲 Planned |
| Signed commits enforcement + branch protection | 🔲 Planned |

---

## Milestone 5 — Extended Tool Support 🔲

Add support for additional workloads and cluster scenarios.

| Item | Status |
|------|--------|
| DiskSpd Windows storage benchmarking (equivalent to fio for Windows targets) | 🔲 Planned |
| RDMA-specific network tests (RPING, perftest) | 🔲 Planned |
| PostgreSQL TPC-C profile in HammerDB | 🔲 Planned |
| fio RDMA I/O engine support | 🔲 Planned |
| Kubernetes workload profile (K8s on AKS Arc) | 🔲 Planned |

---

## Contributing

If you want to work on a 🔲 Planned item, open an issue on GitHub to claim it before starting. See [Contributing](contributing.md) for the full contribution guide.
