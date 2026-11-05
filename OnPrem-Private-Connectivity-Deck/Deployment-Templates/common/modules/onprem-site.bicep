// Simulated on-premises site (resource-group scope): VNet + NAT egress + NSG + optional Bastion Developer,
// optional VPN gateway acting as the customer edge device, and the Hyper-V/SQL host that "appears non-Azure".
param location string
param tags object = {}
@description('Naming: resource names are <abbr>-<suffix>-<role>-<tail>, e.g. suffix=fabcn-p1, tail=dev-eus2')
param suffix string
param tail string
param computerName string
param addressSpace string
param gatewaySubnetPrefix string = ''
param lanSubnetPrefix string
param hostPrivateIp string
param nestedLanPrefix string
param nestedLanGatewayIp string
@description('Azure-side prefixes allowed to reach this site (SQL 1433, DNS 53, ICMP).')
param azureSideCidrs array = []
param extraLanNsgRules array = []

param deployVpnDevice bool = false
param vpnDeviceSku string = 'VpnGw1AZ'
param vpnDeviceAsn int = 65110
param logAnalyticsWorkspaceId string = ''

param deployBastionDeveloper bool = true
param hostVmSize string = 'Standard_D4s_v5'
param adminUsername string
@secure()
param adminPassword string
@secure()
param sqlPassword string
param installHyperV bool = true
param installSql bool = true
param dnsZoneName string = 'corp.contoso.lab'
param runBootstrap bool = true
param presentAsNonAzure bool = true
param onboardToArc bool = true
@secure()
param arcAccessToken string = ''
param enableAutoShutdown bool = true
param autoShutdownTimeZone string = 'Central Standard Time'

var azureAllow = empty(azureSideCidrs) ? [] : [
  {
    name: 'Allow-SQL-From-Azure'
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    src: azureSideCidrs
    dst: [ lanSubnetPrefix ]
    ports: [ '1433' ]
  }
  {
    name: 'Allow-DNS-From-Azure'
    priority: 110
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    src: azureSideCidrs
    dst: [ lanSubnetPrefix ]
    ports: [ '53' ]
  }
  {
    name: 'Allow-ICMP-From-Azure'
    priority: 120
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Icmp'
    src: azureSideCidrs
    dst: [ lanSubnetPrefix ]
    ports: [ '*' ]
  }
]

var baseRules = [
  {
    name: 'Allow-RDP-From-Bastion'
    priority: 130
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    src: [ 'VirtualNetwork' ]
    dst: [ lanSubnetPrefix ]
    ports: [ '3389' ]
  }
  {
    name: 'Allow-Intra-LAN'
    priority: 140
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    src: [ lanSubnetPrefix ]
    dst: [ lanSubnetPrefix ]
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

var lanSubnet = {
  name: 'snet-lan'
  addressPrefix: lanSubnetPrefix
  nsgId: nsg.outputs.id
  natGatewayId: nat.outputs.id
}
var gwSubnet = {
  name: 'GatewaySubnet'
  addressPrefix: gatewaySubnetPrefix
}

module nat 'nat-gateway.bicep' = {
  name: 'nat-${suffix}-onprem'
  params: {
    name: 'ng-${suffix}-onprem-${tail}'
    location: location
    tags: tags
  }
}

module nsg 'nsg.bicep' = {
  name: 'nsg-${suffix}-lan'
  params: {
    name: 'nsg-${suffix}-lan-${tail}'
    location: location
    tags: tags
    rules: concat(azureAllow, baseRules, extraLanNsgRules)
  }
}

module vnet 'vnet.bicep' = {
  name: 'vnet-${suffix}-onprem'
  params: {
    name: 'vnet-${suffix}-onprem-${tail}'
    location: location
    tags: tags
    addressPrefixes: [ addressSpace ]
    subnets: empty(gatewaySubnetPrefix) ? [ lanSubnet ] : [ gwSubnet, lanSubnet ]
  }
}

module bastion 'bastion-developer.bicep' = if (deployBastionDeveloper) {
  name: 'bas-${suffix}-onprem'
  params: {
    name: 'bas-${suffix}-onprem-${tail}'
    location: location
    tags: tags
    vnetId: vnet.outputs.id
  }
}

module vpnDevice 'vpn-gateway.bicep' = if (deployVpnDevice) {
  name: 'vgw-${suffix}-onprem'
  params: {
    name: 'vgw-${suffix}-onprem-${tail}'
    location: location
    tags: tags
    gatewaySubnetId: vnet.outputs.subnetIds.GatewaySubnet
    sku: vpnDeviceSku
    asn: vpnDeviceAsn
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

module host 'onprem-host.bicep' = {
  name: 'vm-${suffix}-onprem-host'
  params: {
    name: 'vm-${suffix}-sql01-${tail}'
    computerName: computerName
    location: location
    tags: tags
    subnetId: vnet.outputs.subnetIds['snet-lan']
    privateIpAddress: hostPrivateIp
    vmSize: hostVmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    sqlPassword: sqlPassword
    installHyperV: installHyperV
    installSql: installSql
    nestedLanPrefix: nestedLanPrefix
    nestedLanGatewayIp: nestedLanGatewayIp
    dnsZoneName: dnsZoneName
    runBootstrap: runBootstrap
    presentAsNonAzure: presentAsNonAzure
    onboardToArc: onboardToArc
    arcAccessToken: arcAccessToken
    enableAutoShutdown: enableAutoShutdown
    autoShutdownTimeZone: autoShutdownTimeZone
  }
}

output vnetId string = vnet.outputs.id
output vnetName string = vnet.outputs.name
output lanSubnetId string = vnet.outputs.subnetIds['snet-lan']
output hostName string = host.outputs.vmName
output hostPrivateIp string = host.outputs.privateIp
output arcResourceName string = host.outputs.arcResourceName
output natPublicIp string = nat.outputs.publicIp
output vpnDeviceId string = vpnDevice.?outputs.id ?? ''
output vpnDeviceName string = vpnDevice.?outputs.name ?? ''
output vpnDevicePublicIp string = vpnDevice.?outputs.publicIp ?? ''
output vpnDeviceAsn int = vpnDeviceAsn
output vpnDeviceBgpIp string = vpnDevice.?outputs.bgpPeeringAddress ?? ''
