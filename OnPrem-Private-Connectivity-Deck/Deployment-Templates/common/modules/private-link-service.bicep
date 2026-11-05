// Pattern 4 core: Standard internal load balancer + NAT forwarder VMs + Private Link Service.
// Fabric's managed private endpoint targets the PLS; the forwarders DNAT TCP 1433 to the on-prem SQL host.
param location string
param tags object = {}
param lbName string
param plsName string
param forwarderNamePrefix string
param forwarderSubnetId string
param plsNatSubnetId string
param lbFrontendIp string
param targetIp string
param targetPort int = 1433
param forwarderCount int = 2
param vmSize string = 'Standard_B2s'
param adminUsername string
@secure()
param adminPassword string
param plsVisibilitySubscriptions array = [ '*' ]
param plsAutoApprovalSubscriptions array = []
param logAnalyticsWorkspaceId string = ''

var cloudInit = replace(replace(loadTextContent('../scripts/nat-forwarder.cloud-init.yaml'), '__TARGET_IP__', targetIp), '__TARGET_PORT__', string(targetPort))
var feName = 'fe-sql'
var bePoolName = 'be-forwarders'
var probeName = 'probe-ssh'

resource lb 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: lbName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: feName
        zones: [ '1', '2', '3' ]
        properties: {
          subnet: {
            id: forwarderSubnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: lbFrontendIp
        }
      }
    ]
    backendAddressPools: [
      {
        name: bePoolName
      }
    ]
    // The forwarders do not listen on 1433 themselves (iptables DNAT), so probe SSH instead.
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Tcp'
          port: 22
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-sql'
        properties: {
          protocol: 'Tcp'
          frontendPort: targetPort
          backendPort: targetPort
          idleTimeoutInMinutes: 30
          enableTcpReset: true
          enableFloatingIP: false
          loadDistribution: 'SourceIP'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, feName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, bePoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, probeName)
          }
        }
      }
    ]
  }
}

resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for i in range(0, forwarderCount): {
  name: 'nic-${forwarderNamePrefix}-${i + 1}'
  location: location
  tags: tags
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: forwarderSubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: [
            {
              id: '${lb.id}/backendAddressPools/${bePoolName}'
            }
          ]
        }
      }
    ]
  }
}]

resource vms 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, forwarderCount): {
  name: '${forwarderNamePrefix}-${i + 1}'
  location: location
  tags: tags
  zones: [ string((i % 2) + 1) ]
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${forwarderNamePrefix}-${i + 1}'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: take('${forwarderNamePrefix}-${i + 1}', 15)
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
        }
      ]
    }
  }
}]

resource pls 'Microsoft.Network/privateLinkServices@2024-05-01' = {
  name: plsName
  location: location
  tags: tags
  properties: {
    loadBalancerFrontendIpConfigurations: [
      {
        id: '${lb.id}/frontendIPConfigurations/${feName}'
      }
    ]
    ipConfigurations: [for i in range(0, 2): {
      name: 'nat-${i + 1}'
      properties: {
        primary: i == 0
        privateIPAllocationMethod: 'Dynamic'
        privateIPAddressVersion: 'IPv4'
        subnet: {
          id: plsNatSubnetId
        }
      }
    }]
    enableProxyProtocol: false
    visibility: {
      subscriptions: plsVisibilitySubscriptions
    }
    autoApproval: {
      subscriptions: plsAutoApprovalSubscriptions
    }
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-to-law'
  scope: lb
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output plsId string = pls.id
output plsName string = pls.name
output plsAlias string = pls.properties.alias
output lbFrontendIp string = lbFrontendIp
