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

## GitHub Actions (Primary)

If you choose to automate, the following workflows are available:

### VMFleet Pipeline (`run-vmfleet.yml`)

Manual trigger (`workflow_dispatch`) with configurable inputs:

- Cluster configuration file path
- Workload profiles to execute
- Credential source (Key Vault or GitHub Secrets)
- Whether to generate reports
- Whether to cleanup after completion

Requires a self-hosted runner with network access to the Azure Local cluster.

### Unit Tests (`run-tests.yml`)

Runs Pester unit tests for all core PowerShell modules on every pull request.

### Configuration Validation (`validate-config.yml`)

Triggers on changes to `config/`. Validates `variables.yml` against the JSON Schema and verifies solution config generation.

### Documentation Build (`deploy-docs.yml`)

Triggers on push to `main` and pull requests. Builds MkDocs HTML documentation and publishes to GitHub Pages.

### Linting (`lint.yml`)

Runs PSScriptAnalyzer for PowerShell, yamllint for YAML files.

## Azure DevOps

Pipeline definitions in `.azuredevops/` mirror the GitHub Actions workflows, adapted for Azure DevOps syntax. Use Azure DevOps Service Connections for credential management.

## GitLab CI

Pipeline definition in `.gitlab/.gitlab-ci.yml` provides the same workflow stages, adapted for GitLab CI syntax.

---

## Self-Hosted Runner Requirements

The VMFleet and tool-specific pipelines require a self-hosted runner on the cluster management network:

1. Install GitHub Actions runner on a Windows management station
2. Register with the repository as a self-hosted runner
3. Tag with labels: `self-hosted`, `windows`, `hci-management`
4. Ensure PowerShell 7.2+ and required modules are installed
5. Configure WinRM access to cluster nodes

See [Runner Setup](runner-setup.md) for detailed instructions.
