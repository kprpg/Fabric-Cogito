// Generic virtual network. Each subnet object supports:
//   name, addressPrefix (required)
//   nsgId, natGatewayId, delegation, privateLinkServiceNetworkPolicies (optional)
param name string
param location string
param tags object = {}
param addressPrefixes array
param subnets array
param dnsServers array = []

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    dhcpOptions: empty(dnsServers) ? null : {
      dnsServers: dnsServers
    }
    subnets: [for s in subnets: {
      name: s.name
      properties: {
        addressPrefix: s.addressPrefix
        networkSecurityGroup: s.?nsgId != null ? { id: s.nsgId } : null
        natGateway: s.?natGatewayId != null ? { id: s.natGatewayId } : null
        delegations: s.?delegation != null ? [
          {
            name: 'delegation'
            properties: {
              serviceName: s.delegation
            }
          }
        ] : []
        privateLinkServiceNetworkPolicies: s.?privateLinkServiceNetworkPolicies ?? 'Enabled'
      }
    }]
  }
}

output id string = vnet.id
output name string = vnet.name
output subnetIds object = toObject(subnets, s => s.name, s => '${vnet.id}/subnets/${s.name}')
