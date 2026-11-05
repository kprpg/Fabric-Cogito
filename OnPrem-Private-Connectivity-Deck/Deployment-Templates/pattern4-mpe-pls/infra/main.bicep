// Pattern 4 - Fabric managed private endpoint + Private Link Service in front of the hybrid network.
// Fabric Spark/Eventstream -> (Fabric managed VNet) -> managed private endpoint -> your PLS -> internal Standard LB
// -> NAT forwarder VMs (DNAT 1433) -> hybrid link -> on-prem SQL Server.
// hybridLinkMode follows Pattern 1: simulatedVpn (default, ExpressRoute stand-in) or expressRoute.
//
// Deployment order: resource groups -> governance -> network + simulated on-prem -> hybrid link -> LB/forwarders/PLS -> Fabric capacity.
// After deployment run common/scripts/Fabric-Configure.ps1 -Pattern 4 to create the workspace + managed private endpoint
// and approve the pending connection on the PLS.
targetScope = 'subscription'

import { regionShortNames } from '../../common/modules/shared.bicep'

param location string = 'eastus2'
param environment string = 'dev'
param workload string = 'fabcn'

@allowed([ 'simulatedVpn', 'expressRoute' ])
param hybridLinkMode string = 'simulatedVpn'
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
param fabricAdminUpns array
param fabricSku string = 'F2'
param hostVmSize string = 'Standard_D4s_v5'
param forwarderCount int = 2
@description('Subscriptions allowed to see/request the PLS. Approval stays manual; tighten once the Fabric requester is known.')
param plsVisibilitySubscriptions array = [ '*' ]
param plsAutoApprovalSubscriptions array = []
param deployerPrincipalId string = ''
param kvUseAccessPolicies bool = false
param runBootstrap bool = true
param deployTestVm bool = true
param deployBastionDeveloper bool = true
param onboardToArc bool = true
@secure()
param arcAccessToken string = ''
param extraTags object = {}

// ---- Address plan ----
var azureCidr = '10.40.0.0/16'
var azureGatewaySubnet = '10.40.0.0/26'
var plsNatSubnet = '10.40.1.0/27'
var forwarderSubnet = '10.40.2.0/27'
var lbFrontendIp = '10.40.2.10'
var azureTestSubnet = '10.40.3.0/27'
var onpremCidr = '10.140.0.0/16'
var onpremGatewaySubnet = '10.140.0.0/27'
var onpremLanSubnet = '10.140.1.0/24'
var onpremHostIp = '10.140.1.4'
var onpremNestedLan = '10.140.2.0/24'
var onpremNestedLanGw = '10.140.2.1'
var azureAsn = 65040
var onpremAsn = 65140
var onpremZone = 'corp.contoso.lab'

var locShort = regionShortNames[?location] ?? take(location, 6)
var pattern = 'p4'
var suffix = '${workload}-${pattern}'
var tail = '${environment}-${locShort}'
var uniq = uniqueString(subscription().id, workload, pattern, environment, location)
var tags = union({
  workload: workload
  pattern: 'p4-mpe-pls'
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

// ---- 2. Network ----
module nsgForwarder '../../common/modules/nsg.bicep' = {
  name: 'nsg-${suffix}-fwd'
  scope: rgNet
  params: {
    name: 'nsg-${suffix}-fwd-${tail}'
    location: location
    tags: tags
    rules: [
      {
        name: 'Allow-SQL-From-PLS-NAT-And-Test'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        src: [ plsNatSubnet, azureTestSubnet ]
        dst: [ forwarderSubnet ]
        ports: [ '1433' ]
      }
      {
        name: 'Allow-LB-Probe'
        priority: 110
        direction: 'Inbound'
        access: 'Allow'
        protocol: '*'
        src: [ 'AzureLoadBalancer' ]
        dst: [ '*' ]
        ports: [ '*' ]
      }
      {
        name: 'Deny-All-Other-Inbound'
        priority: 4000
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        src: [ '*' ]
        dst: [ '*' ]
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

module vnet '../../common/modules/vnet.bicep' = {
  name: 'vnet-${suffix}-pls'
  scope: rgNet
  params: {
    name: 'vnet-${suffix}-pls-${tail}'
    location: location
    tags: tags
    addressPrefixes: [ azureCidr ]
    subnets: [
      {
        name: 'GatewaySubnet'
        addressPrefix: azureGatewaySubnet
      }
      {
        // PLS NAT IPs: network policies for Private Link Service must be disabled on this subnet.
        name: 'snet-pls-nat'
        addressPrefix: plsNatSubnet
        privateLinkServiceNetworkPolicies: 'Disabled'
      }
      {
        name: 'snet-fwd'
        addressPrefix: forwarderSubnet
        nsgId: nsgForwarder.outputs.id
      }
      {
        name: 'snet-test'
        addressPrefix: azureTestSubnet
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
    computerName: 'p4-onprem-sql'
    addressSpace: onpremCidr
    gatewaySubnetPrefix: onpremGatewaySubnet
    lanSubnetPrefix: onpremLanSubnet
    hostPrivateIp: onpremHostIp
    nestedLanPrefix: onpremNestedLan
    nestedLanGatewayIp: onpremNestedLanGw
    azureSideCidrs: [ forwarderSubnet, azureTestSubnet ]
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

// ---- 4. Hybrid link ----
module vpnGw '../../common/modules/vpn-gateway.bicep' = if (useVpn) {
  name: 'vgw-${suffix}-azure'
  scope: rgNet
  params: {
    name: 'vgw-${suffix}-azure-${tail}'
    location: location
    tags: union(tags, { simulates: 'ExpressRoute private peering' })
    gatewaySubnetId: vnet.outputs.subnetIds.GatewaySubnet
    asn: azureAsn
    logAnalyticsWorkspaceId: gov.outputs.logAnalyticsWorkspaceId
  }
}

module erGw '../../common/modules/er-gateway.bicep' = if (!useVpn) {
  name: 'ergw-${suffix}-azure'
  scope: rgNet
  params: {
    name: 'ergw-${suffix}-azure-${tail}'
    location: location
    tags: tags
    gatewaySubnetId: vnet.outputs.subnetIds.GatewaySubnet
    circuitResourceId: expressRouteCircuitId
    circuitAuthorizationKey: expressRouteAuthorizationKey
    logAnalyticsWorkspaceId: gov.outputs.logAnalyticsWorkspaceId
  }
}

module connAzure '../../common/modules/s2s-connection.bicep' = if (linkSite) {
  name: 'cn-${suffix}-azure-to-onprem'
  scope: rgNet
  params: {
    location: location
    tags: tags
    localGatewayName: 'lgw-${suffix}-onprem-${tail}'
    connectionName: 'cn-${suffix}-azure-to-onprem-${tail}'
    virtualNetworkGatewayId: vpnGw!.outputs.id
    remoteGatewayPublicIp: onprem!.outputs.vpnDevicePublicIp
    remoteAsn: onpremAsn
    remoteBgpPeeringAddress: onprem!.outputs.vpnDeviceBgpIp
    sharedKey: vpnSharedKey
  }
}

module connOnprem '../../common/modules/s2s-connection.bicep' = if (linkSite) {
  name: 'cn-${suffix}-onprem-to-azure'
  scope: rgOnprem
  params: {
    location: location
    tags: tags
    localGatewayName: 'lgw-${suffix}-azure-${tail}'
    connectionName: 'cn-${suffix}-onprem-to-azure-${tail}'
    virtualNetworkGatewayId: onprem!.outputs.vpnDeviceId
    remoteGatewayPublicIp: vpnGw!.outputs.publicIp
    remoteAsn: azureAsn
    remoteBgpPeeringAddress: vpnGw!.outputs.bgpPeeringAddress
    sharedKey: vpnSharedKey
  }
}

// ---- 5. Internal LB + NAT forwarders + Private Link Service ----
module pls '../../common/modules/private-link-service.bicep' = {
  name: 'pls-${suffix}'
  scope: rgNet
  params: {
    location: location
    tags: tags
    lbName: 'lbi-${suffix}-sql-${tail}'
    plsName: 'pls-${suffix}-sql-${tail}'
    forwarderNamePrefix: 'vm-${suffix}-fwd'
    forwarderSubnetId: vnet.outputs.subnetIds['snet-fwd']
    plsNatSubnetId: vnet.outputs.subnetIds['snet-pls-nat']
    lbFrontendIp: lbFrontendIp
    targetIp: onpremHostIp
    forwarderCount: forwarderCount
    adminUsername: adminUsername
    adminPassword: adminPassword
    plsVisibilitySubscriptions: plsVisibilitySubscriptions
    plsAutoApprovalSubscriptions: plsAutoApprovalSubscriptions
    logAnalyticsWorkspaceId: gov.outputs.logAnalyticsWorkspaceId
  }
  dependsOn: [
    connAzure
    connOnprem
    erGw
  ]
}

module testVm '../../common/modules/test-client.bicep' = if (deployTestVm) {
  name: 'vm-${suffix}-test'
  scope: rgNet
  params: {
    name: 'vm-${suffix}-test-${tail}'
    location: location
    tags: tags
    subnetId: vnet.outputs.subnetIds['snet-test']
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// ---- 6. Fabric capacity (last; managed private endpoints require an F SKU or Trial) ----
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
    pls
    onprem
  ]
}

output pattern string = 'p4-mpe-pls'
output hybridLinkMode string = hybridLinkMode
output resourceGroups object = {
  net: rgNet.name
  onprem: rgOnprem.name
  gov: rgGov.name
  fabric: rgFabric.name
}
output privateLinkService object = {
  id: pls.outputs.plsId
  name: pls.outputs.plsName
  alias: pls.outputs.plsAlias
  resourceGroup: rgNet.name
}
output lbFrontendIp string = lbFrontendIp
output onpremSqlFqdn string = 'sql01.${onpremZone}'
output onpremSqlIp string = onpremHostIp
output onpremHostVm string = deployOnPremSite ? onprem!.outputs.hostName : ''
output onpremArcMachine string = deployOnPremSite ? onprem!.outputs.arcResourceName : ''
output testVm string = deployTestVm ? testVm!.outputs.name : ''
output vpnConnectionHub string = linkSite ? 'cn-${suffix}-azure-to-onprem-${tail}' : ''
output fabricCapacity string = fabric.outputs.name
output keyVault string = gov.outputs.keyVaultName
output logAnalytics string = gov.outputs.logAnalyticsWorkspaceId
