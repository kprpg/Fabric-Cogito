targetScope = 'resourceGroup'

param namePrefix string
param location string
param addressPrefix string
param publicSql bool
param httpsAllowedFqdns array
param sqlServiceTags array
param logAnalyticsWorkspaceId string
param tags object

var workloadPrefix = cidrSubnet(addressPrefix, 24, 0)
var endpointPrefix = cidrSubnet(addressPrefix, 24, 1)
var firewallPrefix = cidrSubnet(addressPrefix, 24, 2)
var bastionPrefix = cidrSubnet(addressPrefix, 24, 3)
var publicSqlRules = [
  for (serviceTag, i) in (publicSql ? sqlServiceTags : []): {
    name: 'AllowApprovedPublicSql-${i}'
    properties: {
      priority: 300 + i
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '1433'
      sourceAddressPrefix: workloadPrefix
      destinationAddressPrefix: serviceTag
    }
  }
]

resource workloadNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-client-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: concat(
      [
        {
          name: 'AllowBastionRdp'
          properties: {
            priority: 100
            direction: 'Inbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '3389'
            sourceAddressPrefix: bastionPrefix
            destinationAddressPrefix: workloadPrefix
          }
        }
        {
          name: 'DenyOtherInbound'
          properties: {
            priority: 4096
            direction: 'Inbound'
            access: 'Deny'
            protocol: '*'
            sourcePortRange: '*'
            destinationPortRange: '*'
            sourceAddressPrefix: '*'
            destinationAddressPrefix: '*'
          }
        }
        {
          name: 'AllowAzureDns'
          properties: {
            priority: 100
            direction: 'Outbound'
            access: 'Allow'
            protocol: '*'
            sourcePortRange: '*'
            destinationPortRange: '53'
            sourceAddressPrefix: workloadPrefix
            destinationAddressPrefix: 'AzurePlatformDNS'
          }
        }
        {
          name: 'AllowFirewallDnsProxy'
          properties: {
            priority: 105
            direction: 'Outbound'
            access: 'Allow'
            protocol: '*'
            sourcePortRange: '*'
            destinationPortRange: '53'
            sourceAddressPrefix: workloadPrefix
            destinationAddressPrefix: firewallPrefix
          }
        }
        {
          name: 'AllowAzureVmAgent'
          properties: {
            priority: 110
            direction: 'Outbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRanges: [
              '80'
              '32526'
            ]
            sourceAddressPrefix: workloadPrefix
            destinationAddressPrefix: '168.63.129.16'
          }
        }
        {
          name: 'AllowAzureInstanceMetadata'
          properties: {
            priority: 120
            direction: 'Outbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '80'
            sourceAddressPrefix: workloadPrefix
            destinationAddressPrefix: 'AzurePlatformIMDS'
          }
        }
        {
          name: 'AllowPrivateServices'
          properties: {
            priority: 200
            direction: 'Outbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRanges: [
              '443'
              '1433'
            ]
            sourceAddressPrefix: workloadPrefix
            destinationAddressPrefix: endpointPrefix
          }
        }
        {
          name: 'AllowFirewallFilteredWeb'
          properties: {
            priority: 210
            direction: 'Outbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRanges: [
              '80'
              '443'
            ]
            sourceAddressPrefix: workloadPrefix
            destinationAddressPrefix: 'Internet'
          }
        }
        {
          name: 'AllowWindowsActivation'
          properties: {
            priority: 230
            direction: 'Outbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '1688'
            sourceAddressPrefix: workloadPrefix
            destinationAddressPrefix: 'AzurePlatformLKM'
          }
        }
        {
          name: 'DenyOtherOutbound'
          properties: {
            priority: 4096
            direction: 'Outbound'
            access: 'Deny'
            protocol: '*'
            sourcePortRange: '*'
            destinationPortRange: '*'
            sourceAddressPrefix: '*'
            destinationAddressPrefix: '*'
          }
        }
      ],
      publicSqlRules
    )
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: '${namePrefix}-egress-policy'
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Deny'
    dnsSettings: {
      enableProxy: true
    }
  }
}

var sqlFirewallRules = publicSql
  ? [
      {
        name: 'ApprovedFabricTds'
        ruleType: 'NetworkRule'
        ipProtocols: [
          'TCP'
        ]
        sourceAddresses: [
          workloadPrefix
        ]
        destinationAddresses: sqlServiceTags
        destinationPorts: [
          '1433'
        ]
      }
    ]
  : []

resource egressRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: firewallPolicy
  name: 'client-egress'
  properties: {
    priority: 100
    ruleCollections: [
      {
        name: 'platform-and-sql'
        priority: 100
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: concat(
          [
            {
              name: 'WindowsActivation'
              ruleType: 'NetworkRule'
              ipProtocols: [
                'TCP'
              ]
              sourceAddresses: [
                workloadPrefix
              ]
              destinationFqdns: [
                'azkms.${environment().suffixes.storage}'
              ]
              destinationPorts: [
                '1688'
              ]
            }
          ],
          sqlFirewallRules
        )
      }
      {
        name: 'approved-https'
        priority: 200
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'MicrosoftManagedWindowsUpdate'
            ruleType: 'ApplicationRule'
            sourceAddresses: [
              workloadPrefix
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: [
              'WindowsUpdate'
            ]
          }
          {
            name: 'EntraFabricAndApprovedManagement'
            ruleType: 'ApplicationRule'
            sourceAddresses: [
              workloadPrefix
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: httpsAllowedFqdns
          }
        ]
      }
    ]
  }
}

resource firewallIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-egress-ip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-bastion-ip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
  }
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'AzureFirewallSubnet'
  properties: {
    addressPrefix: firewallPrefix
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'AzureBastionSubnet'
  properties: {
    addressPrefix: bastionPrefix
  }
  dependsOn: [
    firewallSubnet
  ]
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: '${namePrefix}-egress'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          subnet: {
            id: firewallSubnet.id
          }
          publicIPAddress: {
            id: firewallIp.id
          }
        }
      }
    ]
  }
}

resource routeTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: '${namePrefix}-client-routes'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'DefaultViaFirewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

resource workloadSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'clients'
  properties: {
    addressPrefix: workloadPrefix
    defaultOutboundAccess: false
    networkSecurityGroup: {
      id: workloadNsg.id
    }
    routeTable: {
      id: routeTable.id
    }
  }
  dependsOn: [
    bastionSubnet
  ]
}

resource endpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'private-endpoints'
  properties: {
    addressPrefix: endpointPrefix
    defaultOutboundAccess: false
    privateEndpointNetworkPolicies: 'Disabled'
  }
  dependsOn: [
    workloadSubnet
  ]
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: '${namePrefix}-bastion'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: false
    enableIpConnect: false
    enableShareableLink: false
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          subnet: {
            id: bastionSubnet.id
          }
          publicIPAddress: {
            id: bastionIp.id
          }
        }
      }
    ]
  }
}

resource firewallDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'central-logs'
  scope: firewall
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

resource bastionDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'central-logs'
  scope: bastion
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output vnetId string = vnet.id
output workloadSubnetId string = workloadSubnet.id
output endpointSubnetId string = endpointSubnet.id
output egressPublicIp string = firewallIp.properties.ipAddress
output bastionId string = bastion.id
output dnsProxyIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
