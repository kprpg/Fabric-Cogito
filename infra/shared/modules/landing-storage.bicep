targetScope = 'resourceGroup'

param namePrefix string
param location string
param subnetId string
param vnetId string
param logAnalyticsWorkspaceId string
param dataPrincipalId string = ''
param tags object

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${take(namePrefix, 10)}${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
  }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

resource landing 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'landing'
  properties: {
    publicAccess: 'None'
  }
}

var services = [
  {
    group: 'blob'
    zone: 'privatelink.blob.${environment().suffixes.storage}'
  }
  {
    group: 'dfs'
    zone: 'privatelink.dfs.${environment().suffixes.storage}'
  }
]

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for service in services: {
    name: service.zone
    location: 'global'
    tags: tags
  }
]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (service, i) in services: {
    parent: zones[i]
    name: '${namePrefix}-${service.group}-dns'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetId
      }
    }
  }
]

@batchSize(1)
resource endpoints 'Microsoft.Network/privateEndpoints@2024-05-01' = [
  for service in services: {
    name: '${namePrefix}-${service.group}-pe'
    location: location
    tags: tags
    properties: {
      subnet: {
        id: subnetId
      }
      privateLinkServiceConnections: [
        {
          name: service.group
          properties: {
            privateLinkServiceId: storage.id
            groupIds: [
              service.group
            ]
          }
        }
      ]
    }
  }
]

resource zoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = [
  for (service, i) in services: {
    parent: endpoints[i]
    name: 'storage'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: service.group
          properties: {
            privateDnsZoneId: zones[i].id
          }
        }
      ]
    }
  }
]

resource dataWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(dataPrincipalId)) {
  name: guid(landing.id, dataPrincipalId, 'Storage Blob Data Contributor')
  scope: landing
  properties: {
    principalId: dataPrincipalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalType: 'ServicePrincipal'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: blob
  name: 'central-logs'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output storageId string = storage.id
output dfsEndpoint string = storage.properties.primaryEndpoints.dfs
output containerName string = landing.name
