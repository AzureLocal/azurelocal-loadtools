# Automation

Documents every GitHub Actions workflow in this repository.

---

## Workflow Summary

| File | Name | Trigger | Purpose |
|------|------|---------|---------|
| `add-to-project.yml` | Add to Project | Issues/PRs opened or labeled | Adds items to org project board and sets custom fields |
| `deploy-docs.yml` | Deploy MkDocs to GitHub Pages | Push to `main` touching `docs/**` or `mkdocs.yml` | Builds MkDocs site and deploys to GitHub Pages |
| `lint.yml` | Lint PowerShell | Push/PR touching PowerShell files | PSScriptAnalyzer via `tests/PSScriptAnalyzer.ps1` wrapper |
| `release-please.yml` | Release Please | Push to `main` | Automates CHANGELOG and releases |
| `run-tests.yml` | Run Tests | Push/PR touching `common/**`, `tools/**`, `tests/**` | Pester 5 unit tests with code coverage |
| `run-vmfleet.yml` | Run VMFleet Load Test | Manual (`workflow_dispatch`) | Executes full VMFleet pipeline on self-hosted runner |
| `validate-config.yml` | Validate Configuration | Push/PR touching `config/**` | Validates config YAML against JSON Schema |
| `validate-repo-structure.yml` | Validate Repo Structure | PR to `main` | Checks required files and directories are present |

---

## add-to-project.yml

**Trigger:** `issues` (opened, labeled) and `pull_request` (opened, labeled)  
**Secrets:** `ADD_TO_PROJECT_PAT`

Two-job pipeline:

1. **add-to-project** — Uses `actions/add-to-project@v1.0.2` to add the item to org project board (`AzureLocal/projects/3`). Outputs the item ID.
2. **set-fields** (issues only) — Uses `gh project item-edit` to set:
   - **ID field** — text value `LOAD-{issue_number}`
   - **Solution field** — maps `solution/*` label to a single-select project option
   - **Priority field** — maps `priority/*` label
   - **Category field** — maps `type/*` label

---

## deploy-docs.yml

**Trigger:** Push to `main` touching `docs/**` or `mkdocs.yml`; manual via `workflow_dispatch`  
**Permissions:** `contents: read`, `pages: write`, `id-token: write`  
**Concurrency group:** `pages` (cancel-in-progress: false)

Two-job pipeline:

**build:**
1. Sets up Python 3.12
2. Installs `mkdocs-material`, `pymdown-extensions`, `mkdocs-drawio`
3. `mkdocs build --strict`
4. Uploads `site/` as a pages artifact

**deploy:**
1. Uses `actions/deploy-pages@v4` to publish to GitHub Pages

---

## lint.yml

**Trigger:** Push to `main` or PR touching `common/**/*.ps1`, `common/**/*.psm1`, `tools/**/*.ps1`, `tests/**/*.ps1`; manual via `workflow_dispatch`  
**Runner:** `windows-latest`

1. Installs PSScriptAnalyzer
2. Runs `tests/PSScriptAnalyzer.ps1 -ProjectRoot <workspace>` — the wrapper script handles settings and exclusions

**Notes:** Uses a wrapper script rather than calling `Invoke-ScriptAnalyzer` directly — see `tests/PSScriptAnalyzer.ps1` for the full rule configuration.

---

## release-please.yml

**Trigger:** Push to `main`  
**Permissions:** `contents: write`, `pull-requests: write`

Uses `googleapis/release-please-action@v4`. Maintains an automated release PR that updates `CHANGELOG.md` and bumps version. Merging it creates the GitHub release and tag.

---

## run-tests.yml

**Trigger:** Push to `main` or PR touching `common/**`, `tools/**`, `tests/**`; manual via `workflow_dispatch`  
**Runner:** `windows-latest`

1. Installs Pester 5, `powershell-yaml`, `ImportExcel`
2. Runs Pester with:
   - Paths: `tests/` and `tools/`
   - Test results: `test-results.xml` (NUnit format) — uploaded as artifact
   - Code coverage: `coverage.xml` (JaCoCo format) over `common/modules/` — uploaded as artifact
   - `Run.Exit = $true` — fails the workflow on any test failure

---

## run-vmfleet.yml

**Trigger:** Manual only (`workflow_dispatch`)  
**Runner:** `[self-hosted, azurelocal]`  
**Secrets:** `CLUSTER_ADMIN_USERNAME`, `CLUSTER_ADMIN_PASSWORD`  
**Timeout:** 120 minutes

This workflow executes the full VMFleet load test pipeline against a live Azure Local cluster.

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `cluster_config` | Yes | `example-cluster.yml` | Config file path relative to `config/clusters/` |
| `profile` | No | `general.yml` | Workload profile relative to `tools/vmfleet/config/profiles/` |
| `report_formats` | No | `PDF,XLSX` | Comma-separated report formats (PDF, DOCX, XLSX) |
| `skip_cleanup` | No | false | Skip VM cleanup after test |
| `push_to_azure_monitor` | No | false | Push metrics to Azure Monitor |

**What it does:**

1. Validates PowerShell 7.2+ on the runner
2. Installs `powershell-yaml` and `ImportExcel` modules if not already present
3. Runs `common/helpers/Initialize-Environment.ps1` with the cluster config
4. Constructs a `PSCredential` from `CLUSTER_ADMIN_USERNAME` and `CLUSTER_ADMIN_PASSWORD` secrets
5. Calls `tools/vmfleet/Invoke-VMFleetPipeline.ps1` with all parameters
6. Uploads reports to `reports/` as artifact (90-day retention)
7. Uploads logs from `logs/` as artifact (30-day retention)

**Runner requirements:** Windows, PowerShell 7.2+, WinRM access to the cluster. See [setup.md](setup.md) for full runner configuration.

---

## validate-config.yml

**Trigger:** Push to `main` or PR touching `config/**`; manual via `workflow_dispatch`

1. Sets up Python 3.12
2. Installs `pyyaml`, `jsonschema`
3. Loads `config/variables.example.yml` and `config/schema/variables.schema.json`
4. Validates example config against schema — fails on any schema violation

---

## validate-repo-structure.yml

**Trigger:** PR to `main`

| Check | Required Items |
|-------|---------------|
| Root files | `README.md`, `CONTRIBUTING.md`, `LICENSE`, `CHANGELOG.md`, `.gitignore` |
| Directories | `docs/`, `.github/` |
| PR template | `.github/PULL_REQUEST_TEMPLATE.md` |
| Config structure (if `config/` exists) | `config/variables.example.yml`, `config/schema/variables.schema.json` |
