// Network security group. Each rule: name, priority, direction, access, protocol, src[], dst[], ports[]
param name string
param location string
param tags object = {}
param rules array = []

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    securityRules: [for r in rules: {
      name: r.name
      properties: {
        priority: r.priority
        direction: r.direction
        access: r.access
        protocol: r.protocol
        sourcePortRange: '*'
        sourceAddressPrefix: length(r.src) == 1 ? r.src[0] : null
        sourceAddressPrefixes: length(r.src) > 1 ? r.src : null
        destinationAddressPrefix: length(r.dst) == 1 ? r.dst[0] : null
        destinationAddressPrefixes: length(r.dst) > 1 ? r.dst : null
        destinationPortRange: length(r.ports) == 1 ? r.ports[0] : null
        destinationPortRanges: length(r.ports) > 1 ? r.ports : null
      }
    }]
  }
}

output id string = nsg.id
