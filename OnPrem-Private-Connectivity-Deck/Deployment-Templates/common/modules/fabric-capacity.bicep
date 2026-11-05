// Microsoft Fabric capacity (F SKU). Deployed last. Pause it when idle (Deploy-Pattern.ps1 -Action Pause).
param name string
param location string
param tags object = {}
param skuName string = 'F2'
param adminMembers array

resource capacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: adminMembers
    }
  }
}

output id string = capacity.id
output name string = capacity.name
