# =============================================================================
# CredentialManager Module - Azure Local Load Tools
# =============================================================================
# Non-interactive credential retrieval. A credential or secret comes from a
# parameter the caller passes, from an environment variable, or from Azure Key
# Vault (the reference mapped in config/credentials/keyvault-config.yml).
# Nothing prompts: when no source has a value, the call stops with a message
# that says what to pass or set. Credentials are never hardcoded.
# =============================================================================

# Module-level variables
$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:VaultConfig = $null

function Get-VaultConfigPath {
    # Resolves the keyvault-config.yml path: explicit path, else <ProjectRoot>/config/credentials/keyvault-config.yml.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$VaultConfigPath,

        [Parameter()]
        [string]$ProjectRoot
    )

    if ($VaultConfigPath) { return $VaultConfigPath }
    $root = if ($ProjectRoot) { $ProjectRoot } else { $script:ProjectRoot }
    return (Join-Path $root 'config\credentials\keyvault-config.yml')
}

function ConvertTo-EnvironmentName {
    # 'cluster_admin' -> 'CLUSTER_ADMIN'; any character other than A-Z, 0-9 becomes '_'.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return ($Name -replace '[^A-Za-z0-9]', '_').ToUpperInvariant()
}

function Import-VaultConfig {
    <#
    .SYNOPSIS
        Loads the Key Vault configuration from YAML.
    .PARAMETER VaultConfigPath
        Path to keyvault-config.yml. Defaults to config/credentials/keyvault-config.yml.
    .PARAMETER ProjectRoot
        Repository root used to find the default keyvault-config.yml.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$VaultConfigPath,

        [Parameter()]
        [string]$ProjectRoot
    )

    $VaultConfigPath = Get-VaultConfigPath -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot

    if (-not (Test-Path -LiteralPath $VaultConfigPath)) {
        throw "Key Vault config not found: $VaultConfigPath. Required for the KeyVault credential source."
    }

    if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        Import-Module powershell-yaml -ErrorAction Stop
    }

    $yamlContent = Get-Content -LiteralPath $VaultConfigPath -Raw
    $script:VaultConfig = (ConvertFrom-Yaml $yamlContent).keyvault

    return $script:VaultConfig
}

function Get-VaultSecretName {
    # Returns the Key Vault secret name mapped to the first of the given logical keys, or $null.
    # Never throws: a missing or unreadable config means "no mapping".
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Key,

        [Parameter()]
        [string]$VaultConfigPath,

        [Parameter()]
        [string]$ProjectRoot
    )

    $path = Get-VaultConfigPath -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    try {
        $config = Import-VaultConfig -VaultConfigPath $path
    } catch {
        Write-Verbose "Key Vault config '$path' could not be read: $($_.Exception.Message)"
        return $null
    }

    if (-not $config -or -not $config.secrets) { return $null }
    foreach ($k in $Key) {
        $mapped = $config.secrets[$k]
        if ($mapped) { return [string]$mapped }
    }
    return $null
}

function Invoke-VaultSecretRead {
    # The single place that reads Azure Key Vault. Tests mock this function.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter(Mandatory)]
        [string]$SecretName
    )

    if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
        throw "Az.KeyVault module is required for Key Vault credential retrieval. Install with: Install-Module Az.KeyVault"
    }
    Import-Module Az.KeyVault -ErrorAction Stop

    try {
        return Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -AsPlainText -ErrorAction Stop
    } catch {
        throw "Failed to retrieve secret '$SecretName' from Key Vault '$VaultName': $($_.Exception.Message)"
    }
}

function Get-MissingCredentialMessage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$VaultConfigPath,

        [Parameter()]
        [string]$ProjectRoot
    )

    $base = $Name -replace '_password$', ''
    $envBase = ConvertTo-EnvironmentName -Name $base
    $path = Get-VaultConfigPath -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot
    return ("No credential found for '{0}'. Pass -Credential, set the environment variables {1}_USERNAME and {1}_PASSWORD, " +
        "or map '{2}_password' (and '{2}_username') under keyvault.secrets in {3}.") -f $Name, $envBase, $base, $path
}

function Get-ManagedCredential {
    <#
    .SYNOPSIS
        Retrieves a credential from a parameter, an environment variable or Azure Key Vault. Never prompts.
    .DESCRIPTION
        Sources:
        - Auto (default): -Credential when passed; else the environment variables
          <NAME>_USERNAME and <NAME>_PASSWORD (for example CLUSTER_ADMIN_USERNAME and
          CLUSTER_ADMIN_PASSWORD); else Key Vault when keyvault-config.yml maps
          <name>_password (or <name>). When none has a value the call throws a
          message that says what to pass or set.
        - Parameter: the -Credential passed by the caller.
        - Environment: <NAME>_USERNAME and <NAME>_PASSWORD.
        - KeyVault: the secrets mapped in keyvault-config.yml.
    .PARAMETER Name
        Logical credential name (for example "cluster_admin"). Alias: CredentialName.
    .PARAMETER Source
        Credential source: Auto, KeyVault, Environment, Parameter. Default: Auto.
    .PARAMETER Credential
        Pre-built PSCredential (used by Auto and Parameter).
    .PARAMETER Username
        Username to pair with the secret (Environment and KeyVault sources).
    .PARAMETER VaultConfigPath
        Path to keyvault-config.yml.
    .PARAMETER ProjectRoot
        Repository root used to find the default keyvault-config.yml.
    .EXAMPLE
        $cred = Get-ManagedCredential -Name 'cluster_admin'
    .EXAMPLE
        $cred = Get-ManagedCredential -Name 'cluster_admin' -Source KeyVault
    .EXAMPLE
        $cred = Get-ManagedCredential -Name 'cluster_admin' -Source Parameter -Credential $myCred
    #>
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory)]
        [Alias('CredentialName')]
        [string]$Name,

        [Parameter()]
        [ValidateSet('Auto', 'KeyVault', 'Environment', 'Parameter')]
        [string]$Source = 'Auto',

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$Username,

        [Parameter()]
        [string]$VaultConfigPath,

        [Parameter()]
        [string]$ProjectRoot
    )

    Write-Verbose "Retrieving credential '$Name' from source: $Source"

    $base = $Name -replace '_password$', ''
    $envBase = ConvertTo-EnvironmentName -Name $base
    $envUserName = "${envBase}_USERNAME"
    $envPasswordName = "${envBase}_PASSWORD"

    if ($Source -eq 'Auto') {
        if ($Credential) {
            $Source = 'Parameter'
        } elseif ([System.Environment]::GetEnvironmentVariable($envPasswordName) -and
            ($Username -or [System.Environment]::GetEnvironmentVariable($envUserName))) {
            $Source = 'Environment'
        } elseif (Get-VaultSecretName -Key @("${base}_password", $Name) -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot) {
            $Source = 'KeyVault'
        } else {
            throw (Get-MissingCredentialMessage -Name $Name -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot)
        }
        Write-Verbose "Credential '$Name' resolved to source: $Source"
    }

    switch ($Source) {
        'Parameter' {
            if (-not $Credential) {
                throw "No credential passed for '$Name'. Pass -Credential when using -Source Parameter."
            }
            return $Credential
        }

        'Environment' {
            $password = [System.Environment]::GetEnvironmentVariable($envPasswordName)
            $user = if ($Username) { $Username } else { [System.Environment]::GetEnvironmentVariable($envUserName) }
            if (-not $password -or -not $user) {
                throw "No credential found for '$Name' in the environment. Set $envUserName and $envPasswordName (or pass -Username with $envPasswordName)."
            }
            $securePassword = [System.Security.SecureString]::new()
            foreach ($ch in $password.ToCharArray()) { $securePassword.AppendChar($ch) }
            $securePassword.MakeReadOnly()
            return [PSCredential]::new($user, $securePassword)
        }

        'KeyVault' {
            return Get-KeyVaultCredential -Name $Name -Username $Username -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot
        }
    }
}

function Get-KeyVaultCredential {
    <#
    .SYNOPSIS
        Retrieves a credential from Azure Key Vault.
    .PARAMETER Name
        Logical credential name. The password secret is mapped as <name>_password (or <name>),
        the username secret as <name>_username, under keyvault.secrets in keyvault-config.yml.
    .PARAMETER Username
        Username to pair with the retrieved secret.
    .PARAMETER VaultConfigPath
        Path to keyvault-config.yml.
    .PARAMETER ProjectRoot
        Repository root used to find the default keyvault-config.yml.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The secret is read from Key Vault at run time and converted once to a SecureString for the PSCredential; it is never stored in a file.')]
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Username,

        [Parameter()]
        [string]$VaultConfigPath,

        [Parameter()]
        [string]$ProjectRoot
    )

    $vaultConfig = Import-VaultConfig -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot

    if (-not $vaultConfig.name) {
        throw "Key Vault name not configured: set keyvault.name in keyvault-config.yml."
    }

    $base = $Name -replace '_password$', ''
    $secretName = $null
    foreach ($k in @("${base}_password", $Name)) {
        if ($vaultConfig.secrets -and $vaultConfig.secrets[$k]) { $secretName = $vaultConfig.secrets[$k]; break }
    }
    if (-not $secretName) {
        throw "No Key Vault secret mapping found for credential '$Name': map '${base}_password' under keyvault.secrets in keyvault-config.yml."
    }

    Write-Verbose "Retrieving secret '$secretName' from Key Vault '$($vaultConfig.name)'"
    $secret = Invoke-VaultSecretRead -VaultName $vaultConfig.name -SecretName $secretName

    if (-not $Username) {
        # No built-in user name: a guessed account would fail late or log on as the wrong identity.
        $usernameSecretName = if ($vaultConfig.secrets) { $vaultConfig.secrets["${base}_username"] } else { $null }
        if (-not $usernameSecretName) {
            throw "No user name for credential '$Name': pass -Username, or map '${base}_username' under keyvault.secrets in keyvault-config.yml."
        }
        $Username = Invoke-VaultSecretRead -VaultName $vaultConfig.name -SecretName $usernameSecretName
        if (-not $Username) {
            throw "The Key Vault secret '$usernameSecretName' (user name of credential '$Name') is empty."
        }
    }

    $securePassword = ConvertTo-SecureString -String $secret -AsPlainText -Force
    $credential = [PSCredential]::new($Username, $securePassword)

    Write-Verbose "Successfully retrieved credential for '$Name' from Key Vault"
    return $credential
}

function Get-ManagedSecret {
    <#
    .SYNOPSIS
        Retrieves a single secret value (not a full credential). Never prompts.
    .DESCRIPTION
        For non-credential secrets such as API keys or a user name.
        - Auto (default): -Value when passed; else the environment variable
          (-EnvironmentVariable, or the name in upper case, for example LOG_ANALYTICS_KEY);
          else Key Vault when keyvault-config.yml maps the name. When none has a value
          the call throws a message that says what to pass or set.
        - Parameter, Environment, KeyVault: that source only.
    .PARAMETER Name
        Logical secret name mapped in keyvault-config.yml. Alias: SecretName.
    .PARAMETER Source
        Secret source: Auto, KeyVault, Environment, Parameter. Default: Auto.
    .PARAMETER Value
        Direct value (used by Auto and Parameter).
    .PARAMETER EnvironmentVariable
        Name of the environment variable. Default: the secret name in upper case.
    .PARAMETER VaultConfigPath
        Path to keyvault-config.yml.
    .PARAMETER ProjectRoot
        Repository root used to find the default keyvault-config.yml.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [Alias('SecretName')]
        [string]$Name,

        [Parameter()]
        [ValidateSet('Auto', 'KeyVault', 'Environment', 'Parameter')]
        [string]$Source = 'Auto',

        [Parameter()]
        [string]$Value,

        [Parameter()]
        [string]$EnvironmentVariable,

        [Parameter()]
        [string]$VaultConfigPath,

        [Parameter()]
        [string]$ProjectRoot
    )

    $envVarName = if ($EnvironmentVariable) { $EnvironmentVariable } else { ConvertTo-EnvironmentName -Name $Name }

    if ($Source -eq 'Auto') {
        if ($Value) {
            $Source = 'Parameter'
        } elseif ([System.Environment]::GetEnvironmentVariable($envVarName)) {
            $Source = 'Environment'
        } elseif (Get-VaultSecretName -Key $Name -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot) {
            $Source = 'KeyVault'
        } else {
            $path = Get-VaultConfigPath -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot
            throw "No value found for secret '$Name'. Pass it as a parameter, set the environment variable $envVarName, or map '$Name' under keyvault.secrets in $path."
        }
    }

    switch ($Source) {
        'Parameter' {
            if (-not $Value) {
                throw "No value passed for secret '$Name'. Pass -Value when using -Source Parameter."
            }
            return $Value
        }

        'Environment' {
            $envValue = [System.Environment]::GetEnvironmentVariable($envVarName)
            if (-not $envValue) {
                throw "Environment variable '$envVarName' is not set (secret '$Name')."
            }
            return $envValue
        }

        'KeyVault' {
            $vaultConfig = Import-VaultConfig -VaultConfigPath $VaultConfigPath -ProjectRoot $ProjectRoot
            if (-not $vaultConfig.name) {
                throw "Key Vault name not configured: set keyvault.name in keyvault-config.yml."
            }
            $secretName = if ($vaultConfig.secrets) { $vaultConfig.secrets[$Name] } else { $null }
            if (-not $secretName) {
                throw "No Key Vault secret mapping found for '$Name': map it under keyvault.secrets in keyvault-config.yml."
            }
            return Invoke-VaultSecretRead -VaultName $vaultConfig.name -SecretName $secretName
        }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ManagedCredential'
    'Get-ManagedSecret'
    'Import-VaultConfig'
)
