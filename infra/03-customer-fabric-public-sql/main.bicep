targetScope = 'resourceGroup'

import { environmentSettings, fabricSettings } from '../shared/types.bicep'

param environment environmentSettings
param fabric fabricSettings
@secure()
@minLength(12)
param adminPassword string

module customer '../shared/customer-environment.bicep' = {
  name: '${environment.namePrefix}-customer'
  params: {
    environment: environment
    fabric: fabric
    adminPassword: adminPassword
    publicSql: true
    customerFabric: true
  }
}

output connections object = customer.outputs.connections
