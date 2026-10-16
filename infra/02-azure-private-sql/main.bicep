targetScope = 'resourceGroup'

import { environmentSettings } from '../shared/types.bicep'

param environment environmentSettings
@secure()
@minLength(12)
param adminPassword string
@minLength(1)
param providerPrivateLinkServiceId string
@description('Explicit design sign-off for the provider workspace Private Link and selected SQL identity mechanism; not proof that the pending connection is approved.')
@allowed([
  true
])
param privateConnectivityApproved bool

module customer '../shared/customer-environment.bicep' = {
  name: '${environment.namePrefix}-customer'
  params: {
    environment: environment
    adminPassword: adminPassword
    publicSql: !privateConnectivityApproved
    customerFabric: false
    providerPrivateLinkServiceId: providerPrivateLinkServiceId
  }
}

output connections object = customer.outputs.connections
