# Implementation Status

![Category: Reference](https://img.shields.io/badge/Category-Reference-95A5A6?style=flat-square)

This page is the **single source of truth** for what is built, what is unit-tested, and what has been proven on real hardware. The README, the [roadmap](../roadmap.md), the [tool overview](../tools/index.md) and every tool page point here. If another page disagrees with this one, this page wins and the other page is a bug.

> [!IMPORTANT]
> **Nothing in this repository has been proven on a live Azure Local cluster yet.** "Implemented" means the scripts exist and the command-construction, parsing and refusal logic pass Pester tests with mocks and fixtures. It does not mean the end-to-end run has been executed on a cluster. Treat every tool as a pre-release until the hardware column says otherwise.

## Definitions

| Column | Meaning |
|--------|---------|
| Implemented | The scripts for install, run and collect exist and are wired together. |
| Unit-tested | Pester tests cover the script structure, parameter handling, command construction and result parsing. No cluster, no network, no Azure calls. |
| Proven on hardware | Someone ran it end to end on a real Azure Local cluster and kept the evidence. **No for every tool today.** |

## Tools

| Tool | Implemented | Unit-tested | Proven on hardware | Notes |
|------|-------------|-------------|--------------------|-------|
| VMFleet (DiskSpd) | Yes: pipeline (pre-check, install, deploy, test, monitor, collect, report, cleanup), monitoring collectors, base-image preparation. Every VMFleet step runs as a one-shot scheduled task on the first node (the management host can be non-domain-joined and reaches the nodes by IP), calling `Install-Fleet`, `New-Fleet`, `Set-Fleet`, `Start-Fleet`, `Start-FleetSweep`, `Stop-Fleet` and `Remove-Fleet` of VMFleet 2.1.0.0. | Yes: the shared helper, the node scripts (against stubs with the real VMFleet 2.1.0.0 parameter lists), every step script and the whole pipeline on fakes, plus scripts, profiles, base image and the failure-injection opt-in guard | **No** | Never run on a cluster: the scheduled-task runner, the in-memory secret hand-over, the VMFleet calls and the DiskSpd result parsing are tested with mocks and stubs only. Not applied: VMFleet data disks (`-DataDiskSizeGB`, `-DataDiskCount`); a profile's mixed random/sequential ratio runs as one pattern. The base-image preparation script (Azure Local marketplace route) is also unproven; the documented route is the managed-disk export in [Deployment](../tools/vmfleet/deployment.md#base-image). |
| fio | Yes: install, start, collect, Ansible role and playbook | Yes: 62 tests | **No** | Linux VMs only. |
| iPerf3 | Yes: start, collect, Ansible role and playbook (no install script: the Ansible role installs it) | Yes: 39 tests | **No** | Plain TCP/UDP only. It does not exercise RDMA; see [Azure Local network guidance](../tools/iperf/azure-local-network-guidance.md). |
| HammerDB | Yes: install, start, collect | Yes: 43 tests (1 skipped) | **No** | |
| stress-ng | Yes: start, collect, Ansible role and playbook (no install script: the Ansible role installs it) | Yes: 36 tests | **No** | Linux VMs only. |

## Framework

| Component | Implemented | Unit-tested | Proven on hardware |
|-----------|-------------|-------------|--------------------|
| ConfigManager, Logger, StateManager, CredentialManager, MonitoringManager | Yes | Yes (Config, Logger, State; Credential and Monitoring are not covered yet) | No |
| ReportGenerator (PDF via asciidoctor-pdf, DOCX via pandoc, XLSX via ImportExcel) | Yes | Partly: 3 tests, the external tools are not exercised | No |
| ResultAnalysis: offline HTML + CSV report, baseline comparison, regression exit code, trend | Yes | Yes: 27 tests on fixtures | Not applicable (offline), but the inputs come from runs that are unproven |
| Day-2 smoke gate (`Invoke-Day2Smoke.ps1`, JSON schema) | Yes | Yes: 25 tests (schema, exit codes, fixtures) | **No** |
| FaultInjection (node pause, drive fault, guarded, opt-in) | Yes | Yes: 43 mocked tests | **No** (see [failure injection](../tools/vmfleet/failure-injection.md)) |
| CI (GitHub Actions and Azure DevOps): analyzer, Pester per suite, link check | Yes | Not applicable | Not applicable |

## Known documentation gaps

- No script has a `-CredentialSource` parameter, and the tool pages no longer show one. The scripts take a `-Credential` (PSCredential) or a secret parameter such as `-WorkspaceKey`, then fall back to the environment variables and the Key Vault mapping (see [Credential Management](../operations/credential-management.md)). For any other command example, the script `param` blocks are the reference.
- The `monitoring/` and `reports/` folders are per tool (`tools/<tool>/monitoring`, `tools/<tool>/reports/templates`), not at the repository root.

## What would change a "No" to a "Yes"

An owner runs the tool on a non-production cluster, keeps the output, and records the date, Azure Local release and result here. The suggested order is in the [roadmap](../roadmap.md#proving-it-on-a-cluster).
