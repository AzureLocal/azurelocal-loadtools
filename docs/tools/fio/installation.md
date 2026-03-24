# fio — Installation

![Tool: fio](https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

This guide covers deploying fio onto Linux VMs on the Azure Local cluster.

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- Linux VMs deployed on the Azure Local cluster and reachable via SSH (port 22)
- SSH key-based authentication configured — the `linux_ssh` credential must be available via Key Vault or interactive prompt
- Ansible 2.14+ accessible from the management station (WSL2 or Linux jump box)
- fio 3.28+ will be installed by `Install-Fio.ps1`

See [Credential Management](../../operations/credential-management.md) for `linux_ssh` setup.

## Deploy fio via Ansible

`Install-Fio.ps1` wraps the Ansible playbook invocation:

```powershell
.\tools\fio\scripts\Install-Fio.ps1 `
    -ClusterName "hci01.corp.infiniteimprobability.com" `
    -Nodes @("hci01-node1", "hci01-node2", "hci01-node3", "hci01-node4") `
    -AnsibleInventory "config/ansible/inventory.yml" `
    -PlaybookPath "tools/fio/playbooks/deploy-fio.yml"
```

### What the Script Does

1. Validates `ansible-playbook` is available on `$PATH`
2. Verifies the inventory file and playbook exist at the provided paths
3. Runs `ansible-playbook deploy-fio.yml -i inventory.yml`
4. Returns an object with `ClusterName`, `Nodes`, `Playbook`, and `Status: Installed`

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ClusterName` | string | required | Cluster display name (used for logging) |
| `-Nodes` | string[] | required | DNS names or IPs of target Linux VMs |
| `-AnsibleInventory` | string | `config/ansible/inventory.yml` | Path to Ansible inventory file |
| `-PlaybookPath` | string | `tools/fio/playbooks/deploy-fio.yml` | Path to the deploy playbook |
| `-CredentialSource` | string | `Interactive` | `KeyVault`, `Interactive`, or `Parameter` |

## Verify Installation

After `Install-Fio.ps1` completes, verify fio is installed and accessible:

```bash
# SSH to a target node and check the version
ssh user@hci01-node1 "fio --version"
```

Expected output: `fio-3.34` (or any 3.28+).

## Supported fio Version

The framework targets **fio 3.28+**. Earlier versions may not support the `--output-format=json` structured output required by `Collect-FioResults.ps1`. If an incompatible version is detected, the collection script will fail with a JSON parse error.

## Remote Directory Structure

| Path | Purpose |
|------|---------|
| `/tmp/fio-test/` | Test target directory (pre-created by `Start-FioTest.ps1`) |
| `/tmp/fio-results/<RunId>/fio-results.json` | Structured JSON output per node |

Results are retrieved by `Collect-FioResults.ps1` via SCP and removed from the remote node after successful collection.

## Ansible Inventory Format

```yaml
# config/ansible/inventory.yml
all:
  hosts:
    hci01-node1:
      ansible_host: 192.168.100.11
      ansible_user: azureuser
      ansible_ssh_private_key_file: ~/.ssh/id_rsa
    hci01-node2:
      ansible_host: 192.168.100.12
      ansible_user: azureuser
      ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

## Next Steps

- [Workload Profiles](workload-profiles.md) — Choose and configure a test profile
- [Monitoring](monitoring.md) — Review alert thresholds active during fio runs
