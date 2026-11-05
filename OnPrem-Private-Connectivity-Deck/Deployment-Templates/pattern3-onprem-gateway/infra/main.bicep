// Pattern 3 - On-premises data gateway (outbound-only). No Azure network or hybrid link is required:
// the gateway cluster lives next to SQL Server in the (simulated) on-prem LAN and dials out to Azure Relay.
// The gateway software itself needs an interactive Entra sign-in; use common/scripts/Install-OnPremGateway.ps1.
//
// Deployment order: resource groups -> governance -> simulated on-prem site (SQL host + gateway nodes) -> Fabric capacity.
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
param fabricAdminUpns array
param fabricSku string = 'F2'
param hostVmSize string = 'Standard_D4s_v5'
@minValue(1)
@maxValue(2)
@description('Gateway cluster nodes (2 = HA cluster).')
param gatewayNodeCount int = 2
param gatewayVmSize string = 'Standard_D4s_v5'
param deployerPrincipalId string = ''
param kvUseAccessPolicies bool = false
param runBootstrap bool = true
param deployBastionDeveloper bool = true
param onboardToArc bool = true
@secure()
param arcAccessToken string = ''
param extraTags object = {}

// ---- Address plan ----
var onpremCidr = '10.130.0.0/16'
var onpremLanSubnet = '10.130.1.0/24'
var onpremHostIp = '10.130.1.4'
var gatewayNodeIps = [ '10.130.1.5', '10.130.1.6' ]
var onpremNestedLan = '10.130.2.0/24'
var onpremNestedLanGw = '10.130.2.1'

var locShort = regionShortNames[?location] ?? take(location, 6)
var pattern = 'p3'
var suffix = '${workload}-${pattern}'
var tail = '${environment}-${locShort}'
var uniq = uniqueString(subscription().id, workload, pattern, environment, location)
var tags = union({
  workload: workload
  pattern: 'p3-onprem-gateway'
  environment: environment
  purpose: 'Fabric private connectivity demo'
  'managed-by': 'bicep'
}, extraTags)

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
  }
}

// ---- 2. Simulated on-premises site: SQL/Hyper-V host + gateway nodes on the same LAN ----
module onprem '../../common/modules/onprem-site.bicep' = {
  name: 'onprem-${suffix}'
  scope: rgOnprem
  params: {
    location: location
    tags: tags
    suffix: suffix
    tail: tail
    computerName: 'p3-onprem-sql'
    addressSpace: onpremCidr
    lanSubnetPrefix: onpremLanSubnet
    hostPrivateIp: onpremHostIp
    nestedLanPrefix: onpremNestedLan
    nestedLanGatewayIp: onpremNestedLanGw
    deployVpnDevice: false
    deployBastionDeveloper: deployBastionDeveloper
    hostVmSize: hostVmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    sqlPassword: sqlPassword
    dnsZoneName: ''
    runBootstrap: runBootstrap
    onboardToArc: onboardToArc
    arcAccessToken: arcAccessToken
    // Egress the on-premises data gateway needs (documented firewall/proxy allow-list).
    extraLanNsgRules: [
      {
        name: 'Allow-Gateway-HTTPS-Out'
        priority: 200
        direction: 'Outbound'
        access: 'Allow'
        protocol: 'Tcp'
        src: [ onpremLanSubnet ]
        dst: [ 'Internet' ]
        ports: [ '443' ]
      }
      {
        name: 'Allow-Gateway-Relay-Out'
        priority: 210
        direction: 'Outbound'
        access: 'Allow'
        protocol: 'Tcp'
        src: [ onpremLanSubnet ]
        dst: [ 'ServiceBus' ]
        ports: [ '5671-5672', '9350-9354' ]
      }
    ]
  }
}

module gatewayNodes '../../common/modules/onprem-host.bicep' = [for i in range(0, gatewayNodeCount): {
  name: 'vm-${suffix}-gw0${i + 1}'
  scope: rgOnprem
  params: {
    name: 'vm-${suffix}-gw0${i + 1}-${tail}'
    computerName: 'p3-onprem-gw0${i + 1}'
    location: location
    tags: tags
    subnetId: onprem.outputs.lanSubnetId
    privateIpAddress: gatewayNodeIps[i]
    vmSize: gatewayVmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    installHyperV: false
    installSql: false
    dnsZoneName: ''
    runBootstrap: runBootstrap
    onboardToArc: onboardToArc
    arcAccessToken: arcAccessToken
  }
}]

// ---- 3. Fabric capacity (last) ----
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
    onprem
    gatewayNodes
  ]
}

output pattern string = 'p3-onprem-gateway'
output resourceGroups object = {
  onprem: rgOnprem.name
  gov: rgGov.name
  fabric: rgFabric.name
}
output onpremSqlIp string = onpremHostIp
output onpremSqlFqdn string = onpremHostIp
output onpremHostVm string = onprem.outputs.hostName
output gatewayNodeVms array = [for i in range(0, gatewayNodeCount): 'vm-${suffix}-gw0${i + 1}-${tail}']
output fabricCapacity string = fabric.outputs.name
output keyVault string = gov.outputs.keyVaultName
