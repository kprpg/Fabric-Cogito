// One side of a BGP-enabled IPsec/IKEv2 site-to-site tunnel: local network gateway (the peer) + connection.
// Deploy once in each resource group; the two sides share the same pre-shared key.
param location string
param tags object = {}
param localGatewayName string
param connectionName string
param virtualNetworkGatewayId string
param remoteGatewayPublicIp string
param remoteAsn int
param remoteBgpPeeringAddress string
@secure()
param sharedKey string

resource lgw 'Microsoft.Network/localNetworkGateways@2024-05-01' = {
  name: localGatewayName
  location: location
  tags: tags
  properties: {
    gatewayIpAddress: remoteGatewayPublicIp
    localNetworkAddressSpace: {
      addressPrefixes: [
        '${remoteBgpPeeringAddress}/32'
      ]
    }
    bgpSettings: {
      asn: remoteAsn
      bgpPeeringAddress: remoteBgpPeeringAddress
    }
  }
}

resource conn 'Microsoft.Network/connections@2024-05-01' = {
  name: connectionName
  location: location
  tags: tags
  properties: {
    connectionType: 'IPsec'
    connectionProtocol: 'IKEv2'
    virtualNetworkGateway1: {
      id: virtualNetworkGatewayId
      properties: {}
    }
    localNetworkGateway2: {
      id: lgw.id
      properties: {}
    }
    sharedKey: sharedKey
    enableBgp: true
    routingWeight: 10
  }
}

output connectionName string = conn.name
