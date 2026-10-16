targetScope = 'resourceGroup'

param namePrefix string
param location string
param sku string
@minLength(1)
param administrators array
param tags object

resource capacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: '${namePrefix}${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: sku
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: administrators
    }
  }
}

output capacityId string = capacity.id
output capacityName string = capacity.name
