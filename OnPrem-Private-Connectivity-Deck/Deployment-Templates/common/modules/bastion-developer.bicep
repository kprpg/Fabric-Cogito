// Free Bastion Developer SKU (shared pool, one session at a time). Region support is limited:
// https://learn.microsoft.com/azure/bastion/bastion-sku-comparison#regional-availability
param name string
param location string
param tags object = {}
param vnetId string

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Developer'
  }
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

output id string = bastion.id
