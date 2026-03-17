# Solution Development Standards

> **Canonical reference:** [Solution Development Standard (full)](https://azurelocal.cloud/standards/solutions/solution-development-standard)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Overview

Standards for solution packaging, multi-tool automation parity, and deployment best practices for the Load Testing Framework.

---

## Solution Structure

| Directory | Purpose |
|-----------|---------|
| `config/` | Configuration files — variables, schemas, profiles |
| `docs/` | Documentation source (MkDocs) |
| `src/` | Source modules and libraries |
| `scripts/` | Automation scripts |
| `tests/` | Pester tests |
| `reports/` | Performance test results and baselines |
| `monitoring/` | Monitoring dashboards and alerts |

---

## Parameter File Derivation

All tool-specific parameter files MUST be derivable from `config/variables.yml`:

| Tool | Parameter Source | Derivation |
|------|-----------------|-----------|
| PowerShell | `config/variables.yml` | `ConvertFrom-Yaml` direct read |
| Profiles | `config/profiles/*.yml` | Workload-specific overrides |
| Clusters | `config/clusters/*.yml` | Per-cluster configuration |

The central config is the **single source of truth**.

---

## Idempotency

All scripts must be safe to re-run without side effects:

- Check for existing resources before creating
- Use `-WhatIf` for dry-run validation
- Log all operations for audit trail

---

## Related Standards

- [Scripting Standards](scripting.md)
- [Variable Standards](variables.md)
- [Infrastructure Standards](infrastructure.md)
- [Automation Interoperability](automation.md)
