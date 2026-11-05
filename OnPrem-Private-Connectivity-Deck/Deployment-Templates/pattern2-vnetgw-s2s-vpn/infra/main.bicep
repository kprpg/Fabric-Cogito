// Pattern 2 - VNet data gateway over Site-to-Site IPsec VPN (single VNet).
// The "on-premises" VPN device is a second BGP-enabled Azure VPN gateway in an isolated simulated on-prem VNet,
// so a real IKEv2/IPsec tunnel with BGP is established over Azure public IPs. The SQL server behind it is a
// Hyper-V-capable VM that presents itself as a non-Azure (Arc-enabled) server.
//
// Deployment order: resource groups -> governance -> network + simulated on-prem -> VPN tunnel -> Fabric capacity.
targetScope = 'subscription'

import { regionShortNames } from '../../common/modules/shared.bicep'

param location string = 'eastus2'
param environment string = 'dev'
param workload string = 'fabcn'

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
param deployerPrincipalId string = ''
param kvUseAccessPolicies bool = false
param runBootstrap bool = true
param deployDnsResolver bool = true
param deployTestVm bool = true
param deployBastionDeveloper bool = true
param onboardToArc bool = true
@secure()
param arcAccessToken string = ''
param extraTags object = {}

// ---- Address plan ----
var azureCidr = '10.20.0.0/16'
var azureGatewaySubnet = '10.20.0.0/26'
var azureDnsOutSubnet = '10.20.0.64/28'
var azureVnetGwSubnet = '10.20.1.0/27'
var azureTestSubnet = '10.20.1.32/27'
var onpremCidr = '10.120.0.0/16'
var onpremGatewaySubnet = '10.120.0.0/27'
var onpremLanSubnet = '10.120.1.0/24'
var onpremHostIp = '10.120.1.4'
var onpremNestedLan = '10.120.2.0/24'
var onpremNestedLanGw = '10.120.2.1'
var azureAsn = 65020
var onpremAsn = 65120
var onpremZone = 'corp.contoso.lab'

var locShort = regionShortNames[?location] ?? take(location, 6)
var pattern = 'p2'
var suffix = '${workload}-${pattern}'
var tail = '${environment}-${locShort}'
var uniq = uniqueString(subscription().id, workload, pattern, environment, location)
var tags = union({
  workload: workload
  pattern: 'p2-vnetgw-s2s-vpn'
  environment: environment
  purpose: 'Fabric private connectivity demo'
  'managed-by': 'bicep'
}, extraTags)

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
        src: [ azureVnetGwSubnet ]
        dst: [ onpremCidr ]
        ports: [ '1433' ]
      }
      {
        name: 'Allow-Intra-Subnet'
        priority: 110
        direction: 'Inbound'
        access: 'Allow'
        protocol: '*'
        src: [ azureVnetGwSubnet ]
        dst: [ azureVnetGwSubnet ]
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

module natVnet '../../common/modules/nat-gateway.bicep' = {
  name: 'nat-${suffix}'
  scope: rgNet
  params: {
    name: 'ng-${suffix}-azure-${tail}'
    location: location
    tags: tags
  }
}

module vnet '../../common/modules/vnet.bicep' = {
  name: 'vnet-${suffix}-azure'
  scope: rgNet
  params: {
    name: 'vnet-${suffix}-azure-${tail}'
    location: location
    tags: tags
    addressPrefixes: [ azureCidr ]
    subnets: [
      {
        name: 'GatewaySubnet'
        addressPrefix: azureGatewaySubnet
      }
      {
        name: 'snet-dns-out'
        addressPrefix: azureDnsOutSubnet
        delegation: 'Microsoft.Network/dnsResolvers'
      }
      {
        name: 'snet-vnetgw'
        addressPrefix: azureVnetGwSubnet
        delegation: 'Microsoft.PowerPlatform/vnetaccesslinks'
        nsgId: nsgVnetGw.outputs.id
        natGatewayId: natVnet.outputs.id
      }
      {
        name: 'snet-test'
        addressPrefix: azureTestSubnet
        nsgId: nsgTest.outputs.id
      }
    ]
  }
}

// ---- 3. Simulated on-premises site (with its own VPN gateway acting as the customer edge device) ----
module onprem '../../common/modules/onprem-site.bicep' = {
  name: 'onprem-${suffix}'
  scope: rgOnprem
  params: {
    location: location
    tags: tags
    suffix: suffix
    tail: tail
    computerName: 'p2-onprem-sql'
    addressSpace: onpremCidr
    gatewaySubnetPrefix: onpremGatewaySubnet
    lanSubnetPrefix: onpremLanSubnet
    hostPrivateIp: onpremHostIp
    nestedLanPrefix: onpremNestedLan
    nestedLanGatewayIp: onpremNestedLanGw
    azureSideCidrs: [ azureCidr ]
    deployVpnDevice: true
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

// ---- 4. S2S VPN ----
module azureVpnGw '../../common/modules/vpn-gateway.bicep' = {
  name: 'vgw-${suffix}-azure'
  scope: rgNet
  params: {
    name: 'vgw-${suffix}-azure-${tail}'
    location: location
    tags: tags
    gatewaySubnetId: vnet.outputs.subnetIds.GatewaySubnet
    asn: azureAsn
    logAnalyticsWorkspaceId: gov.outputs.logAnalyticsWorkspaceId
  }
}

module connAzure '../../common/modules/s2s-connection.bicep' = {
  name: 'cn-${suffix}-azure-to-onprem'
  scope: rgNet
  params: {
    location: location
    tags: tags
    localGatewayName: 'lgw-${suffix}-onprem-${tail}'
    connectionName: 'cn-${suffix}-azure-to-onprem-${tail}'
    virtualNetworkGatewayId: azureVpnGw.outputs.id
    remoteGatewayPublicIp: onprem.outputs.vpnDevicePublicIp
    remoteAsn: onpremAsn
    remoteBgpPeeringAddress: onprem.outputs.vpnDeviceBgpIp
    sharedKey: vpnSharedKey
  }
}

module connOnprem '../../common/modules/s2s-connection.bicep' = {
  name: 'cn-${suffix}-onprem-to-azure'
  scope: rgOnprem
  params: {
    location: location
    tags: tags
    localGatewayName: 'lgw-${suffix}-azure-${tail}'
    connectionName: 'cn-${suffix}-onprem-to-azure-${tail}'
    virtualNetworkGatewayId: onprem.outputs.vpnDeviceId
    remoteGatewayPublicIp: azureVpnGw.outputs.publicIp
    remoteAsn: azureAsn
    remoteBgpPeeringAddress: azureVpnGw.outputs.bgpPeeringAddress
    sharedKey: vpnSharedKey
  }
}

module dns '../../common/modules/dns-resolver.bicep' = if (deployDnsResolver) {
  name: 'dns-${suffix}'
  scope: rgNet
  params: {
    name: 'dnspr-${suffix}-${tail}'
    location: location
    tags: tags
    vnetId: vnet.outputs.id
    outboundSubnetId: vnet.outputs.subnetIds['snet-dns-out']
    forwardingRules: [
      {
        name: 'onprem-corp'
        domain: '${onpremZone}.'
        targets: [ onpremHostIp ]
      }
    ]
    linkedVnetIds: [ vnet.outputs.id ]
  }
  dependsOn: [
    connAzure
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
    connAzure
    connOnprem
  ]
}

output pattern string = 'p2-vnetgw-s2s-vpn'
output resourceGroups object = {
  net: rgNet.name
  onprem: rgOnprem.name
  gov: rgGov.name
  fabric: rgFabric.name
}
output vnetGatewayTarget object = {
  subscriptionId: subscription().subscriptionId
  resourceGroup: rgNet.name
  virtualNetwork: vnet.outputs.name
  delegatedSubnet: 'snet-vnetgw'
  delegation: 'Microsoft.PowerPlatform/vnetaccesslinks'
}
output onpremSqlFqdn string = 'sql01.${onpremZone}'
output onpremSqlIp string = onpremHostIp
output onpremHostVm string = onprem.outputs.hostName
output onpremArcMachine string = onprem.outputs.arcResourceName
output testVm string = deployTestVm ? testVm!.outputs.name : ''
output vpnConnectionHub string = 'cn-${suffix}-azure-to-onprem-${tail}'
output fabricCapacity string = fabric.outputs.name
output keyVault string = gov.outputs.keyVaultName
output logAnalytics string = gov.outputs.logAnalyticsWorkspaceId
