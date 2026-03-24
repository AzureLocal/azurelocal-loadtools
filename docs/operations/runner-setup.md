# Self-Hosted Runner Setup

![Category: Operations](https://img.shields.io/badge/Category-Operations-9B59B6?style=flat-square)

Load-testing pipelines (fio, iPerf3, HammerDB, stress-ng) require a self-hosted runner on the cluster management network — they cannot use GitHub-hosted runners because they need direct SSH and WinRM access to cluster nodes.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Windows Server 2022 or Windows 11 (22H2+) |
| PowerShell | 7.3 or later (`winget install Microsoft.PowerShell`) |
| .NET | .NET 8 SDK (GitHub Actions runner dependency) |
| OpenSSH client | Built-in on Windows Server 2022; verify with `ssh -V` |
| Network | Line-of-sight to cluster management IP range |
| WinRM | Must be able to reach cluster nodes on TCP 5985/5986 |
| GitHub Actions runner | v2.311.0 or later |

---

## Installation Steps

### 1. Register the Runner

In the GitHub repository, go to **Settings → Actions → Runners → New self-hosted runner**. Follow the Windows instructions to download and configure the runner:

```powershell
# Example — replace token and URL from the GitHub UI
mkdir "C:\actions-runner"; cd "C:\actions-runner"
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-win-x64-2.311.0.zip `
    -OutFile actions-runner-win-x64.zip
Expand-Archive -Path actions-runner-win-x64.zip -DestinationPath .

.\config.cmd --url https://github.com/YOUR-ORG/azurelocal-loadtools `
             --token YOUR_TOKEN `
             --labels "self-hosted,windows,hci-management" `
             --runnergroup Default `
             --name "hci-mgmt-runner-01" `
             --work "_work"
```

### 2. Install as a Windows Service

```powershell
# Run from the actions-runner directory
.\svc.cmd install
.\svc.cmd start
```

The service runs as `NT AUTHORITY\NetworkService` by default. For WinRM access to cluster nodes, you may need to change the service account to a domain user with appropriate permissions.

### 3. Install Required PowerShell Modules

```powershell
# Run in an elevated PowerShell 7 session on the runner
$modules = @(
    "Pester",
    "PSScriptAnalyzer",
    "powershell-yaml",
    "Az.KeyVault",
    "Az.Accounts"
)

foreach ($module in $modules) {
    Install-Module -Name $module -Force -AllowClobber -Scope AllUsers
    Write-Host "Installed: $module $(Get-Module $module -ListAvailable | Select-Object -First 1 -ExpandProperty Version)"
}
```

### 4. Configure SSH Key

The runner needs the SSH private key to connect to Linux cluster nodes:

```powershell
# Create SSH directory and restrict permissions
New-Item -Path "$env:ProgramData\azurelocal-runner\.ssh" -ItemType Directory -Force

# Copy the private key (distribute from your secrets manager or GitHub Secrets via pipeline)
# Example: write key from environment variable
$env:LINUX_SSH_KEY | Set-Content "$env:ProgramData\azurelocal-runner\.ssh\azurelocal_rsa" -NoNewline
icacls "$env:ProgramData\azurelocal-runner\.ssh\azurelocal_rsa" /inheritance:r /grant:r "$($env:USERNAME):F"
```

In `config/variables.yml`, set:

```yaml
credentials:
  linux_ssh:
    private_key_path: C:\ProgramData\azurelocal-runner\.ssh\azurelocal_rsa
```

### 5. Validate WinRM Connectivity

```powershell
$clusterNodes = @("hci01-node1", "hci01-node2", "hci01-node3", "hci01-node4")
$cred = Get-Credential  # or pull from Key Vault

foreach ($node in $clusterNodes) {
    try {
        $result = Invoke-Command -ComputerName $node -Credential $cred `
            -ScriptBlock { hostname } -ErrorAction Stop
        Write-Host "WinRM OK: $node → $result"
    } catch {
        Write-Warning "WinRM FAILED: $node — $($_.Exception.Message)"
    }
}
```

### 6. Validate SSH Connectivity

```powershell
$linuxNodes = @("hci01-node1", "hci01-node2")
$sshUser    = "azurelocaladmin"
$keyPath    = "$env:ProgramData\azurelocal-runner\.ssh\azurelocal_rsa"

foreach ($node in $linuxNodes) {
    $result = ssh -i $keyPath -o BatchMode=yes -o ConnectTimeout=5 `
                  "$sshUser@$node" "echo ok" 2>&1
    Write-Host "SSH $node: $result"
}
```

---

## Runner Labels

Pipelines target the runner using the label `hci-management`. Verify that all pipeline YAML files reference this label:

```yaml
# .github/workflows/run-fio.yml (example)
jobs:
  run-fio:
    runs-on: [self-hosted, windows, hci-management]
```

---

## Maintenance

| Task | Frequency | Command |
|------|-----------|---------|
| Update runner binary | Monthly | `.\svc.cmd stop; .\config.cmd remove; # re-download and re-configure` |
| Update PowerShell modules | Monthly | `Update-Module -Scope AllUsers` |
| Rotate SSH key | Per org policy | Re-run Step 4 and update `authorized_keys` on all nodes |
| Check runner status | On pipeline failures | `Get-Service -Name "actions.runner.*" | Select-Object Status` |
