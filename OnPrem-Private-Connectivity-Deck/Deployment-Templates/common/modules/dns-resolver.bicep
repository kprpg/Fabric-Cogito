// Azure DNS Private Resolver (outbound only) that forwards the on-prem zone to the on-prem DNS server.
// The VNet data gateway uses VNet DNS (Azure DNS), so linking the ruleset to its VNet is enough.
param name string
param location string
param tags object = {}
param vnetId string
param outboundSubnetId string
param forwardingRules array = []
param linkedVnetIds array

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource outbound 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = {
  parent: resolver
  name: 'outbound'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: outboundSubnetId
    }
  }
}

resource ruleset 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = {
  name: '${name}-rules'
  location: location
  tags: tags
  properties: {
    dnsResolverOutboundEndpoints: [
      {
        id: outbound.id
      }
    ]
  }
}

resource rules 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = [for r in forwardingRules: {
  parent: ruleset
  name: r.name
  properties: {
    domainName: r.domain
    forwardingRuleState: 'Enabled'
    targetDnsServers: [for ip in r.targets: {
      ipAddress: ip
      port: 53
    }]
  }
}]

resource links 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = [for (id, i) in linkedVnetIds: {
  parent: ruleset
  name: 'link-${i}'
  properties: {
    virtualNetwork: {
      id: id
    }
  }
}]

output resolverId string = resolver.id
