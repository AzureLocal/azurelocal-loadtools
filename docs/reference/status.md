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
| VMFleet (DiskSpd) | Yes: pipeline (pre-check, install, deploy, test, monitor, collect, report, cleanup), monitoring collectors, base-image preparation | Yes: 143 tests (scripts, profiles, base image, failure-injection opt-in guard) | **No** | The deploy phase passes VM count, base VHD and CSV to the fleet cmdlet; the per-VM memory, vCPU and data-disk values are resolved and logged only. Verify the sizing options of your VMFleet version on the cluster. |
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

- Several tool pages show a `-CredentialSource` parameter that the scripts do not implement. The scripts take a `-Credential` (PSCredential) and fall back to the credential manager. Use the script `param` blocks as the reference until the pages are rewritten.
- The `monitoring/` and `reports/` folders are per tool (`tools/<tool>/monitoring`, `tools/<tool>/reports/templates`), not at the repository root.

## What would change a "No" to a "Yes"

An owner runs the tool on a non-production cluster, keeps the output, and records the date, Azure Local release and result here. The suggested order is in the [roadmap](../roadmap.md#proving-it-on-a-cluster).
