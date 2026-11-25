# Configuration System

![Category: Getting Started](https://img.shields.io/badge/Category-Getting%20Started-2ECC71?style=flat-square)

The configuration system is the backbone of the Azure Local Load Testing Framework. It ensures that **nothing is hardcoded** and every value is parameterizable.

## Configuration Architecture

**Configuration Hierarchy**

```text
config/
├── variables/
│   ├── variables.yml                ← The test settings (committed, no cluster facts)
│   ├── variables.example.yml        ← Reference layout of the values a run uses
│   ├── schema/variables.schema.json ← JSON Schema for validation
│   └── solutions/                   ← Generated per-solution config files
│       ├── vmfleet.json
│       ├── fio.json
│       └── ...
tools/<tool>/config/profiles/        ← Workload test profiles (per tool)
infrastructure.yml                   ← The cluster, from the environment (not in this repo)
```

## Master Environment File

The `variables.yml` file contains the **test settings** used across all solutions (profile defaults, durations, VMFleet sizing, monitoring, reporting, logging, fault injection). Each variable is tagged with the solutions that consume it. It holds no cluster facts: the cluster name, nodes, domain, cluster shared volume, Azure scope and Key Vault come from `infrastructure.yml` (see [Cluster Configuration](#cluster-configuration)).

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
Import-Module ./common/modules/ConfigManager/ConfigManager.psm1

Export-SolutionConfig -Solution "vmfleet" `
    -MasterConfigPath "./config/variables/variables.yml" `
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
3. **Master Default** — Fallback value from `variables.yml`

```powershell
# Override chain example:
# 1. Explicit parameter wins
Start-VMFleetTest -VmCountPerNode 20

# 2. Without parameter, reads from vmfleet.json
Start-VMFleetTest

# 3. If vmfleet.json missing, falls back to variables.yml default
```

## Cluster Configuration

The cluster is the environment's `infrastructure.yml` (schema 5), the one file every Azure Local tool reads. To target a cluster, pass its file:

```powershell
# Target different clusters by passing a different environment file
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 -ClusterConfigPath ".\prod\infrastructure.yml"
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 -ClusterConfigPath ".\dev\infrastructure.yml"

# Resolve the cluster facts into the solution JSON files
Export-SolutionConfig -Solution "vmfleet" -InfrastructureFile ".\prod\infrastructure.yml"
```

The file must be schema 5 and hold `cluster.name` and `nodes[].name`. The facts Load Tools reads are listed in [Variable Reference](../reference/variables.md#where-the-cluster-facts-come-from). A per-cluster file of the earlier layout (`config/clusters/*.yml`) is still read, with a warning; the VMFleet scripts read their own per-cluster file (`config/clusters/example-cluster.yml`: nodes by management IP) without one.

The VMFleet scripts also read their own per-cluster file from `config/clusters/`, which reaches the nodes by management IP instead of by name. It defines the cluster name, the nodes by management IP (`nodes[].name`, the remoting target), the Collect volume and the per-node volumes (`storage`). Copy `config/clusters/example-cluster.yml`; real cluster files are git-ignored. To switch clusters, change the `-ClusterConfigPath` parameter:

```powershell
# Target different clusters by swapping config files
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 -ClusterConfigPath config\clusters\prod-cluster.yml -Credential $cred -FleetAdminCredential $fleetAdmin
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 -ClusterConfigPath config\clusters\dev-cluster.yml -Credential $cred -FleetAdminCredential $fleetAdmin
```

The VMFleet scripts read `tools\vmfleet\config\vmfleet.json`, the file generated from the registry (`vm_count_per_node`, `vm_vcpu_count`, `vm_memory_gb`, `vmfleet_version`, `base_vhd_path`, `test_duration_seconds`, `warmup_seconds`, `cooldown_seconds`); the layout and an example are in [VMFleet deployment](../tools/vmfleet/deployment.md#cluster-configuration).

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
$cred = Get-ManagedCredential -Name "cluster_admin"   # -Credential, then CLUSTER_ADMIN_USERNAME / CLUSTER_ADMIN_PASSWORD, then Key Vault
```

See [Credential Management](../operations/credential-management.md) for the credential sources (parameter, environment variable, Key Vault). Nothing prompts.

## Next Steps

Choose a tool to get started:

- [VMFleet Guide](../tools/vmfleet/index.md) — Storage load testing
- [fio Guide](../tools/fio/index.md) — Flexible I/O benchmarking
- [iPerf3 Guide](../tools/iperf/index.md) — Network testing
