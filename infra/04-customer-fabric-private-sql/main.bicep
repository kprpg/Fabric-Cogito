targetScope = 'resourceGroup'

import { environmentSettings, fabricSettings } from '../shared/types.bicep'

param environment environmentSettings
param fabric fabricSettings
@secure()
@minLength(12)
param adminPassword string
@minLength(1)
param providerPrivateLinkServiceId string
@description('Explicit design sign-off for provider workspace networking, SQL identity, and the customer gateway/connector combination.')
@allowed([
  true
])
param privateConnectivityApproved bool

module customer '../shared/customer-environment.bicep' = {
  name: '${environment.namePrefix}-customer'
  params: {
    environment: environment
    fabric: fabric
    adminPassword: adminPassword
    publicSql: !privateConnectivityApproved
    customerFabric: true
    providerPrivateLinkServiceId: providerPrivateLinkServiceId
  }
}

output connections object = customer.outputs.connections
