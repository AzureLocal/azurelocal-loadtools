# CI/CD Pipelines

![Category: Operations](https://img.shields.io/badge/Category-Operations-9B59B6?style=flat-square)

The framework includes pipeline definitions for GitHub Actions (primary), Azure DevOps, and GitLab CI.

## GitHub Actions (Primary)

### Documentation Build (`build-docs.yml`)

Triggers on push to `main` and pull requests. Builds HTML and PDF documentation, exports draw.io diagrams, and publishes artifacts.

### Configuration Validation (`validate-config.yml`)

Triggers on changes to `config/`. Validates `master-environment.yml` against the JSON Schema and verifies solution config generation.

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

### Linting (`lint.yml`)

Runs PSScriptAnalyzer for PowerShell, yamllint for YAML, and AsciiDoc syntax checks.

## Azure DevOps (Placeholder)

Pipeline definitions in `.azuredevops/pipelines/` mirror the GitHub Actions workflows, adapted for Azure DevOps syntax. Use Azure DevOps Service Connections for credential management.

## GitLab CI (Placeholder)

Pipeline definition in `.gitlab/.gitlab-ci.yml` provides the same workflow stages, adapted for GitLab CI syntax.

## Manual Execution

Every pipeline action can also be run manually from a workstation:

```powershell
# Build documentation
asciidoctor-pdf docs/main.adoc -o output/azurelocal-loadtools.pdf

# Validate configuration
.\src\core\powershell\helpers\Initialize-Environment.ps1 -ValidateOnly

# Run VMFleet pipeline
.\src\solutions\vmfleet\orchestrator\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -Profiles @("General", "Peak") `
    -CredentialSource Interactive

# Run unit tests
Invoke-Pester tests/unit/ -Output Detailed
```

## Self-Hosted Runner Setup

The VMFleet pipeline requires a self-hosted runner on the cluster management network:

1. Install GitHub Actions runner on a Windows management station
2. Register with the repository as a self-hosted runner
3. Tag with labels: `self-hosted`, `windows`, `hci-management`
4. Ensure PowerShell 7.2+ and required modules are installed
5. Configure WinRM access to cluster nodes

See [GitHub Actions self-hosted runners documentation](https://docs.github.com/en/actions/hosting-your-own-runners) for setup instructions.
