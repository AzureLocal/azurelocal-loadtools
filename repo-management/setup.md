# Repository Setup

Documents how this repository is configured. Use this as the reference when setting up a new repo or auditing existing settings.

---

## Branch Protection

**Protected branch:** `main`

| Setting | Value |
|---------|-------|
| Require pull request before merging | Yes |
| Required approvals | 1 |
| Dismiss stale reviews on new commits | Yes |
| Require status checks to pass | Yes |
| Required checks | `check-structure` (validate-repo-structure) |
| Require branches to be up to date | Yes |
| Restrict force pushes | Yes |
| Allow admins to bypass | Yes |

---

## Labels

Labels are defined in `azurelocal.github.io/.github/labels.yml` — that is the source of truth for all repos. Labels are applied here when they change in the source repo or manually via `workflow_dispatch` on `sync-labels.yml` in `azurelocal.github.io`.

---

## Secrets

| Secret | Used By | Description |
|--------|---------|-------------|
| `ADD_TO_PROJECT_PAT` | `add-to-project.yml` | Classic PAT with `project` scope. Required for org-level project board access. |
| `CLUSTER_ADMIN_USERNAME` | `run-vmfleet.yml` | Admin username for WinRM connections to the Azure Local cluster. Injected as environment variable — never logged. |
| `CLUSTER_ADMIN_PASSWORD` | `run-vmfleet.yml` | Admin password for WinRM connections to the Azure Local cluster. Injected as environment variable, used to construct a `PSCredential` at runtime. **Never embedded in scripts.** |
| `GITHUB_TOKEN` | All other workflows | Built-in GitHub token. |

> **Security note:** `CLUSTER_ADMIN_USERNAME` and `CLUSTER_ADMIN_PASSWORD` are org-level or repo-level secrets. The `run-vmfleet.yml` workflow converts the password to a `SecureString` at runtime using `ConvertTo-SecureString -AsPlainText -Force`. This is the only supported pattern for passing runtime credentials to WinRM — the value never appears in logs due to GitHub's secret masking.

---

## Self-Hosted Runner

The `run-vmfleet.yml` workflow requires a self-hosted runner tagged `[self-hosted, azurelocal]`.

**Runner requirements:**
- Windows OS with PowerShell 7.2+
- WinRM access to the Azure Local cluster under test
- Network line-of-sight to cluster management IPs
- Modules pre-installed or installed per-run: `powershell-yaml`, `ImportExcel`
- GitHub Actions runner service registered to this repo

The runner is **not** used by any other workflow — all other jobs run on `ubuntu-latest` or `windows-latest` (GitHub-hosted).

---

## CODEOWNERS

Defined in `.github/CODEOWNERS`. Review and update if team membership changes.

---

## GitHub Pages

| Setting | Value |
|---------|-------|
| Source | GitHub Actions (uses `actions/deploy-pages`) |
| Build tool | MkDocs Material + pymdown-extensions + mkdocs-drawio |
| Deploy trigger | Push to `main` touching `docs/**` or `mkdocs.yml` |

---

## Replication Checklist

- [ ] Add `ADD_TO_PROJECT_PAT` secret (org PAT, `project` scope)
- [ ] Add `CLUSTER_ADMIN_USERNAME` and `CLUSTER_ADMIN_PASSWORD` secrets if the repo has a VMFleet-style runner workflow
- [ ] Register self-hosted runner tagged `[self-hosted, azurelocal]` if needed
- [ ] Enable branch protection on `main` per settings above
- [ ] Add `.github/CODEOWNERS`
- [ ] Add `.github/PULL_REQUEST_TEMPLATE.md`
- [ ] Copy `add-to-project.yml` — update ID prefix (`LOAD-$NUMBER`)
- [ ] Copy `release-please.yml` and `release-please-config.json`
- [ ] Copy `validate-repo-structure.yml` — adjust required dirs
- [ ] Copy `deploy-docs.yml` if repo has docs
- [ ] Enable GitHub Pages (Settings → Pages → Source: GitHub Actions)
