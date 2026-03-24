# Prerequisites

![Category: Getting Started](https://img.shields.io/badge/Category-Getting%20Started-2ECC71?style=flat-square)

Before deploying the Azure Local Load Testing Framework, ensure the following common prerequisites are met. Individual tools may have additional requirements — see each tool's prerequisites page.

## Azure Local Cluster Requirements

| Requirement | Details |
|-------------|---------|
| Azure Local Version | Azure Stack HCI 23H2 or later (22H2 supported with limitations) |
| Cluster Nodes | Minimum 2 nodes; recommended 4+ for meaningful fleet testing |
| Storage Spaces Direct (S2D) | Enabled and healthy (`Get-StorageSubSystem` shows `HealthStatus: Healthy`) |
| Cluster Shared Volumes | At least one CSV for VM fleet storage; additional CSV for results collection |

## Network Requirements

| Requirement | Details |
|-------------|---------|
| Management Network | IP connectivity from management station to all cluster nodes |
| PowerShell Remoting | WinRM enabled on all cluster nodes (default for Azure Local) |
| RDMA (Optional) | Required for storage network performance validation with iPerf3 |
| Firewall | Ports 5985 (WinRM HTTP), 5986 (WinRM HTTPS) open from management station |

## Management Station Requirements

The management station is where automation scripts execute. This can be a physical workstation, jump box, or CI/CD runner.

| Requirement | Details |
|-------------|---------|
| Operating System | Windows 10/11 or Windows Server 2019+ (PowerShell 7.2+) |
| PowerShell | Version 7.2 or later (`$PSVersionTable.PSVersion`) |
| PowerShell Modules | `Az.KeyVault`, `Az.Monitor`, `powershell-yaml`, `ImportExcel` |
| Asciidoctor | Ruby 3.0+, `asciidoctor`, `asciidoctor-pdf` gems (for report generation) |
| Pandoc | Version 3.0+ (for DOCX report generation) |
| Git | Version 2.30+ (for repository management) |

## Ansible Requirements (for Linux-Based Tools)

Ansible is required only if using fio, iPerf3, HammerDB, or stress-ng on Linux VMs.

| Requirement | Details |
|-------------|---------|
| Ansible | Version 2.14+ (installed via `pip install ansible`) |
| Execution Environment | WSL2 on Windows, Linux jump box, or CI runner (see installation guide) |
| SSH Access | Key-based SSH authentication to target Linux VMs |
| Python | Version 3.9+ on the Ansible control node |

## Azure Requirements (Optional)

Required only if using Azure Monitor integration or Azure Key Vault for credentials.

| Requirement | Details |
|-------------|---------|
| Azure Subscription | Active subscription with Contributor access |
| Azure Key Vault | Provisioned Key Vault with secrets for cluster credentials |
| Log Analytics Workspace | Provisioned workspace for Azure Monitor metric ingestion |
| Service Principal or Managed Identity | For non-interactive Azure authentication in CI/CD |
| Azure Local custom location | Required for marketplace image acquisition (`azure_local.custom_location_id`) |
| Azure Local storage container | Required to resolve VHDX path (`azure_local.storage_path_id`) |

## Validating Prerequisites

Run the pre-check script to validate all common prerequisites:

```powershell
# From the repository root
.\src\core\powershell\helpers\Initialize-Environment.ps1 -ValidateOnly
```

This will check:

- PowerShell version and required modules
- Cluster connectivity and S2D health
- Required volumes availability
- Azure connectivity (if Azure features enabled)
- Ansible availability (if Linux tools enabled)

## Tool-Specific Prerequisites

Each tool may have additional requirements beyond the common set above:

- [VMFleet Prerequisites](../tools/vmfleet/prerequisites.md) — Base VHD, Collect volume, VMFleet module
- [fio Prerequisites](../tools/fio/index.md) — Linux VMs, fio package
- [iPerf3 Prerequisites](../tools/iperf/index.md) — iPerf3 binaries, RDMA configuration
- [HammerDB Prerequisites](../tools/hammerdb/index.md) — SQL Server, HammerDB installation
- [stress-ng Prerequisites](../tools/stress-ng/index.md) — Linux VMs, stress-ng package

## Next Steps

- [Installation](installation.md) — Install the framework and dependencies
