// =============================================================================
// keyvault.bicep - Azure Local Load Tools
// =============================================================================
// Deploys an Azure Key Vault for storing credentials used by load test scripts.
// =============================================================================

@description('Name of the Key Vault')
param keyVaultName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Object ID of the security principal for access policies')
param adminObjectId string

@description('Tenant ID')
param tenantId string = subscription().tenantId

@description('Tags for resource organization')
param tags object = {
  project: 'azurelocal-loadtools'
  purpose: 'load-testing'
}

@description('Enable soft delete')
param enableSoftDelete bool = true

@description('Soft delete retention days')
param softDeleteRetentionInDays int = 7

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enableRbacAuthorization: true
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: adminObjectId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
            'delete'
          ]
        }
      }
    ]
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Pre-populate secret placeholders (values set manually or via CI)
resource clusterAdminUsername 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'cluster-admin-username'
  properties: {
    value: 'REPLACE_WITH_ACTUAL_USERNAME'
    contentType: 'text/plain'
  }
}

resource clusterAdminPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'cluster-admin-password'
  properties: {
    value: 'REPLACE_WITH_ACTUAL_PASSWORD'
    contentType: 'text/plain'
  }
}

resource logAnalyticsKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'log-analytics-key'
  properties: {
    value: 'REPLACE_WITH_ACTUAL_KEY'
    contentType: 'text/plain'
  }
}

@description('Key Vault resource ID')
output keyVaultId string = keyVault.id

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri
