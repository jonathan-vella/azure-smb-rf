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

// Seed: canonical Microsoft pattern `guid(principalId, roleDefId, scope)`.
// Stable across redeploys for the same UAMI principal, and matches what
// most Azure tooling/samples generate so it's more likely to align with
// pre-existing assignments created elsewhere.
//
// Note on RBAC idempotency: Azure rejects creating a second role
// assignment for the same (scope, principal, role) tuple even with a
// different name (RoleAssignmentExists / "The role assignment already
// exists"). Bicep cannot detect that pre-existing state at compile time.
// If a partner hits this on first deploy, an assignment for this UAMI's
// principalId already exists at the subscription scope from another
// source — delete it once via:
//   az role assignment delete --ids <existingAssignmentId>
// then redeploy. Subsequent redeploys are idempotent.
resource backupContributorRA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, backupContributorRoleId, subscription().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', backupContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource vmContributorRA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, vmContributorRoleId, subscription().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
