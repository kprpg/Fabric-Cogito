// Governance & shared services for one pattern: Log Analytics, Key Vault (RBAC), ADLS Gen2 storage.
// Deployed BEFORE network and Fabric so that diagnostics and secrets have a home.
param location string
param tags object = {}
param logAnalyticsName string
param keyVaultName string
param storageAccountName string
param deployerPrincipalId string = ''
@description('Use vault access policies instead of Azure RBAC (needed when the deployer cannot create role assignments).')
param useAccessPolicies bool = false
@secure()
param adminPassword string
@secure()
param sqlPassword string
@secure()
param vpnSharedKey string = ''

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: !useAccessPolicies
    accessPolicies: useAccessPolicies && !empty(deployerPrincipalId) ? [
      {
        tenantId: tenant().tenantId
        objectId: deployerPrincipalId
        permissions: {
          secrets: [ 'get', 'list', 'set', 'delete' ]
        }
      }
    ] : []
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

resource secretAdmin 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'vm-admin-password'
  properties: {
    value: adminPassword
  }
}

resource secretSql 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'sql-fabricsvc-password'
  properties: {
    value: sqlPassword
  }
}

resource secretVpn 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(vpnSharedKey)) {
  parent: kv
  name: 'vpn-shared-key'
  properties: {
    value: vpnSharedKey
  }
}

resource kvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!useAccessPolicies && !empty(deployerPrincipalId)) {
  name: guid(kv.id, deployerPrincipalId, 'kv-secrets-officer')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: deployerPrincipalId
  }
}

resource kvDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: kv
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
  }
}

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: st
  name: 'default'
}

resource landing 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'landing'
}

output logAnalyticsWorkspaceId string = law.id
output keyVaultName string = kv.name
output keyVaultId string = kv.id
output storageAccountName string = st.name
