// ============================================================================
// Onboarding helper: User-Assigned Managed Identity inside a resource group
// ============================================================================
// Tiny RG-scope module so policy-mi.bicep can stay subscription-scoped while
// still creating the UAMI inside a specific RG. Avoids pulling in an AVM
// dependency for this single-purpose, customer-side template (which gets
// deployed by the customer admin directly via ARM PUT, not via azd).
// ============================================================================

targetScope = 'resourceGroup'

@description('UAMI name')
param name string

@description('Region')
param location string

@description('Tags')
param tags object = {}

resource id 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

output resourceId string = id.id
output principalId string = id.properties.principalId
output clientId string = id.properties.clientId
