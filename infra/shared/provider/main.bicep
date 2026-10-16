targetScope = 'resourceGroup'

@description('Deploy separately while signed into the Epic/provider tenant. This does not create or modify the workspace.')
@minLength(3)
param privateLinkServiceName string
@minLength(36)
@maxLength(36)
param workspaceId string

// Microsoft publishes this exact ARM contract in the workspace Private Link setup guide; compiler types are not yet available.
#disable-next-line BCP081
resource service 'Microsoft.Fabric/privateLinkServicesForFabric@2024-06-01' = {
  name: privateLinkServiceName
  location: 'global'
  properties: {
    tenantId: tenant().tenantId
    workspaceId: workspaceId
  }
}

output privateLinkServiceResourceId string = service.id
output providerTenantId string = tenant().tenantId
output workspaceId string = workspaceId
