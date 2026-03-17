# Examples & IIC Policy

> **Canonical reference:** [Fictional Company Policy (full)](https://azurelocal.cloud/standards/fictional-company-policy)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Policy

All examples, sample configurations, walkthroughs, and documentation across every AzureLocal repository use **one** fictional company: **Infinite Improbability Corp (IIC)**.

!!! warning "Mandatory"
    Never use `contoso`, `fabrikam`, `adventure-works`, `woodgrove`, `example.com`, or any real customer name.
    **IIC only** — in every repo, every example, every sample config.

---

## IIC Reference Card

| Attribute | Value |
|-----------|-------|
| **Full Name** | Infinite Improbability Corp |
| **Abbreviation** | IIC |
| **Domain (public)** | `improbability.cloud` / `iic.cloud` |
| **Domain (on-prem AD)** | `iic.local` |
| **NetBIOS Name** | `IMPROBABLE` |
| **Entra ID Tenant** | `improbability.onmicrosoft.com` |
| **Email Pattern** | `user@improbability.cloud` |
| **Origin** | A nod to *The Hitchhiker's Guide to the Galaxy* |

---

## LoadTools Naming Patterns

### Azure Resources

| Resource | Pattern | Example |
|----------|---------|---------|
| Resource Group | `rg-iic-loadtools-<##>` | `rg-iic-loadtools-01` |
| Key Vault | `kv-iic-<purpose>` | `kv-iic-platform` |
| Storage Account | `stiic<purpose><##>` | `stiicresults01` |
| Log Analytics | `law-iic-<purpose>-<##>` | `law-iic-monitor-01` |

### Cluster & Nodes

| Resource | Pattern | Example |
|----------|---------|---------|
| Cluster | `iic-clus<NN>` | `iic-clus01` |
| Test VMs | `iic-vm<tool>-<NN>` | `iic-vmfleet-01` |

---

## Real Identities

These are **not** fictional — use for authorship and attribution:

| Name | Usage |
|------|-------|
| **Azure Local Cloud** | Community project, GitHub org, `azurelocal.cloud` |
| **Hybrid Cloud Solutions** | Author/maintainer LLC, script headers, copyright |

---

## Usage Examples

### In `config/variables.example.yml`

```yaml
azure:
  subscription_id: "00000000-0000-0000-0000-000000000000"
  resource_group: "rg-iic-loadtools-01"
  location: "eastus"

keyvault:
  name: "kv-iic-platform"

testing:
  cluster_name: "iic-clus01"
  vm_count: 64
```

### In Documentation

> Infinite Improbability Corp validates storage performance on `iic-clus01` using
> VMFleet with 64 test VMs across four Azure Local nodes.

### In Scripts

```powershell
# Example: Start VMFleet workload on IIC cluster
$clusterName = "iic-clus01"
$credential = Get-Secret -Vault "kv-iic-platform" -Name "svc-iic-deploy"
Invoke-VMFleetWorkload -ClusterName $clusterName -Credential $credential
```

---

## Enforcement

- **PR review**: Reviewers flag any use of `contoso`, `fabrikam`, or other non-IIC names
- **Config validation**: `variables.example.yml` uses IIC naming patterns in all placeholders
- **CI**: Vale linting rules can flag non-IIC fictional company names (when configured)
