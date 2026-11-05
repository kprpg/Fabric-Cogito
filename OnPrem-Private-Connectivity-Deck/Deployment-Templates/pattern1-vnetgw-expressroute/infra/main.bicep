// Pattern 1 - VNet data gateway over ExpressRoute (hub & spoke).
// ExpressRoute is frequently not authorized in lab subscriptions, so hybridLinkMode=simulatedVpn (default)
// builds the identical hub-and-spoke topology and uses a BGP-enabled VPN gateway as the ExpressRoute stand-in.
// Set hybridLinkMode=expressRoute to deploy a real ExpressRoute gateway (and optionally connect a circuit).
//
// Deployment order: resource groups -> governance -> network + simulated on-prem -> hybrid link -> Fabric capacity.
targetScope = 'subscription'

import { regionShortNames } from '../../common/modules/shared.bicep'

param location string = 'eastus2'
param environment string = 'dev'
param workload string = 'fabcn'

@allowed([ 'simulatedVpn', 'expressRoute' ])
param hybridLinkMode string = 'simulatedVpn'
@description('Deploy the simulated on-premises site (VNet + Hyper-V/SQL host that appears non-Azure).')
param deployOnPremSite bool = true
param expressRouteCircuitId string = ''
@secure()
param expressRouteAuthorizationKey string = ''

param adminUsername string = 'azureadmin'
@secure()
param adminPassword string
@secure()
param sqlPassword string
@secure()
param vpnSharedKey string
@description('Entra UPNs that administer the Fabric capacity.')
param fabricAdminUpns array
param fabricSku string = 'F2'
param hostVmSize string = 'Standard_D4s_v5'
param deployerPrincipalId string = ''
param kvUseAccessPolicies bool = false
@description('Set false when re-deploying after the host guest agent has been disabled.')
param runBootstrap bool = true
param deployDnsResolver bool = true
param deployTestVm bool = true
param deployBastionDeveloper bool = true
param onboardToArc bool = true
@secure()
param arcAccessToken string = ''
param extraTags object = {}

// ---- Address plan (no overlap across any pattern; see docs/02-ip-addressing-and-naming.md) ----
var hubCidr = '10.10.0.0/22'
var hubGatewaySubnet = '10.10.0.0/26'
var hubDnsOutSubnet = '10.10.0.64/28'
var spokeCidr = '10.10.4.0/22'
var spokeVnetGwSubnet = '10.10.4.0/27'
var spokeTestSubnet = '10.10.4.32/27'
var onpremCidr = '10.110.0.0/16'
var onpremGatewaySubnet = '10.110.0.0/27'
var onpremLanSubnet = '10.110.1.0/24'
var onpremHostIp = '10.110.1.4'
var onpremNestedLan = '10.110.2.0/24'
var onpremNestedLanGw = '10.110.2.1'
var azureAsn = 65010
var onpremAsn = 65110
var onpremZone = 'corp.contoso.lab'

var locShort = regionShortNames[?location] ?? take(location, 6)
var pattern = 'p1'
var suffix = '${workload}-${pattern}'
var tail = '${environment}-${locShort}'
var uniq = uniqueString(subscription().id, workload, pattern, environment, location)
var tags = union({
  workload: workload
  pattern: 'p1-vnetgw-expressroute'
  environment: environment
  purpose: 'Fabric private connectivity demo'
  'managed-by': 'bicep'
}, extraTags)

var useVpn = hybridLinkMode == 'simulatedVpn'
var linkSite = useVpn && deployOnPremSite

resource rgNet 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${suffix}-net-${tail}'
  location: location
  tags: tags
}

resource rgOnprem 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${suffix}-onprem-${tail}'
  location: location
  tags: tags
}

resource rgGov 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${suffix}-gov-${tail}'
  location: location
  tags: tags
}

resource rgFabric 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${suffix}-fabric-${tail}'
  location: location
  tags: tags
}

// ---- 1. Governance ----
module gov '../../common/modules/governance.bicep' = {
  name: 'gov-${suffix}'
  scope: rgGov
  params: {
    location: location
    tags: tags
    logAnalyticsName: 'log-${suffix}-${tail}'
    keyVaultName: 'kv-${suffix}-${environment}-${take(uniq, 5)}'
    storageAccountName: 'st${workload}${pattern}${environment}${take(uniq, 6)}'
    deployerPrincipalId: deployerPrincipalId
    useAccessPolicies: kvUseAccessPolicies
    adminPassword: adminPassword
    sqlPassword: sqlPassword
    vpnSharedKey: vpnSharedKey
  }
}

// ---- 2. Network (hub & spoke) ----
module nsgVnetGw '../../common/modules/nsg.bicep' = {
  name: 'nsg-${suffix}-vnetgw'
  scope: rgNet
  params: {
    name: 'nsg-${suffix}-vnetgw-${tail}'
    location: location
    tags: tags
    rules: [
      {
        name: 'Allow-SQL-To-OnPrem'
        priority: 100
        direction: 'Outbound'
        access: 'Allow'
        protocol: 'Tcp'
        src: [ spokeVnetGwSubnet ]
        dst: [ onpremCidr ]
        ports: [ '1433' ]
      }
      {
        name: 'Allow-Intra-Subnet'
        priority: 110
        direction: 'Inbound'
        access: 'Allow'
        protocol: '*'
        src: [ spokeVnetGwSubnet ]
        dst: [ spokeVnetGwSubnet ]
        ports: [ '*' ]
      }
    ]
  }
}

module nsgTest '../../common/modules/nsg.bicep' = {
  name: 'nsg-${suffix}-test'
  scope: rgNet
  params: {
    name: 'nsg-${suffix}-test-${tail}'
    location: location
    tags: tags
    rules: []
  }
}

module natSpoke '../../common/modules/nat-gateway.bicep' = {
  name: 'nat-${suffix}-spoke'
  scope: rgNet
  params: {
    name: 'ng-${suffix}-spoke-${tail}'
    location: location
    tags: tags
  }
}

module hubVnet '../../common/modules/vnet.bicep' = {
  name: 'vnet-${suffix}-hub'
  scope: rgNet
  params: {
    name: 'vnet-${suffix}-hub-${tail}'
    location: location
    tags: tags
    addressPrefixes: [ hubCidr ]
    subnets: [
      {
        name: 'GatewaySubnet'
        addressPrefix: hubGatewaySubnet
      }
      {
        name: 'snet-dns-out'
        addressPrefix: hubDnsOutSubnet
        delegation: 'Microsoft.Network/dnsResolvers'
      }
    ]
  }
}

module spokeVnet '../../common/modules/vnet.bicep' = {
  name: 'vnet-${suffix}-spoke'
  scope: rgNet
  params: {
    name: 'vnet-${suffix}-spoke-${tail}'
    location: location
    tags: tags
    addressPrefixes: [ spokeCidr ]
    subnets: [
      {
        // Delegated to the Power Platform VNet data gateway; must not be named GatewaySubnet/AzureBastionSubnet.
        name: 'snet-vnetgw'
        addressPrefix: spokeVnetGwSubnet
        delegation: 'Microsoft.PowerPlatform/vnetaccesslinks'
        nsgId: nsgVnetGw.outputs.id
        natGatewayId: natSpoke.outputs.id
      }
      {
        name: 'snet-test'
        addressPrefix: spokeTestSubnet
        nsgId: nsgTest.outputs.id
      }
    ]
  }
}

// ---- 3. Simulated on-premises site ----
module onprem '../../common/modules/onprem-site.bicep' = if (deployOnPremSite) {
  name: 'onprem-${suffix}'
  scope: rgOnprem
  params: {
    location: location
    tags: tags
    suffix: suffix
    tail: tail
    computerName: 'p1-onprem-sql'
    addressSpace: onpremCidr
    gatewaySubnetPrefix: onpremGatewaySubnet
    lanSubnetPrefix: onpremLanSubnet
    hostPrivateIp: onpremHostIp
    nestedLanPrefix: onpremNestedLan
    nestedLanGatewayIp: onpremNestedLanGw
    azureSideCidrs: [ hubCidr, spokeCidr ]
    deployVpnDevice: linkSite
    vpnDeviceAsn: onpremAsn
    logAnalyticsWorkspaceId: gov.outputs.logAnalyticsWorkspaceId
    deployBastionDeveloper: deployBastionDeveloper
    hostVmSize: hostVmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    sqlPassword: sqlPassword
    dnsZoneName: onpremZone
    runBootstrap: runBootstrap
    onboardToArc: onboardToArc
    arcAccessToken: arcAccessToken
  }
}

// ---- 4. Hybrid link (ExpressRoute stand-in or real ExpressRoute) ----
module hubVpnGw '../../common/modules/vpn-gateway.bicep' = if (useVpn) {
  name: 'vgw-${suffix}-hub'
  scope: rgNet
  params: {
    name: 'vgw-${suffix}-hub-${tail}'
    location: location
    tags: union(tags, { simulates: 'ExpressRoute private peering' })
    gatewaySubnetId: hubVnet.outputs.subnetIds.GatewaySubnet
    asn: azureAsn
    logAnalyticsWorkspaceId: gov.outputs.logAnalyticsWorkspaceId
  }
}

module hubErGw '../../common/modules/er-gateway.bicep' = if (!useVpn) {
  name: 'ergw-${suffix}-hub'
  scope: rgNet
  params: {
    name: 'ergw-${suffix}-hub-${tail}'
    location: location
    tags: tags
    gatewaySubnetId: hubVnet.outputs.subnetIds.GatewaySubnet
    circuitResourceId: expressRouteCircuitId
    circuitAuthorizationKey: expressRouteAuthorizationKey
    logAnalyticsWorkspaceId: gov.outputs.logAnalyticsWorkspaceId
  }
}

module connHub '../../common/modules/s2s-connection.bicep' = if (linkSite) {
  name: 'cn-${suffix}-hub-to-onprem'
  scope: rgNet
  params: {
    location: location
    tags: tags
    localGatewayName: 'lgw-${suffix}-onprem-${tail}'
    connectionName: 'cn-${suffix}-hub-to-onprem-${tail}'
    virtualNetworkGatewayId: hubVpnGw!.outputs.id
    remoteGatewayPublicIp: onprem!.outputs.vpnDevicePublicIp
    remoteAsn: onpremAsn
    remoteBgpPeeringAddress: onprem!.outputs.vpnDeviceBgpIp
    sharedKey: vpnSharedKey
  }
}

module connOnprem '../../common/modules/s2s-connection.bicep' = if (linkSite) {
  name: 'cn-${suffix}-onprem-to-hub'
  scope: rgOnprem
  params: {
    location: location
    tags: tags
    localGatewayName: 'lgw-${suffix}-hub-${tail}'
    connectionName: 'cn-${suffix}-onprem-to-hub-${tail}'
    virtualNetworkGatewayId: onprem!.outputs.vpnDeviceId
    remoteGatewayPublicIp: hubVpnGw!.outputs.publicIp
    remoteAsn: azureAsn
    remoteBgpPeeringAddress: hubVpnGw!.outputs.bgpPeeringAddress
    sharedKey: vpnSharedKey
  }
}

// Spoke uses the hub gateway (gateway transit) - requires the gateway to exist first.
module peering '../../common/modules/vnet-peering.bicep' = {
  name: 'peer-${suffix}'
  scope: rgNet
  params: {
    hubVnetName: hubVnet.outputs.name
    spokeVnetName: spokeVnet.outputs.name
    hubVnetId: hubVnet.outputs.id
    spokeVnetId: spokeVnet.outputs.id
    hubHasGateway: true
  }
  dependsOn: [
    hubVpnGw
    hubErGw
  ]
}

module dns '../../common/modules/dns-resolver.bicep' = if (deployDnsResolver && deployOnPremSite) {
  name: 'dns-${suffix}'
  scope: rgNet
  params: {
    name: 'dnspr-${suffix}-${tail}'
    location: location
    tags: tags
    vnetId: hubVnet.outputs.id
    outboundSubnetId: hubVnet.outputs.subnetIds['snet-dns-out']
    forwardingRules: [
      {
        name: 'onprem-corp'
        domain: '${onpremZone}.'
        targets: [ onpremHostIp ]
      }
    ]
    linkedVnetIds: [ spokeVnet.outputs.id ]
  }
  dependsOn: [
    peering
  ]
}

module testVm '../../common/modules/test-client.bicep' = if (deployTestVm) {
  name: 'vm-${suffix}-test'
  scope: rgNet
  params: {
    name: 'vm-${suffix}-test-${tail}'
    location: location
    tags: tags
    subnetId: spokeVnet.outputs.subnetIds['snet-test']
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// ---- 5. Fabric capacity (last) ----
module fabric '../../common/modules/fabric-capacity.bicep' = {
  name: 'fabric-${suffix}'
  scope: rgFabric
  params: {
    name: 'fc${workload}${pattern}${environment}${locShort}'
    location: location
    tags: tags
    skuName: fabricSku
    adminMembers: fabricAdminUpns
  }
  dependsOn: [
    gov
    peering
    onprem
  ]
}

output pattern string = 'p1-vnetgw-expressroute'
output hybridLinkMode string = hybridLinkMode
output resourceGroups object = {
  net: rgNet.name
  onprem: rgOnprem.name
  gov: rgGov.name
  fabric: rgFabric.name
}
output vnetGatewayTarget object = {
  subscriptionId: subscription().subscriptionId
  resourceGroup: rgNet.name
  virtualNetwork: spokeVnet.outputs.name
  delegatedSubnet: 'snet-vnetgw'
  delegation: 'Microsoft.PowerPlatform/vnetaccesslinks'
}
output onpremSqlFqdn string = 'sql01.${onpremZone}'
output onpremSqlIp string = onpremHostIp
output onpremHostVm string = deployOnPremSite ? onprem!.outputs.hostName : ''
output onpremArcMachine string = deployOnPremSite ? onprem!.outputs.arcResourceName : ''
output testVm string = deployTestVm ? testVm!.outputs.name : ''
output vpnConnectionHub string = linkSite ? 'cn-${suffix}-hub-to-onprem-${tail}' : ''
output fabricCapacity string = fabric.outputs.name
output keyVault string = gov.outputs.keyVaultName
output logAnalytics string = gov.outputs.logAnalyticsWorkspaceId
