// Shared constants exported to every pattern (see docs/02-ip-addressing-and-naming.md).

@export()
var regionShortNames = {
  eastus: 'eus'
  eastus2: 'eus2'
  centralus: 'cus'
  northcentralus: 'ncus'
  southcentralus: 'scus'
  westus: 'wus'
  westus2: 'wus2'
  westus3: 'wus3'
  westeurope: 'weu'
  northeurope: 'neu'
  uksouth: 'uks'
  swedencentral: 'sec'
  australiaeast: 'aue'
  southeastasia: 'sea'
}

// Built-in role: Azure Connected Machine Onboarding
@export()
var arcOnboardingRoleId = 'b64e21ea-ac4e-4cdf-9dc9-5b892992bee7'

// Built-in role: Key Vault Secrets Officer
@export()
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
