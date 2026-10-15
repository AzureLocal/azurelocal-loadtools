# CI/CD Pipelines (Optional Automation)

![Category: Operations](https://img.shields.io/badge/Category-Operations-9B59B6?style=flat-square)

> [!NOTE]
> **Pipelines are optional**
> Every test in this framework can be run standalone from a PowerShell terminal. CI/CD pipelines are an **optional addition** for teams that want to automate, schedule, or integrate load testing into their deployment workflows.
>
The framework includes pipeline definitions for GitHub Actions (primary), Azure DevOps, and GitLab CI. These pipelines call the **same scripts** you would run manually — they are not a separate system.

## When to Use CI/CD

| Use Case | Standalone | CI/CD |
|----------|-----------|-------|
| One-off test run from your workstation | :white_check_mark: | |
| Scheduled nightly performance regression | | :white_check_mark: |
| Triggered by infrastructure changes (PR) | | :white_check_mark: |
| Automated reporting after every test | | :white_check_mark: |
| Learning or debugging the framework | :white_check_mark: | |
| Production validation before go-live | :white_check_mark: | :white_check_mark: |

## Running Tests Without CI/CD

Every pipeline action can be run manually from a PowerShell terminal. See each tool's page for exact commands:

- [VMFleet — Run This Test](../tools/vmfleet/index.md#run-this-test)
- [fio — Run This Test](../tools/fio/index.md#run-this-test)
- [iPerf3 — Run This Test](../tools/iperf/index.md#run-this-test)
- [HammerDB — Run This Test](../tools/hammerdb/index.md#run-this-test)
- [stress-ng — Run This Test](../tools/stress-ng/index.md#run-this-test)

Or use the common utility scripts directly:

```powershell
# Validate your configuration
.\common\helpers\Initialize-Environment.ps1 -ValidateOnly

# Run Pester unit tests
Invoke-Pester tests/ -Output Detailed
```

---

## What exists today

| Pipeline | File | What it does | Needs a cluster |
|----------|------|--------------|-----------------|
| GitHub Actions: `ci` | `.github/workflows/ci.yml` | On every pull request and push to `main`: PSScriptAnalyzer (errors fail, more than 50 warnings fail), Pester with one process per suite, relative Markdown link check. Actions are pinned to commit SHAs. | No |
| GitHub Actions: `Release Please` | `.github/workflows/release-please.yml` | Opens the release pull request (version bump and CHANGELOG) from Conventional Commit messages. Merging it creates the tag and the GitHub release. | No |
| GitHub Actions: docs | `.github/workflows/deploy-docs.yml` | Builds the VitePress site and publishes it to GitHub Pages on changes under `docs/`. | No |
| Azure DevOps: validate | `.azuredevops/azure-pipelines.yml` | Runs the same `tests/Invoke-CiChecks.ps1` as GitHub Actions | No |
| Azure DevOps: VMFleet run | `.azuredevops/azure-pipelines-vmfleet.yml` | Runs the VMFleet pipeline. Needs a self-hosted agent with cluster access. | Yes |
| Root `azure-pipelines.yml` | `azure-pipelines.yml` | Trigger that extends the central Platform Engineering module template | No |

There are no GitHub Actions workflows that run a load test, and no GitLab CI pipeline. Both appeared in earlier versions of this page and were never built; they remain on the [roadmap](../roadmap.md).

### Run the same checks locally

```powershell
pwsh -File tests/Invoke-CiChecks.ps1 -Check All          # analyzer, Pester per suite, links
pwsh -File tests/Invoke-CiChecks.ps1 -Check Analyzer -MaxWarnings 50
```

The analyzer settings are in `.psscriptanalyzer.psd1`; every excluded rule is listed there with its reason.

### Gating a readiness check

A pipeline or readiness script can call [`Invoke-Day2Smoke.ps1`](../reference/day2-smoke.md) or [`Compare-VMFleetResults.ps1`](../tools/vmfleet/regression-gate.md). Both exit non-zero when the check did not pass, and write a JSON result. This is not wired into any workflow here because it needs a cluster.

## Self-Hosted Runner Requirements

The VMFleet and tool-specific pipelines require a self-hosted runner on the cluster management network:

1. Install GitHub Actions runner on a Windows management station
2. Register with the repository as a self-hosted runner
3. Tag with labels: `self-hosted`, `windows`, `hci-management`
4. Ensure PowerShell 7.2+ and required modules are installed
5. Configure WinRM access to cluster nodes

See [Runner Setup](runner-setup.md) for detailed instructions.
