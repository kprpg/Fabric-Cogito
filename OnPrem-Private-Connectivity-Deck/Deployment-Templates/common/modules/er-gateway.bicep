// ExpressRoute gateway (zone-redundant). Optionally connects to an existing circuit.
// Without a circuit the gateway still deploys; it is the "dry run" hub for a later circuit.
param name string
param location string
param tags object = {}
param gatewaySubnetId string
param sku string = 'ErGw1AZ'
param zones array = [ '1', '2', '3' ]
param circuitResourceId string = ''
@secure()
param circuitAuthorizationKey string = ''
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
    gatewayType: 'ExpressRoute'
    sku: {
      name: sku
      tier: sku
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

resource conn 'Microsoft.Network/connections@2024-05-01' = if (!empty(circuitResourceId)) {
  name: 'cn-${name}'
  location: location
  tags: tags
  properties: {
    connectionType: 'ExpressRoute'
    virtualNetworkGateway1: {
      id: gw.id
      properties: {}
    }
    peer: {
      id: circuitResourceId
    }
    authorizationKey: empty(circuitAuthorizationKey) ? null : circuitAuthorizationKey
    routingWeight: 0
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
