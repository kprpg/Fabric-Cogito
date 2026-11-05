// "On-premises" server simulated by an Azure VM on a nested-virtualization-capable SKU (Dsv5).
// Optionally runs Hyper-V (internal vSwitch for nested guests), DNS and SQL Server 2022 Developer, then
// hides its Azure origin: IMDS blocked, guest agent disabled, onboarded to Azure Arc (Microsoft.HybridCompute/machines).
// Supported by Microsoft for evaluation/testing only.
param name string
@maxLength(15)
param computerName string
param location string
param tags object = {}
param subnetId string
param privateIpAddress string
param vmSize string = 'Standard_D4s_v5'
param adminUsername string
@secure()
param adminPassword string
@secure()
param sqlPassword string = ''

param installHyperV bool = true
param installSql bool = true
param dataDiskSizeGB int = 256
param nestedLanPrefix string = ''
param nestedLanGatewayIp string = ''
param dnsZoneName string = ''
param dnsRecordName string = 'sql01'
param sqlLogin string = 'fabricsvc'

@description('Run the first-boot bootstrap. Set false on re-deployments after the guest agent has been disabled.')
param runBootstrap bool = true
param presentAsNonAzure bool = true
param onboardToArc bool = true
@secure()
@description('Optional ARM access token used instead of the VM managed identity for Arc onboarding (when no role-assignment rights).')
param arcAccessToken string = ''
param enableAutoShutdown bool = true
param autoShutdownTime string = '2100'
param autoShutdownTimeZone string = 'Central Standard Time'

var images = {
  sql: {
    publisher: 'MicrosoftSQLServer'
    offer: 'sql2022-ws2022'
    sku: 'sqldev-gen2'
    version: 'latest'
  }
  windows: {
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-g2'
    version: 'latest'
  }
}

var arcResourceName = '${name}-arc'
var stage2 = loadTextContent('../scripts/OnPremHost-Stage2.ps1')
var stage1 = replace(loadTextContent('../scripts/OnPremHost-Stage1.ps1'), '#STAGE2_PLACEHOLDER#', stage2)

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    enableIPForwarding: true
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIpAddress
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: installSql ? images.sql : images.windows
      osDisk: {
        name: 'osdisk-${name}'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      dataDisks: installHyperV ? [
        {
          name: 'datadisk-${name}-hyperv'
          lun: 0
          createOption: 'Empty'
          diskSizeGB: dataDiskSizeGB
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      ] : []
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// Lets the VM onboard itself to Arc without any stored credential (token is read from IMDS before IMDS is blocked).
resource arcRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (presentAsNonAzure && onboardToArc && empty(arcAccessToken)) {
  name: guid(resourceGroup().id, vm.id, 'arc-onboarding')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b64e21ea-ac4e-4cdf-9dc9-5b892992bee7')
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource bootstrap 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = if (runBootstrap) {
  parent: vm
  name: 'onprem-simulation-stage1'
  location: location
  tags: tags
  properties: {
    source: {
      script: stage1
    }
    protectedParameters: [
      {
        name: 'ConfigB64'
        value: base64(string({
          installHyperV: installHyperV
          installSql: installSql
          sqlPassword: sqlPassword
          sqlLogin: sqlLogin
          nestedLanPrefix: nestedLanPrefix
          nestedLanGatewayIp: nestedLanGatewayIp
          dnsZone: dnsZoneName
          dnsRecord: dnsRecordName
          hostIp: privateIpAddress
          presentAsNonAzure: presentAsNonAzure
          onboardArc: presentAsNonAzure && onboardToArc
          arcResourceName: arcResourceName
          arcAccessToken: arcAccessToken
          arcTags: 'Purpose=OnPremSimulation,SimulatedBy=${name}'
        }))
      }
    ]
    timeoutInSeconds: 1800
    treatFailureAsDeploymentFailure: true
  }
  dependsOn: [
    arcRole
  ]
}

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (enableAutoShutdown) {
  name: 'shutdown-computevm-${name}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimeZone
    notificationSettings: {
      status: 'Disabled'
    }
    targetResourceId: vm.id
  }
}

output vmName string = vm.name
output vmId string = vm.id
output privateIp string = privateIpAddress
output arcResourceName string = arcResourceName
