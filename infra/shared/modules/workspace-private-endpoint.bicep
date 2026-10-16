targetScope = 'resourceGroup'

param namePrefix string
param location string
param subnetId string
param vnetId string
@minLength(1)
@description('Epic-owned Microsoft.Fabric/privateLinkServicesForFabric resource ID, not a workspace GUID or Microsoft.Network/privateLinkServices ID.')
param providerPrivateLinkServiceId string
param tags object

resource endpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${namePrefix}-epic-workspace-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    manualPrivateLinkServiceConnections: [
      {
        name: 'epic-approval-required'
        properties: {
          privateLinkServiceId: providerPrivateLinkServiceId
          groupIds: [
            'workspace'
          ]
          requestMessage: 'Customer requests access to the agreed Cogito workspace. Provider approval and separate data authorization required.'
        }
      }
    ]
  }
}

resource fabricDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.fabric.microsoft.com'
  location: 'global'
  tags: tags
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: fabricDns
  name: '${namePrefix}-fabric-dns'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: endpoint
  name: 'fabric'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'fabric'
        properties: {
          privateDnsZoneId: fabricDns.id
        }
      }
    ]
  }
}

output endpointId string = endpoint.id
output dnsZoneId string = fabricDns.id
output dnsHandoff string = 'After Epic approves, inspect the endpoint DNS configuration. Deploy shared/consumer-sql-dns only with the actual guest-specific SQL hostname and the verified SQL member IP.'
