# Canonical Variable Migration Checklist — azurelocal-loadtools

## Status: Wave 2

## Prerequisites
- [x] CanonicalVariable.psm1 deployed to `common/modules/`
- [ ] Validate `config/variables/variables.example.yml` against canonical schema
- [ ] Confirm CI pipeline passes with no regressions

## Migration Steps

### Step 1: ConfigManager Integration
The repo has its own `common/modules/ConfigManager/ConfigManager.psm1` with `Import-MasterConfig`.
Integration approach:
- Add `CanonicalVariable.psm1` as a dependency of `ConfigManager`
- Delegate variable lookups through canonical reader for alias resolution
- Preserve ConfigManager's solution filtering (tags) and dual-config (master + cluster)

### Step 2: Script Migration (8+ scripts)

| Script | Complexity | Status |
|--------|-----------|--------|
| common/helpers/Initialize-Environment.ps1 | Low — bootstrap only | [ ] |
| common/modules/ConfigManager/ConfigManager.psm1 | High — core module | [ ] |
| common/helpers/Common-Functions.ps1 | Medium — cluster node lookups | [ ] |
| tools/vmfleet/Invoke-VMFleetPipeline.ps1 | High — dual config | [ ] |
| tools/vmfleet/infrastructure/Prepare-VMFleetBaseImage.ps1 | High — inline dual YAML | [ ] |
| tools/vmfleet/scripts/Deploy-VMFleet.ps1 | Low — pipeline params | [ ] |
| tools/vmfleet/scripts/Install-VMFleet.ps1 | Low — pipeline params | [ ] |
| tools/fio/* | Medium — tool-specific | [ ] |
| tools/iperf/* | Medium — tool-specific | [ ] |
| tools/stress-ng/* | Medium — tool-specific | [ ] |

### Step 3: Variable Path Mapping
Key paths used → canonical equivalents:

| Legacy Path | Canonical Path |
|------------|---------------|
| `$config.azure.subscription_id` | `azure_platform.subscription_id` |
| `$config.azure.resource_group` | `azure_platform.resource_groups.*` |
| `$config.azure.location` | `azure_platform.location` |
| `$config.azure_local.custom_location_id` | `compute.clusters.azure_local.azl_custom_location_id` |
| `$config.azure_local.storage_path_id` | `storage.storage_path_id` |
| `$config.storage.*` | `storage.*` |
| `$clusterConfig.nodes[].name` | `compute.cluster_nodes[].hostname` |

### Step 4: Dual Config Architecture
Loadtools uses two separate YAML files:
- `config/variables/variables.yml` — master variables
- `config/clusters/cluster.yml` — cluster-specific config

Migration approach:
- Master variables: migrate to canonical reader
- Cluster config: keep separate (cluster-specific, not in registry)

### Step 5: Validation Gate
- [ ] Run canonical schema validator
- [ ] Add CI check to `.azuredevops/` pipeline

## Notes
- Most complex consumer repo — has its own ConfigManager module with solution tagging
- Tool-specific profiles (vmfleet.json, iperf profiles) are separate from canonical variables
- The nested config path (`config/variables/variables.yml`) is already compatible with bootstrap
