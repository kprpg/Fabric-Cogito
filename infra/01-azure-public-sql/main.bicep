targetScope = 'resourceGroup'

import { environmentSettings } from '../shared/types.bicep'

param environment environmentSettings
@secure()
@minLength(12)
param adminPassword string

module customer '../shared/customer-environment.bicep' = {
  name: '${environment.namePrefix}-customer'
  params: {
    environment: environment
    adminPassword: adminPassword
    publicSql: true
    customerFabric: false
  }
}

output connections object = customer.outputs.connections
