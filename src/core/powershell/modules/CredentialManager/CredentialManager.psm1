# =============================================================================
# CredentialManager Module - Azure Local Load Tools
# =============================================================================
# Dual-mode credential retrieval: Azure Key Vault, interactive prompt, or
# direct parameter injection. Ensures credentials are never hardcoded.
# =============================================================================

# Module-level variables
$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$script:VaultConfig = $null

function Import-VaultConfig {
    <#
    .SYNOPSIS
        Loads the Key Vault configuration from YAML.
    .PARAMETER VaultConfigPath
        Path to keyvault-config.yml. Defaults to config/credentials/keyvault-config.yml.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$VaultConfigPath
    )

    if (-not $VaultConfigPath) {
        $VaultConfigPath = Join-Path $script:ProjectRoot 'config\credentials\keyvault-config.yml'
    }

    if (-not (Test-Path $VaultConfigPath)) {
        throw "Key Vault config not found: $VaultConfigPath. Required for KeyVault credential source."
    }

    $yamlContent = Get-Content -Path $VaultConfigPath -Raw
    $script:VaultConfig = (ConvertFrom-Yaml $yamlContent).keyvault

    return $script:VaultConfig
}

function Get-ManagedCredential {
    <#
    .SYNOPSIS
        Retrieves credentials from the configured source.
    .DESCRIPTION
        Supports three credential retrieval modes:
        - KeyVault: Retrieves secrets from Azure Key Vault
        - Interactive: Prompts the user with Get-Credential
        - Parameter: Expects credential passed directly
    .PARAMETER Name
        Logical credential name (e.g., "cluster_admin_password").
    .PARAMETER Source
        Credential source: KeyVault, Interactive, Parameter.
    .PARAMETER Credential
        Pre-built PSCredential (used with -Source Parameter).
    .PARAMETER Username
        Username for the credential (used with KeyVault and Interactive sources).
    .PARAMETER VaultConfigPath
        Path to keyvault-config.yml.
    .PARAMETER Prompt
        Custom prompt message for interactive mode.
    .EXAMPLE
        $cred = Get-ManagedCredential -Name "cluster_admin" -Source Interactive
    .EXAMPLE
        $cred = Get-ManagedCredential -Name "cluster_admin" -Source KeyVault
    .EXAMPLE
        $cred = Get-ManagedCredential -Name "cluster_admin" -Source Parameter -Credential $myCred
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('KeyVault', 'Interactive', 'Parameter')]
        [string]$Source = 'Interactive',

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$Username,

        [Parameter()]
        [string]$VaultConfigPath,

        [Parameter()]
        [string]$Prompt
    )

    Write-Verbose "Retrieving credential '$Name' from source: $Source"

    switch ($Source) {
        'Parameter' {
            if (-not $Credential) {
                throw "Credential parameter is required when using -Source Parameter"
            }
            Write-Verbose "Using directly provided credential for '$Name'"
            return $Credential
        }

        'Interactive' {
            $promptMessage = $Prompt ?? "Enter credentials for: $Name"
            if ($Username) {
                $cred = Get-Credential -UserName $Username -Message $promptMessage
            }
            else {
                $cred = Get-Credential -Message $promptMessage
            }

            if (-not $cred) {
                throw "No credential provided for '$Name'"
            }
            return $cred
        }

        'KeyVault' {
            return Get-KeyVaultCredential -Name $Name -Username $Username -VaultConfigPath $VaultConfigPath
        }
    }
}

function Get-KeyVaultCredential {
    <#
    .SYNOPSIS
        Retrieves a credential from Azure Key Vault.
    .PARAMETER Name
        Logical credential name mapped in keyvault-config.yml.
    .PARAMETER Username
        Username to pair with the retrieved secret.
    .PARAMETER VaultConfigPath
        Path to keyvault-config.yml.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Username,

        [Parameter()]
        [string]$VaultConfigPath
    )

    # Ensure Az.KeyVault is available
    if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
        throw "Az.KeyVault module is required for Key Vault credential retrieval. Install with: Install-Module Az.KeyVault"
    }

    Import-Module Az.KeyVault -ErrorAction Stop

    # Load vault config
    $vaultConfig = Import-VaultConfig -VaultConfigPath $VaultConfigPath

    if (-not $vaultConfig.name) {
        throw "Key Vault name not configured in keyvault-config.yml"
    }

    # Map logical name to secret name
    $secretName = $vaultConfig.secrets.$Name
    if (-not $secretName) {
        throw "No Key Vault secret mapping found for credential '$Name' in keyvault-config.yml"
    }

    Write-Verbose "Retrieving secret '$secretName' from Key Vault '$($vaultConfig.name)'"

    try {
        $secret = Get-AzKeyVaultSecret -VaultName $vaultConfig.name -Name $secretName -AsPlainText
    }
    catch {
        throw "Failed to retrieve secret '$secretName' from Key Vault '$($vaultConfig.name)': $($_.Exception.Message)"
    }

    # If username is mapped, retrieve it too
    if (-not $Username) {
        $usernameKey = $Name -replace '_password$', '_username'
        $usernameSecretName = $vaultConfig.secrets.$usernameKey
        if ($usernameSecretName) {
            try {
                $Username = Get-AzKeyVaultSecret -VaultName $vaultConfig.name -Name $usernameSecretName -AsPlainText
            }
            catch {
                Write-Warning "Could not retrieve username secret '$usernameSecretName'. Defaulting to 'Administrator'."
                $Username = 'Administrator'
            }
        }
        else {
            $Username = 'Administrator'
        }
    }

    # Build PSCredential
    $securePassword = ConvertTo-SecureString -String $secret -AsPlainText -Force
    $credential = [PSCredential]::new($Username, $securePassword)

    Write-Verbose "Successfully retrieved credential for '$Name' (username: $Username)"
    return $credential
}

function Get-ManagedSecret {
    <#
    .SYNOPSIS
        Retrieves a single secret value (not a full credential) from the configured source.
    .DESCRIPTION
        For retrieving non-credential secrets like API keys, connection strings, etc.
    .PARAMETER Name
        Logical secret name mapped in keyvault-config.yml.
    .PARAMETER Source
        Secret source: KeyVault, Interactive, Parameter, Environment.
    .PARAMETER Value
        Direct value (used with -Source Parameter).
    .PARAMETER EnvironmentVariable
        Name of environment variable (used with -Source Environment).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('KeyVault', 'Interactive', 'Parameter', 'Environment')]
        [string]$Source = 'Interactive',

        [Parameter()]
        [string]$Value,

        [Parameter()]
        [string]$EnvironmentVariable
    )

    switch ($Source) {
        'Parameter' {
            if (-not $Value) {
                throw "Value parameter is required when using -Source Parameter"
            }
            return $Value
        }

        'Environment' {
            $envVarName = $EnvironmentVariable ?? $Name.ToUpper()
            $envValue = [System.Environment]::GetEnvironmentVariable($envVarName)
            if (-not $envValue) {
                throw "Environment variable '$envVarName' not set"
            }
            return $envValue
        }

        'Interactive' {
            $secureValue = Read-Host -Prompt "Enter value for '$Name'" -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
            try {
                return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }

        'KeyVault' {
            $vaultConfig = Import-VaultConfig
            $secretName = $vaultConfig.secrets.$Name
            if (-not $secretName) {
                throw "No Key Vault secret mapping found for '$Name'"
            }
            Import-Module Az.KeyVault -ErrorAction Stop
            return Get-AzKeyVaultSecret -VaultName $vaultConfig.name -Name $secretName -AsPlainText
        }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ManagedCredential'
    'Get-ManagedSecret'
    'Import-VaultConfig'
)
