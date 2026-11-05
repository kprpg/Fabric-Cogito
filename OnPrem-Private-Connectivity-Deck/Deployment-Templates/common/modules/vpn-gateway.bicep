// Route-based, BGP-enabled, zone-redundant VPN gateway (active-passive).
// Used both as the Azure-side hybrid gateway and as the simulated on-premises VPN device.
param name string
param location string
param tags object = {}
param gatewaySubnetId string
param sku string = 'VpnGw1AZ'
param asn int
param zones array = [ '1', '2', '3' ]
param logAnalyticsWorkspaceId string = ''

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  zones: zones
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource gw 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation1'
    sku: {
      name: sku
      tier: sku
    }
    enableBgp: true
    activeActive: false
    bgpSettings: {
      asn: asn
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          publicIPAddress: {
            id: pip.id
          }
          subnet: {
            id: gatewaySubnetId
          }
        }
      }
    ]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-to-law'
  scope: gw
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = gw.id
output name string = gw.name
output publicIp string = pip.properties.ipAddress
output asn int = asn
output bgpPeeringAddress string = gw.properties.bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]
