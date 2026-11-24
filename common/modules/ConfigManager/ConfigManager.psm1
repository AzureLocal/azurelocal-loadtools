# =============================================================================
# ConfigManager Module - Azure Local Load Tools
# =============================================================================
# Manages configuration pipeline: reads variables.yml, filters by
# solution tag, generates solution-specific JSON files, and provides the
# override chain for variable resolution.
# =============================================================================

#Requires -Modules powershell-yaml

# Cluster facts (the cluster, its nodes, the domain, the CSV, the Azure scope, the Key Vault) are not defined here: they
# come from the environment's infrastructure.yml (azurelocal-toolkit schema 5). variables.yml holds the test settings only.

# Module-level variables
$script:MasterConfig = $null
$script:MasterConfigLoadedFrom = $null
$script:SolutionConfigs = @{}
$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

function Import-MasterConfig {
    <#
    .SYNOPSIS
        Loads the master environment configuration from YAML.
    .DESCRIPTION
        Reads and parses the variables.yml file. Validates structure
        against expected schema. Caches the result for subsequent calls.
    .PARAMETER MasterConfigPath
        Path to variables.yml. Defaults to config/variables/variables.yml.
    .PARAMETER Force
        Force reload even if already cached.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$MasterConfigPath,

        [Parameter()]
        [switch]$Force
    )

    if (-not $MasterConfigPath) {
        $MasterConfigPath = Join-Path $script:ProjectRoot 'config\variables\variables.yml'
    }

    # Always validate the requested path first: a cached config must never mask a bad path.
    if (-not (Test-Path $MasterConfigPath)) {
        throw "Master environment file not found: $MasterConfigPath"
    }

    $resolvedPath = (Resolve-Path $MasterConfigPath).Path
    if ($script:MasterConfig -and -not $Force -and $script:MasterConfigLoadedFrom -eq $resolvedPath) {
        Write-Verbose "Master config already loaded from this path. Use -Force to reload."
        return $script:MasterConfig
    }

    Write-Verbose "Loading master configuration from: $MasterConfigPath"
    $yamlContent = Get-Content -Path $MasterConfigPath -Raw
    $script:MasterConfig = ConvertFrom-Yaml $yamlContent
    $script:MasterConfigLoadedFrom = $resolvedPath

    # Validate basic structure
    if (-not $script:MasterConfig.metadata) {
        throw "Master config missing 'metadata' section"
    }
    if (-not $script:MasterConfig.variables) {
        throw "Master config missing 'variables' section"
    }

    Write-Verbose "Loaded $($script:MasterConfig.variables.Count) variables from master config v$($script:MasterConfig.metadata.version)"
    return $script:MasterConfig
}

function Get-InfrastructureValue {
    # One value of the parsed infrastructure file by dotted path ('cluster.name'); $null when a key on the way is missing.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Data, [Parameter(Mandatory)][string]$Path)
    $node = $Data
    foreach ($segment in $Path -split '\.') {
        if ($node -is [System.Collections.IDictionary] -and $node.Contains($segment)) { $node = $node[$segment] } else { return $null }
    }
    return $node
}

function Import-InfrastructureConfig {
    <#
    .SYNOPSIS
        Reads the cluster facts Load Tools needs from the environment's infrastructure.yml (azurelocal-toolkit, schema 5).
    .DESCRIPTION
        The one source of the cluster facts. The file is the full infrastructure.yml or its loadtools cut
        (New-InfrastructureArtifacts.ps1 -Cut loadtools, _metadata.scope loadtools). Keys read:
          cluster.name                              -> cluster_name
          nodes[].name                              -> cluster_nodes
          identity.active_directory.domain_fqdn     -> cluster_domain (empty for a local identity design)
          storage.paths[].path (else storage.volumes[].name) -> csv_path: the first cluster shared volume,
                                                       C:\ClusterStorage\<volume>
          azure.tenant_id, subscription_id, resource_group, location -> azure_tenant_id, azure_subscription_id,
                                                       azure_resource_group, azure_location
          key_vaults[].name (purpose management, else the first; else cluster.key_vault.name) -> keyvault_name
          azure.custom_location, storage.paths[].name (the first) -> azure_custom_location_id, storage_path_id: the
                                                       ARM resource IDs Prepare-VMFleetBaseImage.ps1 needs, built with
                                                       the subscription and resource group above
        Returns Source, Values (the names above, as the solution configs use them) and ClusterConfig (the parsed file with
        cluster.domain and storage.csv_path filled in, the shape the tool scripts read through -ClusterConfigPath).
    .PARAMETER InfrastructureFile
        Path to infrastructure.yml.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$InfrastructureFile)

    if (-not (Test-Path -LiteralPath $InfrastructureFile -PathType Leaf)) { throw "Infrastructure file not found: $InfrastructureFile" }
    $data = ConvertFrom-Yaml (Get-Content -LiteralPath $InfrastructureFile -Raw)
    $version = [string](Get-InfrastructureValue -Data $data -Path '_metadata.schema_version')
    if ($version -notmatch '^5(\.|$)') { throw "$InfrastructureFile is not an infrastructure.yml of schema 5 (_metadata.schema_version is '$version')." }

    $name = [string](Get-InfrastructureValue -Data $data -Path 'cluster.name')
    $nodes = @(@(Get-InfrastructureValue -Data $data -Path 'nodes') | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['name'] } | ForEach-Object { [string]$_['name'] })
    $problems = @()
    if (-not $name) { $problems += 'cluster.name' }
    if ($nodes.Count -eq 0) { $problems += 'nodes[].name' }
    if ($problems.Count) { throw "$InfrastructureFile has no $($problems -join ' and '): Load Tools needs the cluster and its nodes." }

    $domain = [string](Get-InfrastructureValue -Data $data -Path 'identity.active_directory.domain_fqdn')

    # The first cluster shared volume: the root of the first storage path, else the first volume of storage.volumes.
    $csv = ''
    foreach ($entry in @(Get-InfrastructureValue -Data $data -Path 'storage.paths')) {
        if ($entry -is [System.Collections.IDictionary] -and [string]$entry['path'] -match '^(?<root>[A-Za-z]:\\ClusterStorage\\[^\\]+)') { $csv = $Matches['root']; break }
    }
    if (-not $csv) {
        foreach ($entry in @(Get-InfrastructureValue -Data $data -Path 'storage.volumes')) {
            if ($entry -is [System.Collections.IDictionary] -and $entry['name']) { $csv = "C:\ClusterStorage\$([string]$entry['name'])"; break }
        }
    }

    $vaults = @(@(Get-InfrastructureValue -Data $data -Path 'key_vaults') | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['name'] })
    $vault = @($vaults | Where-Object { [string]$_['purpose'] -eq 'management' } | Select-Object -First 1)
    if (-not $vault) { $vault = @($vaults | Select-Object -First 1) }
    $vaultName = if ($vault) { [string]$vault[0]['name'] } else { [string](Get-InfrastructureValue -Data $data -Path 'cluster.key_vault.name') }

    $values = [ordered]@{
        cluster_name          = $name
        cluster_domain        = $domain
        cluster_nodes         = $nodes
        csv_path              = $csv
        azure_tenant_id       = [string](Get-InfrastructureValue -Data $data -Path 'azure.tenant_id')
        azure_subscription_id = [string](Get-InfrastructureValue -Data $data -Path 'azure.subscription_id')
        azure_resource_group  = [string](Get-InfrastructureValue -Data $data -Path 'azure.resource_group')
        azure_location        = [string](Get-InfrastructureValue -Data $data -Path 'azure.location')
        keyvault_name         = $vaultName
    }
    $scope = "/subscriptions/$($values.azure_subscription_id)/resourceGroups/$($values.azure_resource_group)"
    $customLocation = [string](Get-InfrastructureValue -Data $data -Path 'azure.custom_location')
    $storagePath = @(@(Get-InfrastructureValue -Data $data -Path 'storage.paths') | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['name'] } | Select-Object -First 1)
    $values['azure_custom_location_id'] = if ($customLocation -and $values.azure_subscription_id -and $values.azure_resource_group) { "$scope/providers/Microsoft.ExtendedLocation/customLocations/$customLocation" } else { '' }
    $values['storage_path_id'] = if ($storagePath -and $values.azure_subscription_id -and $values.azure_resource_group) { "$scope/providers/Microsoft.AzureStackHCI/storageContainers/$([string]$storagePath[0]['name'])" } else { '' }

    # The shape the tool scripts read: cluster.name, cluster.domain, nodes[].name and storage.csv_path.
    if ($data['cluster'] -isnot [System.Collections.IDictionary]) { $data['cluster'] = @{} }
    if ($domain -and -not $data['cluster']['domain']) { $data['cluster']['domain'] = $domain }
    if ($csv) {
        if ($data['storage'] -isnot [System.Collections.IDictionary]) { $data['storage'] = @{} }
        if (-not $data['storage']['csv_path']) { $data['storage']['csv_path'] = $csv }
    }
    return [pscustomobject]@{ Source = (Resolve-Path -LiteralPath $InfrastructureFile).Path; Values = $values; ClusterConfig = $data }
}

function Import-ClusterConfig {
    <#
    .SYNOPSIS
        Reads the cluster file a tool script is given (-ClusterConfigPath): the environment's infrastructure.yml, or a
        per-cluster file of the earlier layout.
    .DESCRIPTION
        An infrastructure.yml (_metadata.schema_version 5.x) is read with Import-InfrastructureConfig and returned in the
        shape the scripts use (cluster.name, cluster.domain, nodes[].name, storage.csv_path). Any other file is parsed as it
        is, with a warning: the per-cluster file is replaced by infrastructure.yml, which holds the same facts once for
        every tool.
    .PARAMETER Path
        Path to the file.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Cluster config not found: $Path" }
    $data = ConvertFrom-Yaml (Get-Content -LiteralPath $Path -Raw)
    if ($data -is [System.Collections.IDictionary] -and $data.Contains('_metadata') -and $data['_metadata'] -is [System.Collections.IDictionary] -and $data['_metadata'].Contains('schema_version')) {
        return (Import-InfrastructureConfig -InfrastructureFile $Path).ClusterConfig
    }
    Write-Warning "$Path is a per-cluster file of the earlier layout. Give the environment's infrastructure.yml (-ClusterConfigPath or -InfrastructureFile) instead: it holds the cluster, nodes, domain, volumes, Azure scope and Key Vault once for every tool."
    return $data
}

function Export-SolutionConfig {
    <#
    .SYNOPSIS
        Generates a solution-specific JSON config from the master environment.
    .DESCRIPTION
        Filters variables from variables.yml by solution tag and writes
        a flat JSON file containing only the variables relevant to the specified solution.
    .PARAMETER Solution
        Solution name to filter for: vmfleet, fio, iperf, hammerdb, stress-ng.
    .PARAMETER MasterConfigPath
        Path to variables.yml.
    .PARAMETER OutputPath
        Output path for the generated JSON file.
    .PARAMETER ClusterConfigPath
        Optional cluster config to merge cluster-specific values. An infrastructure.yml is read as with -InfrastructureFile.
    .PARAMETER InfrastructureFile
        The environment's infrastructure.yml. Its cluster facts (cluster_name, cluster_domain, cluster_nodes, csv_path,
        azure_*, keyvault_name; see Import-InfrastructureConfig) are written to the solution JSON. variables.yml does not
        define them.
    .EXAMPLE
        Export-SolutionConfig -Solution "vmfleet" -InfrastructureFile ./infrastructure.yml
    .EXAMPLE
        Export-SolutionConfig -Solution "vmfleet"
    .EXAMPLE
        Export-SolutionConfig -Solution "fio" -OutputPath ".\my-fio-config.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('vmfleet', 'fio', 'iperf', 'hammerdb', 'stress-ng')]
        [string]$Solution,

        [Parameter()]
        [string]$MasterConfigPath,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [string]$ClusterConfigPath,

        [Parameter()]
        [string]$InfrastructureFile
    )

    # Load master config
    $masterConfig = Import-MasterConfig -MasterConfigPath $MasterConfigPath

    if (-not $OutputPath) {
        $OutputPath = Join-Path $script:ProjectRoot "config\variables\solutions\$Solution.json"
    }

    # Filter variables by solution tag
    $solutionVars = $masterConfig.variables | Where-Object {
        $_.solutions -contains $Solution
    }

    Write-Verbose "Found $($solutionVars.Count) variables tagged for solution: $Solution"

    # Build flat key-value object
    $configObject = [ordered]@{
        '_metadata' = [ordered]@{
            'solution'       = $Solution
            'generated_from' = 'config/variables/variables.yml'
            'generated_at'   = (Get-Date -Format 'o')
            'description'    = "$Solution-specific configuration (auto-generated by ConfigManager)"
        }
    }

    foreach ($var in $solutionVars) {
        # Skip sensitive variables — they should come from Key Vault at runtime
        if ($var.sensitive -eq $true) {
            $configObject[$var.name] = ''
        } else {
            $configObject[$var.name] = $var.value
        }
    }

    # The cluster facts come from the infrastructure file (-InfrastructureFile, or -ClusterConfigPath when it is one). Each
    # fact goes to the solutions that use it; a per-cluster file of the earlier layout is still merged, with a warning.
    $factSolutions = @{
        cluster_name = '*'; cluster_domain = '*'; cluster_nodes = '*'; csv_path = @('vmfleet', 'fio')
        azure_tenant_id = '*'; azure_subscription_id = '*'; azure_resource_group = '*'; azure_location = '*'; keyvault_name = '*'
        azure_custom_location_id = @('vmfleet'); storage_path_id = @('vmfleet')
    }
    $facts = $null
    if ($InfrastructureFile) {
        Write-Verbose "Reading cluster facts from: $InfrastructureFile"
        $facts = (Import-InfrastructureConfig -InfrastructureFile $InfrastructureFile).Values
    }
    elseif ($ClusterConfigPath -and (Test-Path $ClusterConfigPath)) {
        Write-Verbose "Merging cluster config from: $ClusterConfigPath"
        $clusterConfig = Import-ClusterConfig -Path $ClusterConfigPath
        $domain = if ($clusterConfig.cluster) { $clusterConfig.cluster.domain } else { $null }
        $csvPath = if ($clusterConfig.storage -and $clusterConfig.storage.csv_path) { $clusterConfig.storage.csv_path } elseif ($clusterConfig.cluster) { $clusterConfig.cluster.csv_path } else { $null }
        $facts = [ordered]@{
            cluster_name   = if ($clusterConfig.cluster) { $clusterConfig.cluster.name } else { $null }
            cluster_domain = $domain
            cluster_nodes  = @($clusterConfig.nodes | ForEach-Object { $_.name })
            csv_path       = $csvPath
        }
    }
    if ($facts) {
        foreach ($key in $facts.Keys) {
            $applies = $factSolutions[$key] -eq '*' -or $Solution -in @($factSolutions[$key])
            if ($applies -and $facts[$key]) { $configObject[$key] = $facts[$key] }
        }
    }

    # Ensure output directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Write JSON
    $jsonContent = $configObject | ConvertTo-Json -Depth 10
    Set-Content -Path $OutputPath -Value $jsonContent -Encoding UTF8

    Write-Verbose "Solution config written to: $OutputPath"

    # Cache the solution config
    $script:SolutionConfigs[$Solution] = $configObject

    return $OutputPath
}

function Get-ConfigValue {
    <#
    .SYNOPSIS
        Retrieves a configuration value with override chain support.
    .DESCRIPTION
        Resolves a variable value using the three-level override chain:
        1. Explicit override (highest priority)
        2. Solution JSON file
        3. Master environment default (lowest priority)
    .PARAMETER Name
        Variable name to retrieve (snake_case).
    .PARAMETER Solution
        Solution context for filtering (e.g., "vmfleet").
    .PARAMETER Override
        Explicit override value (highest priority in the chain).
    .PARAMETER DefaultValue
        Fallback if variable not found in any source.
    .PARAMETER SolutionConfigPath
        Path to the solution JSON file. Auto-resolved if not specified.
    .EXAMPLE
        Get-ConfigValue -Name "vm_count_per_node" -Solution "vmfleet"
    .EXAMPLE
        Get-ConfigValue -Name "vm_count_per_node" -Solution "vmfleet" -Override 20
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Solution,

        [Parameter()]
        $Override,

        [Parameter()]
        $DefaultValue,

        [Parameter()]
        [string]$SolutionConfigPath
    )

    # Level 1: Explicit override wins
    if ($PSBoundParameters.ContainsKey('Override') -and $null -ne $Override) {
        Write-Verbose "Config '$Name': using explicit override value"
        return $Override
    }

    # Level 2: Solution JSON
    if ($Solution) {
        if (-not $SolutionConfigPath) {
            $SolutionConfigPath = Join-Path $script:ProjectRoot "config\variables\solutions\$Solution.json"
        }

        if (Test-Path $SolutionConfigPath) {
            $solutionConfig = Get-Content -Path $SolutionConfigPath -Raw | ConvertFrom-Json -AsHashtable
            if ($solutionConfig.ContainsKey($Name) -and $solutionConfig[$Name] -ne '' -and $null -ne $solutionConfig[$Name]) {
                Write-Verbose "Config '$Name': using value from $Solution.json"
                return $solutionConfig[$Name]
            }
        }
    }

    # Level 3: Master environment default
    $masterConfig = Import-MasterConfig
    $variable = $masterConfig.variables | Where-Object { $_.name -eq $Name } | Select-Object -First 1

    if ($variable -and $null -ne $variable.value -and $variable.value -ne '') {
        Write-Verbose "Config '$Name': using master environment default"
        return $variable.value
    }

    # Fallback
    if ($PSBoundParameters.ContainsKey('DefaultValue')) {
        Write-Verbose "Config '$Name': using provided default value"
        return $DefaultValue
    }

    Write-Warning "Config '$Name': no value found in any source"
    return $null
}

function Test-MasterConfig {
    <#
    .SYNOPSIS
        Validates the master environment configuration.
    .DESCRIPTION
        Checks the variables.yml for structural correctness,
        required fields, and valid solution tags.
    .PARAMETER MasterConfigPath
        Path to variables.yml.
    .OUTPUTS
        PSCustomObject with IsValid (bool) and Errors (string[]) properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$MasterConfigPath
    )

    $errors = @()

    try {
        $config = Import-MasterConfig -MasterConfigPath $MasterConfigPath -Force
    } catch {
        return [PSCustomObject]@{
            IsValid = $false
            Errors  = @("Failed to load master config: $($_.Exception.Message)")
        }
    }

    $validSolutions = @('vmfleet', 'fio', 'iperf', 'hammerdb', 'stress-ng')
    $validTypes = @('string', 'integer', 'boolean', 'array')
    $namesSeen = @{}

    foreach ($var in $config.variables) {
        # Check required fields
        if (-not $var.name) { $errors += "Variable missing 'name' field" }
        if (-not $var.description) { $errors += "Variable '$($var.name)' missing 'description'" }
        if (-not $var.type) { $errors += "Variable '$($var.name)' missing 'type'" }
        if (-not $var.solutions -or $var.solutions.Count -eq 0) {
            $errors += "Variable '$($var.name)' has no solution tags"
        }

        # Check for duplicates
        if ($var.name -and $namesSeen.ContainsKey($var.name)) {
            $errors += "Duplicate variable name: '$($var.name)'"
        }
        $namesSeen[$var.name] = $true

        # Validate type
        if ($var.type -and $var.type -notin $validTypes) {
            $errors += "Variable '$($var.name)' has invalid type: '$($var.type)'"
        }

        # Validate solution tags
        if ($var.solutions) {
            foreach ($sol in $var.solutions) {
                if ($sol -notin $validSolutions) {
                    $errors += "Variable '$($var.name)' has invalid solution tag: '$sol'"
                }
            }
        }
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors  = $errors
    }
}

function Export-AllSolutionConfigs {
    <#
    .SYNOPSIS
        Generates JSON config files for all solutions.
    .PARAMETER MasterConfigPath
        Path to variables.yml.
    .PARAMETER ClusterConfigPath
        Optional cluster config to merge.
    .PARAMETER InfrastructureFile
        The environment's infrastructure.yml: the source of the cluster facts (see Export-SolutionConfig).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$MasterConfigPath,

        [Parameter()]
        [string]$ClusterConfigPath,

        [Parameter()]
        [string]$InfrastructureFile
    )

    $solutions = @('vmfleet', 'fio', 'iperf', 'hammerdb', 'stress-ng')

    foreach ($solution in $solutions) {
        Write-Verbose "Generating config for: $solution"
        Export-SolutionConfig -Solution $solution -MasterConfigPath $MasterConfigPath -ClusterConfigPath $ClusterConfigPath -InfrastructureFile $InfrastructureFile
    }

    Write-Verbose "All solution configs generated successfully"
}

# Export module members
Export-ModuleMember -Function @(
    'Import-MasterConfig'
    'Export-SolutionConfig'
    'Export-AllSolutionConfigs'
    'Get-ConfigValue'
    'Test-MasterConfig'
    'Import-InfrastructureConfig'
    'Import-ClusterConfig'
)
