# Variable Reference

All load testing tools read from a single central configuration file: `config/variables.yml`. This file is the **single source of truth** — cluster details, credentials, testing defaults, and monitoring settings are all declared here and consumed by every automation tool.

> [!TIP]
> **Getting started**
> Copy the example and fill in your values:
> ```powershell
> cp config/variables.example.yml config/variables.yml
> ```
> **Never commit** `variables.yml` — it is excluded by `.gitignore` because it contains environment-specific values and Key Vault references.
>
!!! info "Additional configs"
    Detailed configs live in subdirectories under `config/`:

    - `config/clusters/` — Per-cluster connection details
    - `config/credentials/` — Key Vault credential mappings
    - `config/profiles/` — Workload profiles (vmfleet, fio, iperf, etc.)
    - `config/variables/` — Master variable registry and solution schemas

---

## Naming Rules

| Scope | Convention | Example |
|-------|-----------|---------|
| Top-level sections | `snake_case` | `azure_local`, `credentials` |
| Keys within sections | `snake_case` | `subscription_id`, `default_tool` |
| Booleans | Descriptive name | `enable_real_time: true` |
| Secrets | `keyvault://` URI | `keyvault://kv-name/secret-name` |

---

## Azure

```yaml
azure:
  subscription_id: "00000000-0000-0000-0000-000000000000"
  tenant_id: "00000000-0000-0000-0000-000000000000"
  resource_group: "rg-loadtools-eus-01"
  location: "eastus"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `azure.subscription_id` | string | **Yes** | Azure subscription ID | — |
| `azure.tenant_id` | string | **Yes** | Azure AD tenant ID | — |
| `azure.resource_group` | string | **Yes** | Resource group for load testing resources | — |
| `azure.location` | string | **Yes** | Azure region | `eastus` |

---

## Key Vault

```yaml
keyvault:
  name: "kv-iic-loadtools"
  auth_method: "az_cli"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `keyvault.name` | string | **Yes** | Key Vault name for all `keyvault://` URI resolution | — |
| `keyvault.auth_method` | string | No | Auth method: `managed_identity`, `service_principal`, or `az_cli` | `az_cli` |

---

## Azure Local Cluster

```yaml
azure_local:
  cluster_name: "azl-cluster-01"
  cluster_domain: "contoso.local"
  nodes:
    - name: "azl-node-01"
      management_ip: "10.0.0.1"
      storage_ip: "10.0.1.1"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `azure_local.cluster_name` | string | **Yes** | Azure Local cluster name | — |
| `azure_local.cluster_domain` | string | **Yes** | Active Directory domain for the cluster | — |
| `azure_local.nodes` | list | **Yes** | Cluster nodes with name, management_ip, and storage_ip | — |

---

## Storage

```yaml
storage:
  csv_path: "C:\\ClusterStorage\\Volume1"
  collect_volume_path: "C:\\ClusterStorage\\Collect"
  base_vhd_path: "C:\\ClusterStorage\\Collect\\BaseImage.vhdx"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `storage.csv_path` | string | **Yes** | Cluster Shared Volume path for VM storage | — |
| `storage.collect_volume_path` | string | No | VMFleet Collect volume path (ReFS, 200 GB+) | — |
| `storage.base_vhd_path` | string | No | Windows Server Core base VHDX path | — |

---

## Networking

```yaml
networking:
  management:
    subnet: "10.0.0.0/24"
    vlan_id: 0
  storage:
    subnet: "10.0.1.0/24"
    vlan_id: 100
    rdma_enabled: true
  compute:
    subnet: "10.0.2.0/24"
    vlan_id: 200
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `networking.management.subnet` | string | No | Management network CIDR | — |
| `networking.management.vlan_id` | integer | No | Management VLAN ID | `0` |
| `networking.storage.subnet` | string | No | Storage network CIDR | — |
| `networking.storage.vlan_id` | integer | No | Storage VLAN ID | — |
| `networking.storage.rdma_enabled` | boolean | No | Whether RDMA is enabled on storage NICs | `true` |
| `networking.compute.subnet` | string | No | Compute network CIDR | — |
| `networking.compute.vlan_id` | integer | No | Compute VLAN ID | — |

---

## Credentials

```yaml
credentials:
  cluster_admin_username: "keyvault://kv-iic-loadtools/hci-cluster-admin-user"
  cluster_admin_password: "keyvault://kv-iic-loadtools/hci-cluster-admin-pwd"
  vmfleet_admin_username: "keyvault://kv-iic-loadtools/vmfleet-admin-user"
  vmfleet_admin_password: "keyvault://kv-iic-loadtools/vmfleet-admin-pwd"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `credentials.cluster_admin_username` | string | **Yes** | Key Vault URI — cluster admin username | — |
| `credentials.cluster_admin_password` | string | **Yes** | Key Vault URI — cluster admin password | — |
| `credentials.vmfleet_admin_username` | string | No | Key Vault URI — VMFleet VM admin username | — |
| `credentials.vmfleet_admin_password` | string | No | Key Vault URI — VMFleet VM admin password | — |

---

## Testing Defaults

```yaml
testing:
  default_tool: "vmfleet"
  default_profile: "general"
  duration_seconds: 300
  warmup_seconds: 60
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `testing.default_tool` | string | **Yes** | Default tool: `vmfleet`, `fio`, `iperf`, `hammerdb`, `stress-ng` | `vmfleet` |
| `testing.default_profile` | string | No | Profile name from `config/profiles/<tool>/` | `general` |
| `testing.duration_seconds` | integer | No | Duration of each test pass in seconds | `300` |
| `testing.warmup_seconds` | integer | No | Warmup period before measurement | `60` |

---

## Monitoring & Reporting

```yaml
monitoring:
  log_analytics_workspace_id: "00000000-0000-0000-0000-000000000000"
  log_analytics_shared_key: "keyvault://kv-iic-loadtools/log-analytics-key"
  enable_real_time: true
  collection_interval_seconds: 10

reporting:
  output_dir: "reports"
  format: "html"
  include_charts: true
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `monitoring.log_analytics_workspace_id` | string | No | Log Analytics workspace ID | — |
| `monitoring.log_analytics_shared_key` | string | No | Key Vault URI — Log Analytics shared key | — |
| `monitoring.enable_real_time` | boolean | No | Enable real-time metric collection | `true` |
| `monitoring.collection_interval_seconds` | integer | No | Metric sampling interval | `10` |
| `reporting.output_dir` | string | No | Report output directory | `reports` |
| `reporting.format` | string | No | Output format: `html`, `json`, `csv` | `html` |
| `reporting.include_charts` | boolean | No | Include charts in reports | `true` |

---

## WinRM

```yaml
winrm:
  port: 5985
  use_ssl: false
  authentication: "Kerberos"
  operation_timeout_seconds: 300
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `winrm.port` | integer | No | WinRM port | `5985` |
| `winrm.use_ssl` | boolean | No | Enable HTTPS for WinRM | `false` |
| `winrm.authentication` | string | No | Auth method: `Kerberos`, `Negotiate`, `Basic` | `Kerberos` |
| `winrm.operation_timeout_seconds` | integer | No | Command timeout in seconds | `300` |

---

## Tags

```yaml
tags:
  project: "LoadTools"
  environment: "production"
  workload: "performance-testing"
  solution: "loadtools-azure-local"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `tags.project` | string | No | Project tag | `LoadTools` |
| `tags.environment` | string | No | Environment tag | `production` |
| `tags.workload` | string | No | Workload tag | `performance-testing` |
| `tags.solution` | string | No | Solution tag | `loadtools-azure-local` |

---

## Key Vault Secret Resolution

Secrets are never stored in plaintext. The `keyvault://` URI format tells deployment tools to resolve the value at runtime:

```yaml
cluster_admin_password: "keyvault://kv-iic-loadtools/hci-cluster-admin-pwd"
```

**Resolution flow:**

1. Tool parses the URI → vault name: `kv-iic-loadtools`, secret name: `hci-cluster-admin-pwd`
2. Tool calls `az keyvault secret show --vault-name kv-iic-loadtools --name hci-cluster-admin-pwd`
3. Secret value is passed directly to the script — never written to disk
