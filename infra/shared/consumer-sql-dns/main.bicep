targetScope = 'resourceGroup'

@description('Exact SQL hostname from the provider-generated guestTenantId + privateLinkType=Workspace connection string. No protocol, port, or database.')
@minLength(1)
param sqlServerFqdn string
@description('SQL member private IPv4 address verified from the approved workspace private endpoint NIC. Do not use an arbitrary first IP.')
@minLength(7)
param sqlPrivateIp string
param virtualNetworkId string
param tags object = {}

// A host-specific zone avoids guessing Fabric CNAMEs or shadowing an entire shared SQL DNS suffix.
resource sqlDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: sqlServerFqdn
  location: 'global'
  tags: tags
}

resource sqlRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: sqlDns
  name: '@'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: sqlPrivateIp
      }
    ]
  }
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: sqlDns
  name: 'sql-client-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

output sqlServerFqdn string = sqlDns.name
