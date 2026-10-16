targetScope = 'resourceGroup'

import { environmentSettings, fabricSettings } from './types.bicep'

param environment environmentSettings
@secure()
param adminPassword string
param publicSql bool
param customerFabric bool
param providerPrivateLinkServiceId string = ''
param fabric fabricSettings?

var tags = union(environment.tags, {
  architecture: customerFabric ? 'customer-fabric' : 'azure-client'
  sqlTransport: publicSql ? 'public-tds' : 'workspace-private-link'
})

module monitoring './modules/monitoring.bicep' = {
  name: '${environment.namePrefix}-monitoring'
  params: {
    namePrefix: environment.namePrefix
    location: environment.location
    tags: tags
  }
}

module network './modules/network.bicep' = {
  name: '${environment.namePrefix}-network'
  params: {
    namePrefix: environment.namePrefix
    location: environment.location
    addressPrefix: environment.vnetAddressPrefix
    publicSql: publicSql
    httpsAllowedFqdns: environment.httpsAllowedFqdns
    sqlServiceTags: environment.sqlServiceTags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: tags
  }
}

module client './modules/client.bicep' = {
  name: '${environment.namePrefix}-client'
  params: {
    namePrefix: environment.namePrefix
    location: environment.location
    subnetId: network.outputs.workloadSubnetId
    dnsServerIp: network.outputs.dnsProxyIp
    adminUsername: environment.adminUsername
    adminPassword: adminPassword
    vmSize: environment.vmSize
    tags: tags
  }
}

module epicEndpoint './modules/workspace-private-endpoint.bicep' = if (!publicSql) {
  name: '${environment.namePrefix}-epic-endpoint'
  params: {
    namePrefix: environment.namePrefix
    location: environment.location
    subnetId: network.outputs.endpointSubnetId
    vnetId: network.outputs.vnetId
    providerPrivateLinkServiceId: providerPrivateLinkServiceId
    tags: tags
  }
}

module capacity './modules/fabric-capacity.bicep' = if (customerFabric) {
  name: '${environment.namePrefix}-capacity'
  params: {
    namePrefix: environment.namePrefix
    location: environment.location
    sku: fabric!.sku
    administrators: fabric!.administrators
    tags: tags
  }
}

module storage './modules/landing-storage.bicep' = if (customerFabric) {
  name: '${environment.namePrefix}-landing'
  params: {
    namePrefix: environment.namePrefix
    location: environment.location
    subnetId: network.outputs.endpointSubnetId
    vnetId: network.outputs.vnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    dataPrincipalId: fabric!.landingDataPrincipalId
    tags: tags
  }
  dependsOn: [
    epicEndpoint
  ]
}

output connections object = {
  virtualNetworkId: network.outputs.vnetId
  clientVirtualMachineId: client.outputs.vmId
  clientPrivateIp: client.outputs.privateIp
  bastionId: network.outputs.bastionId
  egressPublicIp: network.outputs.egressPublicIp
  logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  providerPrivateEndpointId: publicSql ? '' : epicEndpoint!.outputs.endpointId
  customerCapacityId: customerFabric ? capacity!.outputs.capacityId : ''
  customerCapacityName: customerFabric ? capacity!.outputs.capacityName : ''
  landingStorageId: customerFabric ? storage!.outputs.storageId : ''
  landingDfsEndpoint: customerFabric ? storage!.outputs.dfsEndpoint : ''
}
