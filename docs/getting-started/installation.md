# Installation

![Category: Getting Started](https://img.shields.io/badge/Category-Getting%20Started-2ECC71?style=flat-square)

This guide walks through the installation and initial setup of the Azure Local Load Testing Framework.

## Clone the Repository

```powershell
git clone https://github.com/AzureLocal/azurelocal-loadtools.git
cd azurelocal-loadtools
```

## Install PowerShell Dependencies

```powershell
# Install required PowerShell modules
Install-Module -Name powershell-yaml -Scope CurrentUser -Force
Install-Module -Name ImportExcel -Scope CurrentUser -Force
Install-Module -Name Az.KeyVault -Scope CurrentUser -Force
Install-Module -Name Az.Monitor -Scope CurrentUser -Force
Install-Module -Name VMFleet -Scope CurrentUser -Force
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
```

## Install Report Generation Tools

### Asciidoctor (PDF Reports)

```powershell
# Install Ruby (via winget or chocolatey)
winget install RubyInstallerTeam.Ruby.3.2

# Install Asciidoctor and PDF generator
gem install asciidoctor asciidoctor-pdf rouge
```

### Pandoc (Word Reports)

```powershell
# Install Pandoc
winget install JohnMacFarlane.Pandoc
```

## Install Ansible (Optional — Linux Tools)

Ansible is required only for Linux-based tools (fio, iPerf3, HammerDB, stress-ng).

### Option A: WSL2 on Windows

```powershell
# Enable WSL2 and install Ubuntu
wsl --install -d Ubuntu

# Inside WSL2:
sudo apt update && sudo apt install -y python3-pip
pip3 install ansible
```

### Option B: Linux Jump Box

```bash
# On a dedicated Linux management VM
sudo apt update && sudo apt install -y python3-pip
pip3 install ansible
```

### Option C: CI Runner Only

Ansible is installed as part of the CI/CD pipeline. See the [CI/CD Pipelines](../operations/ci-cd.md) guide.

## Configure Cluster Connection

The cluster comes from the environment's `infrastructure.yml` (schema 5), the one file every Azure Local tool reads. Trailwright writes it from the plan, hardware discovery fills the serial numbers and MAC addresses, and the toolkit deploys from it. Load Tools reads these keys and nothing else of it:

| Key | Used for |
|-----|----------|
| `cluster.name` | The cluster to test |
| `nodes[].name` | The nodes the scripts connect to |
| `identity.active_directory.domain_fqdn` | The domain of the nodes |
| `storage.paths[].path` (else the first `storage.volumes[].name`) | The cluster shared volume (`C:\ClusterStorage\<volume>`) |
| `azure.tenant_id`, `subscription_id`, `resource_group`, `location`, `custom_location` | The Azure scope; the custom location and the first storage path give the IDs `Prepare-VMFleetBaseImage.ps1` needs |
| `key_vaults[]` (purpose `management`, else the first; else `cluster.key_vault.name`) | The Key Vault for credentials |
| `_metadata.schema_version` | Must start with `5`; any other value stops the script |

Pass it as `-InfrastructureFile` to `Initialize-Environment.ps1` and `Export-SolutionConfig`, or as `-ClusterConfigPath` to any tool script. The file must be schema 5 (`_metadata.schema_version`) and hold `cluster.name` and `nodes[].name`, or the script stops and says which is missing. A per-cluster file of the earlier layout is still read, with a warning; the VMFleet scripts read their own per-cluster file (`config/clusters/example-cluster.yml`: nodes by management IP) without one. To start, copy the Load Tools template from the toolkit (`config/variables/templates/tools/loadtools.yml`) or use your Trailwright export. The part of the file Load Tools reads (the other sections are for the tools that deploy the cluster; example values):

```yaml
_metadata:
  schema_version: "5.6.35"
  scope: "loadtools"

azure:
  tenant_id: "00000000-0000-0000-0000-000000000000"
  subscription_id: "00000000-0000-0000-0000-000000000000"
  resource_group: "rg-iic-azl-01"
  location: "eastus"
  custom_location: "cl-iic-azl-01"

key_vaults:
  - name: "kv-iic-mgmt-01"
    purpose: "management"

cluster:
  name: "iic-azl-01"

nodes:
  - name: "iic-azl-n01"
  - name: "iic-azl-n02"

identity:
  active_directory:
    domain_fqdn: "improbability.cloud"

storage:
  paths:
    - name: "sp-workloads-01"
      path: "C:\\ClusterStorage\\vol-workloads-01\\vms"
```

`_metadata.scope: loadtools` marks a file cut for this tool; the full file works the same. The VMFleet base image path and the collect volume are test settings (`storage.base_vhd_path` and the others in `config/variables/variables.yml`), not cluster facts.

### VMFleet: nodes by management IP

The VMFleet scripts remote into the nodes by `nodes[].name`. When the management host is not domain-joined and cannot resolve the node names, use VMFleet's own per-cluster file instead, which holds the management IPs (put them in `TrustedHosts`):

```powershell
Copy-Item config/clusters/example-cluster.yml config/clusters/cluster.yml
```

`config/clusters/cluster.yml` is git-ignored because it holds real IP addresses. Edit it with your cluster details:

```yaml
cluster:
  name: "my-hci-cluster"            # reports only
nodes:
  - name: "192.0.2.11"              # management IP, the remoting target; the first node runs the VMFleet steps
    hostname: "hci-node-01"         # optional, display only
  - name: "192.0.2.12"
    hostname: "hci-node-02"
storage:
  collect_path: "C:\ClusterStorage\Collect"
  node_volumes:
    - "C:\ClusterStorage\hci-node-01"
    - "C:\ClusterStorage\hci-node-02"
  base_vhd_path: "C:\ClusterStorage\Collect\base\vmfleet-base.vhdx"
```

Pass either file as `-ClusterConfigPath`. The other tools (fio, iPerf3, HammerDB, stress-ng) read `nodes[].name` the same way. See [VMFleet deployment](../tools/vmfleet/deployment.md) for the base image and the credentials.

## Initialize the Environment

```powershell
# Run the environment initialization script
.\common\helpers\Initialize-Environment.ps1 -Solution VMFleet `
    -MasterConfigPath "config/variables/variables.yml" `
    -InfrastructureFile ".\infrastructure.yml"
```

(`Initialize-Environment.ps1` only checks that the cluster file exists.)

This will:

1. Check the local prerequisites (PowerShell 7.2+, `powershell-yaml`, optional modules and report tools, and the `VMFleet` module when `-Solution VMFleet`); skip with `-SkipPrerequisiteCheck`
2. Check that `config/variables/variables.yml` (committed, the test settings) exists, and stop with an error when it is missing; load the core modules from `common/modules`
3. Validate the master configuration file and read the cluster facts from the `infrastructure.yml` (the script returns them as an object; without `-InfrastructureFile` it warns that the cluster facts are not resolved)
4. Create the working directory structure

Cluster connectivity, Storage Spaces Direct health and base VHD checks are not part of this script; run them per tool (see the [VMFleet prerequisites](../tools/vmfleet/prerequisites.md)).

## Verify Installation

```powershell
# Run the validation suite
Invoke-Pester tests/unit/ -Output Detailed
```

All tests should pass, confirming modules load correctly and configuration is valid.

## Next Steps

- [Configuration](configuration.md) — Understand the configuration system
- [VMFleet Guide](../tools/vmfleet/index.md) — Start with VMFleet storage testing
