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

Copy the example cluster configuration and customize:

```powershell
Copy-Item config/clusters/example-cluster.yml config/clusters/cluster.yml
```

`config/clusters/cluster.yml` is git-ignored because it holds real IP addresses. Edit it with your cluster details. The management host does not have to be domain-joined: the nodes are reached by management IP (put them in `TrustedHosts`), so the IPs go in `nodes[].name`:

```yaml
cluster:
  name: "my-hci-cluster"            # reports only
nodes:
  - name: "192.0.2.11"              # management IP, the remoting target; the first node runs the VMFleet steps
    hostname: "hci-node-01"         # optional, display only
  - name: "192.0.2.12"
    hostname: "hci-node-02"
storage:
  collect_path: "C:\\ClusterStorage\\Collect"
  node_volumes:
    - "C:\\ClusterStorage\\hci-node-01"
    - "C:\\ClusterStorage\\hci-node-02"
  base_vhd_path: "C:\\ClusterStorage\\Collect\\base\\vmfleet-base.vhdx"
```

The other tools (fio, iPerf3, HammerDB, stress-ng) read `nodes[].name` the same way. See [VMFleet deployment](../tools/vmfleet/deployment.md) for the base image and the credentials.

## Initialize the Environment

```powershell
# Run the environment initialization script
.\common\helpers\Initialize-Environment.ps1 -Solution VMFleet `
    -MasterConfigPath "config/variables/variables.yml" `
    -ClusterConfigPath "config/clusters/cluster.yml"
```

(`Initialize-Environment.ps1` only checks that the cluster file exists.)

This will:

1. Check the local prerequisites (PowerShell 7.2+, `powershell-yaml`, optional modules and report tools, and the `VMFleet` module when `-Solution VMFleet`); skip with `-SkipPrerequisiteCheck`
2. Create `config/variables/variables.yml` from the example when it is missing, and load the core modules from `common/modules`
3. Validate the master and cluster configuration files when they are given
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
