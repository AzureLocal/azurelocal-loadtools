# Variable Standards

> **Canonical reference:** [Variable Management Standard](https://azurelocal.cloud/standards/variable-management/)  
> **Full variable catalog:** [Variable Reference](../reference/variables.md)  
> **Last Updated:** 2026-03-17

---

## Overview

This repository uses a **single central configuration file** — `config/variables.yml` — as the source of truth. Additional subdirectories under `config/` provide cluster-specific, credential, and profile configurations.

---

## Config Directory Structure

```
config/
├── variables.example.yml        # Template with IIC examples (committed)
├── variables.yml                # Your actual config (gitignored)
├── schema/
│   └── variables.schema.json    # JSON Schema for CI validation
├── clusters/                    # Per-cluster config overrides
├── credentials/                 # Credential templates
├── profiles/                    # Workload profiles
└── variables/                   # Additional variable files
```

---

## Naming Rules

| Rule | Standard | Example |
|------|----------|---------|
| Top-level sections | `snake_case` | `azure_local`, `storage`, `testing` |
| Keys within sections | `snake_case` | `subscription_id`, `cluster_name` |
| Pattern | `^[a-z][a-z0-9_]*$` | — |
| Max length | 50 characters | — |
| Booleans | Descriptive names | `monitoring_enabled: true` |
| Secrets | `keyvault://` URI format | `keyvault://kv-iic-platform/admin-password` |

---

## Key Vault Resolution

Secrets are never stored in plaintext:

```yaml
credentials:
  admin_password: "keyvault://kv-iic-platform/admin-password"
  service_principal_secret: "keyvault://kv-iic-platform/sp-secret"
```

---

## CI Validation

Every PR validates `config/variables.example.yml` against `config/schema/variables.schema.json` using the `validate-config.yml` workflow.

---

## Detailed Reference

For the complete variable catalog see:

- **[Variable Reference](../reference/variables.md)** — per-variable documentation for this repo
- **[Variable Management Standard](https://azurelocal.cloud/standards/variable-management/)** — org-wide governance
- **[Schema Validation](https://azurelocal.cloud/standards/variable-management/schema-validation)** — JSON Schema enforcement
- **[Usage Workflows](https://azurelocal.cloud/standards/variable-management/usage-workflows)** — how scripts read configuration
