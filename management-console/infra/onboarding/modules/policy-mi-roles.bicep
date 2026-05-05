// ============================================================================
// Subscription-scoped role assignments for the policy backup UAMI.
// ----------------------------------------------------------------------------
// Wrapped in a dedicated module so `principalId` is a module parameter
// (known at deployment-start within this module's scope) and therefore
// usable in the role assignment `name` GUID seed without tripping BCP120.
// ============================================================================

targetScope = 'subscription'

@description('Object (principal) id of the UAMI receiving the role assignments.')
param principalId string

@description('Built-in Backup Contributor role definition id (GUID only).')
param backupContributorRoleId string

@description('Built-in Virtual Machine Contributor role definition id (GUID only).')
param vmContributorRoleId string

// Seed the deterministic GUID with the UAMI's principalId so a recreated
// UAMI (new principalId) produces a new role-assignment name instead of
// colliding with the previous one. Azure rejects principalId updates on
// an existing role assignment with RoleAssignmentUpdateNotPermitted.
resource backupContributorRA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'Backup Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', backupContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource vmContributorRA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'VM Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
