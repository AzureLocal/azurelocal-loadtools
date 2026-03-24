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
Copy-Item config/clusters/example-cluster.yml config/clusters/my-cluster.yml
```

Edit `config/clusters/my-cluster.yml` with your cluster details:

```yaml
cluster:
  name: "my-hci-cluster"
  domain: "contoso.local"
  nodes:
    - name: "hci-node-01"
      management_ip: "10.0.0.1"
    - name: "hci-node-02"
      management_ip: "10.0.0.2"
  csv_path: "C:\\ClusterStorage\\Volume1"
  collect_volume_path: "C:\\ClusterStorage\\Collect"
  base_vhd_path: "C:\\ClusterStorage\\Collect\\BaseImage.vhdx"
```

## Initialize the Environment

```powershell
# Run the environment initialization script
.\src\core\powershell\helpers\Initialize-Environment.ps1 `
    -ClusterConfig "config/clusters/my-cluster.yml" `
    -CredentialSource Interactive
```

This will:

1. Load and validate the cluster configuration
2. Test connectivity to all cluster nodes
3. Verify Storage Spaces Direct health
4. Check for required volumes and base VHD
5. Generate solution-specific configuration files from the master environment
6. Create initial run state

## Verify Installation

```powershell
# Run the validation suite
Invoke-Pester tests/unit/ -Output Detailed
```

All tests should pass, confirming modules load correctly and configuration is valid.

## Next Steps

- [Configuration](configuration.md) — Understand the configuration system
- [VMFleet Guide](../tools/vmfleet/index.md) — Start with VMFleet storage testing
