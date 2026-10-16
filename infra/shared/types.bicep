@export()
@sealed()
type environmentSettings = {
  @minLength(3)
  @maxLength(12)
  namePrefix: string
  location: string
  @description('Nonoverlapping IPv4 /16. Subnets are derived from this prefix.')
  vnetAddressPrefix: string
  adminUsername: string
  vmSize: string
  @description('Approved HTTPS destinations for Entra, Fabric, gateway relay, and software management. No wildcard-wide Internet rule.')
  @minLength(1)
  httpsAllowedFqdns: string[]
  @description('Public SQL only: approved service tags covering provider home, capacity, and recovery regions.')
  @minLength(1)
  sqlServiceTags: string[]
  tags: object
}

@export()
@sealed()
type fabricSettings = {
  sku: 'F2' | 'F4' | 'F8' | 'F16' | 'F32' | 'F64' | 'F128' | 'F256' | 'F512' | 'F1024' | 'F2048'
  @minLength(1)
  administrators: string[]
  @description('Optional customer-tenant object ID explicitly authorized to write landing data. Empty means no data-plane grant.')
  landingDataPrincipalId: string
}
