# Credential Management

![Category: Operations](https://img.shields.io/badge/Category-Operations-9B59B6?style=flat-square)

All credential handling in the Azure Local Load Testing Framework follows the principle of least privilege. Credentials are **never hardcoded** in scripts or configuration files, and **no script prompts** for a credential or a secret.

## Credential Sources

The `CredentialManager` module takes a credential or secret from one of three places:

| Source | How It Works | Best For |
| --- | --- | --- |
| **Parameter** | The caller passes a `[PSCredential]` (or a secret value) | Scripted orchestration, pipelines, testing |
| **Environment** | `<NAME>_USERNAME` and `<NAME>_PASSWORD` (for example `CLUSTER_ADMIN_USERNAME` and `CLUSTER_ADMIN_PASSWORD`); a secret uses its name in upper case (for example `LOG_ANALYTICS_KEY`) | CI/CD variables, local runs |
| **Key Vault** | The secret mapped in `config/credentials/keyvault-config.yml`, read with `Az.KeyVault` | Production, shared runners |

The default source is **Auto**: the parameter when one is passed, then the environment variables, then Key Vault when `keyvault-config.yml` maps the name. When none has a value, the call stops with a message that names the parameter, the environment variables and the Key Vault mapping to set. A script that cannot get a credential stops with that message and exit code 2.

## Using Credentials in Scripts

```powershell
# Auto: -Credential, then CLUSTER_ADMIN_USERNAME / CLUSTER_ADMIN_PASSWORD, then Key Vault
$cred = Get-ManagedCredential -Name 'cluster_admin'

# One source only
$cred = Get-ManagedCredential -Name 'cluster_admin' -Source KeyVault
$cred = Get-ManagedCredential -Name 'cluster_admin' -Source Environment
$cred = Get-ManagedCredential -Name 'cluster_admin' -Source Parameter -Credential $myCred

# A single secret: -Value, then LOG_ANALYTICS_KEY, then Key Vault
$key = Get-ManagedSecret -Name 'log_analytics_key'
```

The tool scripts take a `-Credential` parameter (the cluster administrator, `cluster_admin`). When it is not passed they use the environment variables or Key Vault:

```powershell
$env:CLUSTER_ADMIN_USERNAME = 'iic\svc-loadtools'
$env:CLUSTER_ADMIN_PASSWORD = '<from your secret store>'
.\tools\vmfleet\Invoke-VMFleetPipeline.ps1 `
    -ClusterConfigPath "config\clusters\iic-cluster01.yml"
```

The Linux tools (fio, iPerf3, stress-ng) connect over SSH with a key. The SSH user comes from `-SshUser`, then `cluster.ssh_user` in the cluster file, then the `LINUX_SSH_USERNAME` environment variable, then the `linux_ssh_username` Key Vault mapping. When none is set, the script stops with exit code 2.

## Key Vault Configuration

The `config/credentials/keyvault-config.yml` file maps logical credential names to Key Vault secrets. A credential named `cluster_admin` reads `cluster_admin_password` and `cluster_admin_username` (or the caller passes `-Username`; without a user name the call stops with a message, no account name is assumed):

```yaml
keyvault:
  name: "kv-iic-loadtools"
  resource_group: "rg-iic-loadtools"
  secrets:
    cluster_admin_password: "hci-cluster-admin-pwd"
    cluster_admin_username: "hci-cluster-admin-user"
    linux_ssh_username: "linux-ssh-user"
    log_analytics_key: "log-analytics-key"
```

Sign in to Azure first (`Connect-AzAccount`, a managed identity or a service principal). The module does not sign in for you and does not prompt.

### Deploying Key Vault Infrastructure

Use the provided Bicep template:

```powershell
az deployment group create `
    -g "rg-iic-loadtools" `
    -f "common/bicep/keyvault.bicep" `
    -p vaultName="kv-iic-loadtools"
```

## CI/CD Credential Patterns

| Platform | Credential Mechanism |
| --- | --- |
| GitHub Actions | GitHub Secrets → environment variables (`CLUSTER_ADMIN_USERNAME`, `CLUSTER_ADMIN_PASSWORD`) |
| Azure DevOps | Variable group → a `PSCredential` passed as `-Credential` (see `.azuredevops/azure-pipelines-vmfleet.yml`) |
| GitLab CI | CI/CD Variables (masked) → environment variables |

## Security Practices

- All credential access is logged — values are **masked** in logs for audit trail
- Key Vault access should use managed identity where possible
- Rotate secrets on a regular schedule
- Use `:sensitive: true` in `variables.yml` to flag variables that must come from Key Vault
- Never commit credentials to the repository — use `.gitignore` and pre-commit hooks
