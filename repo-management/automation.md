# Automation

Documents the GitHub Actions workflows that exist in this repository. Earlier versions of this page also described workflows that were never built; they are listed at the end as not built.

---

## Workflow Summary

| File | Name | Trigger | Purpose |
|------|------|---------|---------|
| `ci.yml` | ci | Pull request, push to `main`, manual | PSScriptAnalyzer (errors fail, more than 50 warnings fail), Pester with one process per suite, relative Markdown link check. Runs `tests/Invoke-CiChecks.ps1`. |
| `release-please.yml` | Release Please | Push to `main` | Maintains the release pull request (version bump and CHANGELOG) |
| `deploy-docs.yml` | Deploy VitePress to GitHub Pages | Push to `main` touching `docs/**` | Builds the VitePress site and deploys it to GitHub Pages |

Also in the repository: `.github/dependabot.yml` (weekly GitHub Actions updates), issue templates and a pull request template.

---

## ci.yml

**Trigger:** `pull_request`, `push` to `main`, `workflow_dispatch`
**Permissions:** `contents: read`
**Secrets:** none. Nothing here needs a cluster or a tenant.

Runs on `windows-latest` (the tests use Windows path separators). Actions are pinned to full commit SHAs. Installs Pester 5.9.1, PSScriptAnalyzer 1.25.0 and powershell-yaml 0.4.12, then runs `tests/Invoke-CiChecks.ps1` once per check (Analyzer, Pester, Links) and uploads the JSON results. Run the same checks locally with `pwsh -File tests/Invoke-CiChecks.ps1 -Check All`.

---

## deploy-docs.yml

**Trigger:** Push to `main` touching `docs/**`; manual via `workflow_dispatch`
**Permissions:** `contents: read`, `pages: write`, `id-token: write`
**Concurrency group:** `pages` (cancel-in-progress: false)

One job: checks out, sets up Node.js 20, installs the VitePress dependencies in `docs/` (`npm ci`, falling back to `npm install`), runs `npm run docs:build`, uploads `docs/.vitepress/dist` as the pages artifact and deploys it with `actions/deploy-pages`. The actions in this workflow use major-version tags, not commit SHAs (unlike `ci.yml`); Dependabot proposes the bumps.

---

## release-please.yml

**Trigger:** Push to `main`  
**Permissions:** `contents: write`, `pull-requests: write`

Uses `googleapis/release-please-action@v4`. Maintains an automated release PR that updates `CHANGELOG.md` and bumps version. Merging it creates the GitHub release and tag.

---

## Not built

These were described earlier and do not exist in `.github/workflows/`: `add-to-project.yml`, `lint.yml` (replaced by `ci.yml`), `run-tests.yml` (replaced by `ci.yml`), `run-vmfleet.yml`, `validate-config.yml`, `validate-repo-structure.yml`. The `.azuredevops/azure-pipelines-vmfleet.yml` pipeline is the closest thing to a load-test pipeline and needs a self-hosted agent with cluster access.
