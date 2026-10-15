# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). From the first release on, release-please maintains this file from Conventional Commit messages.

## [Unreleased]

Target: 0.1.0, the first tagged pre-release. Nothing in this repository has been proven on a live Azure Local cluster; see `docs/reference/status.md`.

### Features

- Opt-in failure injection for VMFleet runs (`FaultInjection` module, `Invoke-VMFleetFault.ps1`, `Undo-VMFleetFault.ps1`, `failure-injection.yml` profile): node pause or one drive out, `-AllowFault` plus confirmation, undo printed first, refuses when the cluster is unhealthy, one fault at a time. Mocked tests only.
- `ResultAnalysis` module: offline HTML and CSV report, baseline comparison with a regression exit code (0 / 1 / 2, fails closed), trend over several runs. `Compare-VMFleetResults.ps1`, `New-VMFleetReport.ps1`.
- Day-2 smoke: `day2-smoke.yml` profile, `Invoke-Day2Smoke.ps1` (exit 0 / 1 / 2 / 3), a JSON result and its schema in `docs/reference`, fixtures validated against it.
- CI: `ci.yml` (PSScriptAnalyzer with a warning budget, Pester one process per suite, link check; actions pinned to SHAs), `release-please.yml`, Dependabot, issue and pull request templates, Azure DevOps validate pipeline with parity.
- Documentation: single implementation-status truth table; CSV in-memory read cache caveat and Well-Architected failure-condition guidance for VMFleet and DiskSpd; Azure Local network guidance for iPerf3 (it does not exercise RDMA).

### Bug Fixes

- `ConfigManager`: a cached configuration no longer hides a bad path (`Import-MasterConfig` now validates the path first and caches per path); the default path is `config/variables/variables.yml`, the file that exists.
- All modules resolved `ProjectRoot` four levels up, outside the repository; it is now the repository root.
- `Deploy-VMFleet.ps1` no longer creates fleet VMs with a hard-coded placeholder password; a `-FleetAdminCredential` is required (also on `Invoke-VMFleetPipeline.ps1`).
- Seven failing Pester tests fixed (StateManager `$using:` in test code, base-image regex, ConfigManager mock scope).

### Miscellaneous

- PSScriptAnalyzer warnings reduced from 545 to 0 by formatting, fixing unused variables and the automatic-variable assignment, and documented rule exclusions in `.psscriptanalyzer.psd1`.
- Module manifests are version 0.1.0; empty `.gitkeep` placeholders removed; the README, roadmap, tool pages and the automation and CI/CD pages no longer claim workflows, scripts or completeness that do not exist.

### VMFleet (earlier, unreleased)

- Add `Prepare-VMFleetBaseImage.ps1` — automates WS2022 Core Gen2 base image download from Azure Local marketplace
- Add `sequential-throughput.yml` workload profile — 512K sequential writes for MB/s ceiling measurement
- Add Azure Monitor workbook (`vmfleet-workbook.json`) with IOPS, latency P95, and throughput panels
- Add KQL queries for Log Analytics (`vmfleet-iops.kql`, `vmfleet-latency.kql`)
- Add `custom_location_id` and `storage_path_id` fields to config schema and example
- Add Pester tests for VMFleet script standards compliance and base image script
- Expand VMFleet documentation: prerequisites, deployment, workload profiles, monitoring, reporting, troubleshooting

### Initial scope (earlier, unreleased)

- VMFleet, fio, iPerf3, HammerDB, and stress-ng load testing scripts
- Modular PowerShell framework (ConfigManager, Logger, StateManager, CredentialManager, MonitoringManager, ReportGenerator)
- Monitoring collectors, dashboards, and alert rules
- Report templates for performance analysis
- Add CONTRIBUTING.md
