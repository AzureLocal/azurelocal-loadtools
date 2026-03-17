# Naming Conventions

> **Canonical reference:** [Naming Conventions (full)](https://azurelocal.cloud/standards/documentation/naming-conventions)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## File & Directory Naming

| Type | Convention | Pattern | Example |
|------|-----------|---------|---------|
| Directories | lowercase-with-hyphens | `^[a-z][a-z0-9-]*$` | `tools/`, `getting-started/` |
| Markdown (docs/) | lowercase with hyphens | `*.md` | `workload-profiles.md` |
| Root files | UPPERCASE | — | `README.md`, `CHANGELOG.md` |
| PowerShell scripts | PascalCase | `Verb-Noun.ps1` | `Start-VMFleetWorkload.ps1` |
| Config files | lowercase-with-hyphens | — | `variables.example.yml` |

---

## Azure Resource Naming

All resources follow the [IIC naming patterns](examples.md):

| Resource Type | Pattern | Example |
|--------------|---------|---------|
| Resource Group | `rg-iic-loadtools-<##>` | `rg-iic-loadtools-01` |
| Key Vault | `kv-iic-<purpose>` | `kv-iic-platform` |
| Storage Account | `stiic<purpose><##>` | `stiicresults01` |
| Log Analytics | `law-iic-<purpose>-<##>` | `law-iic-monitor-01` |

---

## Variable Naming

| Rule | Standard | Example |
|------|----------|---------|
| YAML sections | `snake_case` | `azure_local`, `testing` |
| YAML keys | `snake_case` | `subscription_id`, `cluster_name` |
| Pattern | `^[a-z][a-z0-9_]*$` | — |
| Max length | 50 characters | — |

---

## Git Branch Naming

| Pattern | Usage | Example |
|---------|-------|---------|
| `main` | Default branch | — |
| `feature/<description>` | New features | `feature/hammerdb-support` |
| `fix/<description>` | Bug fixes | `fix/vmfleet-timeout` |
| `docs/<description>` | Documentation | `docs/workload-profiles` |
| `infra/<description>` | CI/CD | `infra/add-pester-tests` |

---

## Related Standards

- [Full Naming Conventions](https://azurelocal.cloud/standards/documentation/naming-conventions)
- [Repository Structure](https://azurelocal.cloud/standards/repo-structure)
- [Documentation Standards](documentation.md)
- [Examples & IIC](examples.md)
