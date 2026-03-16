# Configuration System

![Category: Getting Started](https://img.shields.io/badge/Category-Getting%20Started-2ECC71?style=flat-square)

The configuration system is the backbone of the Azure Local Load Testing Framework. It ensures that **nothing is hardcoded** and every value is parameterizable.

## Configuration Architecture

**Configuration Hierarchy**

```text
config/
├── variables/
│   ├── master-environment.yml       ← Single source of truth for ALL variables
│   ├── schema.json                  ← JSON Schema for validation
│   └── solutions/                   ← Generated per-solution config files
│       ├── vmfleet.json
│       ├── fio.json
│       └── ...
├── clusters/                        ← Per-cluster connection configs
│   └── example-cluster.yml
├── profiles/                        ← Workload test profiles
│   ├── vmfleet/
│   └── ...
└── credentials/
    └── keyvault-config.yml          ← Key Vault connection settings
```

## Master Environment File

The `master-environment.yml` file contains **every** variable used across all solutions. Each variable is tagged with the solutions that consume it.

**Variable Structure**

```yaml
variables:
  - name: vm_count_per_node
    value: 10
    type: integer
    required: true
    description: "Number of fleet VMs to deploy per cluster node"
    solutions: [vmfleet]
    category: deployment
```

**Variable Properties**

| Property | Description | Required |
|----------|-------------|----------|
| `name` | Unique variable identifier (snake_case) | Yes |
| `value` | Default value | Yes |
| `type` | Data type: string, integer, boolean, array | Yes |
| `required` | Whether the variable must have a non-empty value | Yes |
| `description` | Human-readable description | Yes |
| `solutions` | Array of solution tags: vmfleet, fio, iperf, hammerdb, stress-ng | Yes |
| `category` | Logical grouping: cluster, deployment, testing, monitoring, reporting | No |
| `sensitive` | If true, value should come from Key Vault (never stored in YAML) | No |

## Solution Configuration Generation

The `ConfigManager` module reads the master environment, filters by solution tag, and writes JSON:

```powershell
# Generate VMFleet-specific configuration
Import-Module ./src/core/powershell/modules/ConfigManager/ConfigManager.psm1

Export-SolutionConfig -Solution "vmfleet" `
    -MasterConfigPath "./config/variables/master-environment.yml" `
    -OutputPath "./config/variables/solutions/vmfleet.json"
```

The generated `vmfleet.json` contains only variables tagged with `vmfleet`:

```json
{
  "vm_count_per_node": 10,
  "vm_vcpu_count": 2,
  "vm_memory_gb": 2,
  "test_duration_seconds": 300,
  "warmup_seconds": 60
}
```

## Variable Override Chain

Every script supports a three-level override chain:

1. **Explicit Parameter** — Highest priority. Pass `-VmCountPerNode 20` to any script.
2. **Solution JSON** — Read from `config/variables/solutions/{solution}.json`
3. **Master Default** — Fallback value from `master-environment.yml`

```powershell
# Override chain example:
# 1. Explicit parameter wins
Start-VMFleetTest -VmCountPerNode 20

# 2. Without parameter, reads from vmfleet.json
Start-VMFleetTest

# 3. If vmfleet.json missing, falls back to master-environment.yml default
```

## Cluster Configuration

Cluster configs in `config/clusters/` define target cluster details. To switch clusters, change the `-ClusterConfig` parameter:

```powershell
# Target different clusters by swapping config files
.\Invoke-VMFleetPipeline.ps1 -ClusterConfig "config/clusters/prod-cluster.yml"
.\Invoke-VMFleetPipeline.ps1 -ClusterConfig "config/clusters/dev-cluster.yml"
```

## Workload Profiles

Each solution has predefined workload profiles in `config/profiles/{solution}/`:

```yaml
# config/profiles/vmfleet/general.yml
profile:
  name: "General"
  description: "Balanced read/write workload for general validation"
  parameters:
    block_size: "8k"
    write_ratio: 30
    random_ratio: 70
    outstanding_io: 8
    threads_per_vm: 2
    duration_seconds: 300
    warmup_seconds: 60
```

## Credential Configuration

The `keyvault-config.yml` maps logical credential names to Key Vault secrets:

```yaml
keyvault:
  name: "my-keyvault-name"
  resource_group: "my-rg"
  secrets:
    cluster_admin_password: "hci-cluster-admin-pwd"
    cluster_admin_username: "hci-cluster-admin-user"
    azure_client_secret: "sp-client-secret"
```

Scripts use `CredentialManager` to retrieve credentials without knowing the storage mechanism:

```powershell
$cred = Get-ManagedCredential -Name "cluster_admin" -Source KeyVault
```

See [Credential Management](../operations/credential-management.md) for full details on the three credential modes.

## Next Steps

Choose a tool to get started:

- [VMFleet Guide](../tools/vmfleet/overview.md) — Storage load testing
- [fio Guide](../tools/fio/overview.md) — Flexible I/O benchmarking
- [iPerf3 Guide](../tools/iperf/overview.md) — Network testing
