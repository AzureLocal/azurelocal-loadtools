# Documentation Standards

> **Canonical reference:** [Documentation Standards (full)](https://azurelocal.cloud/standards/documentation/documentation-standards)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Principles

| Principle | Rule |
|-----------|------|
| Documentation-First | Document **before** implementing. Keep docs current with code. |
| Single Source of Truth | One authoritative document per topic. Cross-reference, don't duplicate. |
| Audience-Aware | Write for operators, developers, or executives — with appropriate depth. |
| Actionable | Step-by-step procedures, examples, prerequisites, and outcomes. |

---

## File Naming

| Type | Convention | Pattern | Example |
|------|-----------|---------|---------|
| Directories | lowercase-with-hyphens | `^[a-z][a-z0-9-]*$` | `tools/`, `getting-started/` |
| Markdown (docs/) | lowercase with hyphens | `*.md` | `workload-profiles.md` |
| Root files | UPPERCASE | — | `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md` |
| PowerShell scripts | PascalCase | `Verb-Noun.ps1` | `Start-VMFleetWorkload.ps1` |
| Config files | lowercase-with-hyphens | — | `variables.example.yml` |

---

## MkDocs Material Conventions

This repo uses **MkDocs Material** with:

- **Admonitions**: `!!! note`, `!!! warning`, `!!! danger`, `!!! info`, `!!! tip`
- **Code blocks**: Always include a language identifier
- **Code copy**: Enabled via `content.code.copy`
- **Mermaid diagrams**: Supported via `pymdownx.superfences`
- **Tables**: Standard Markdown tables
- **Tabs**: `=== "Tab Name"` via `pymdownx.tabbed`

---

## Badges

Use Shields.io Markdown badges for visual metadata at the top of documentation pages:

```markdown
[![Label](https://img.shields.io/badge/Label-Value-color?style=flat-square&logo=icon)](URL)
```

| Badge | Markdown |
|-------|----------|
| Standard | `[![Standard](https://img.shields.io/badge/Type-Standard-green?style=flat-square)](./index.md)` |
| AzureLocal | `[![AzureLocal](https://img.shields.io/badge/AzureLocal-Community-0078D4?style=flat-square)](https://azurelocal.cloud)` |
| PowerShell | `[![PowerShell](https://img.shields.io/badge/Language-PowerShell-blue?style=flat-square&logo=powershell)](https://docs.microsoft.com/en-us/powershell/)` |

**Placement rules**: 2–4 badges max per page, immediately after `# Title`, order: Type → Organization → Technology → Category, always `?style=flat-square`.

---

## Fictional Company — Infinite Improbability Corp (IIC)

All examples must use IIC naming patterns:

| Never Use | Use Instead |
|-----------|-------------|
| `contoso`, `fabrikam`, `northwind` | Infinite Improbability Corp |
| `example.com`, `test.com` | `improbability.cloud` |
| Real customer names | IIC naming patterns |

---

## Related Standards

- [Naming Conventions (full reference)](https://azurelocal.cloud/standards/documentation/naming-conventions)
- [Badge Library (full reference)](https://azurelocal.cloud/standards/documentation/badge-library)
- [Naming Conventions](naming.md)
- [Scripting Standards](scripting.md)
