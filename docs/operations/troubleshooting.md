# Operations Troubleshooting

![Category: Operations](https://img.shields.io/badge/Category-Operations-9B59B6?style=flat-square)

This guide covers cross-tool issues (credential failures, connectivity, CI/CD, and logging). For tool-specific symptoms, see the troubleshooting page for the relevant tool.

---

## SSH Key Failures

**Symptom:** Any `Start-*.ps1` or `Collect-*.ps1` script targeting Linux nodes fails with `Permission denied (publickey)`.

**Diagnosis:**

```powershell
# Test SSH connectivity in BatchMode (no interactive password fallback)
ssh -i "$env:USERPROFILE\.ssh\azurelocal_rsa" `
    -o BatchMode=yes `
    -o ConnectTimeout=5 `
    "azurelocaladmin@hci01-node1" "echo ok" 2>&1
```

**Common Causes and Resolutions:**

| Cause | Diagnostic | Fix |
|-------|-----------|-----|
| Key not distributed to node | `Permission denied` returned | `ssh-copy-id -i azurelocal_rsa.pub azurelocaladmin@hci01-node1` |
| Wrong key specified in variables.yml | `No such file or directory` | Update `credentials.linux_ssh.private_key_path` |
| Permissions too open on key file | `WARNING: UNPROTECTED PRIVATE KEY FILE` | `icacls azurelocal_rsa /inheritance:r /grant:r "$($env:USERNAME):F"` |
| SSH service not running on node | `Connection refused` on port 22 | `sudo systemctl start sshd && sudo systemctl enable sshd` |

---

## WinRM Connectivity Failures

**Symptom:** `Install-HammerDB.ps1` or any Windows-target script fails with `WinRM cannot complete the operation`.

**Diagnosis:**

```powershell
Test-WSMan -ComputerName "hci01-node1" -Authentication Negotiate
```

**Common Causes and Resolutions:**

| Cause | Diagnostic | Fix |
|-------|-----------|-----|
| WinRM not enabled on node | `Connection refused` on 5985 | `Enable-PSRemoting -Force` on the target node |
| Firewall blocking 5985/5986 | Port scan fails | `New-NetFirewallRule -Name WinRM-HTTP -Protocol TCP -LocalPort 5985 -Action Allow` |
| Credential mismatch | `Access denied` | Verify username/domain in `credentials.windows_winrm` block |
| Trusted hosts not configured | `Access is denied` on workgroup network | `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "hci01-node*"` |
| CredSSP not enabled | Used for double-hop scenarios | Enable CredSSP: `Enable-WSManCredSSP -Role Client -DelegateComputer "*.corp.infiniteimprobability.com"` |

---

## Azure Key Vault Authentication Failures

**Symptom:** `CredentialManager` reports `AADSTS700016: Application not found` or `No credential found in Key Vault`.

**Diagnosis:**

```powershell
# Verify the current Az context
Get-AzContext | Select-Object Account, Subscription, Tenant

# Test Key Vault access directly
Get-AzKeyVaultSecret -VaultName "kv-azurelocal-loadtools" -Name "linux-ssh-key" |
    Select-Object Name, Enabled, Expires
```

**Common Causes and Resolutions:**

| Cause | Fix |
|-------|-----|
| Not logged in | `Connect-AzAccount` |
| Wrong subscription selected | `Set-AzContext -SubscriptionId "..."` |
| Service principal secret expired | Rotate the secret in Entra ID; update GitHub Secrets |
| Managed identity not assigned | Assign the runner VM's managed identity the `Key Vault Secrets User` role |
| Vault name wrong in variables.yml | Check `azure.key_vault_name` in your variables file |

---

## PSScriptAnalyzer Lint Failures in CI

**Symptom:** The `lint.yml` pipeline fails with `PSScriptAnalyzer found X issues`.

**Diagnosis:**

```powershell
# Run locally before pushing
Invoke-ScriptAnalyzer -Path .\scripts\ -Recurse -Settings PSGallery |
    Where-Object { $_.Severity -in "Warning","Error" } |
    Format-Table RuleName, Severity, Message, ScriptName, Line -AutoSize
```

**Common Issues:**

| Rule | Fix |
|------|-----|
| `PSAvoidUsingInvokeExpression` | Replace `Invoke-Expression` with `& $scriptPath` |
| `PSUseShouldProcessForStateChangingFunctions` | Add `[CmdletBinding(SupportsShouldProcess)]` and `$PSCmdlet.ShouldProcess()` guard |
| `PSAvoidUsingPlainTextForPassword` | Use `[SecureString]` parameter type for password parameters |
| `PSAvoidTrailingWhitespace` | Run `sed -i 's/[[:space:]]*$//' *.ps1` or use VS Code "Trim Trailing Whitespace" |

---

## Pester Unit Test Failures

**Symptom:** `run-tests.yml` pipeline step fails with `Pester test(s) failed`.

**Diagnosis:**

```powershell
# Run tests locally with verbose output
Invoke-Pester -Path tests\unit\ -Output Detailed -PassThru |
    Select-Object -ExpandProperty TestResult |
    Where-Object { $_.Result -eq "Failed" } |
    Select-Object Name, ErrorRecord
```

**Common Causes:**

- Mock not matching updated function signature — update the `Mock` call in the test file
- Module not imported in `BeforeAll` — ensure `Import-Module "src\common\modules\..."` in the describe block
- Test assumes a file exists that has been moved — update the path in the fixture setup

---

## Log Correlation

Every run writes logs under `logs\<tool>\<RunId>\`. Use the RunId to correlate across files:

```powershell
$runId = "fio-sequentialread-202412011430"
$logDir = "logs\fio\$runId"

# Show all events for this run in chronological order
Get-ChildItem "$logDir\*.jsonl" | ForEach-Object {
    Get-Content $_ | ConvertFrom-Json
} | Sort-Object timestamp | Format-Table timestamp, level, message -AutoSize
```

Alert events are in `alerts-<node>.jsonl`; PerfMon samples are in `monitor-<node>.jsonl`. The `state\<RunId>.json` file records which phases completed successfully — check it when debugging a mid-run failure:

```powershell
Get-Content "state\$runId.json" | ConvertFrom-Json |
    Select-Object phase, status, completed_at
```
