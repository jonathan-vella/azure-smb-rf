// ============================================================================
// Customer Onboarding — Policy Backup MI
// ============================================================================
// Purpose:
//   Pre-create a User-Assigned Managed Identity (UAMI) in the customer tenant
//   for the smb-backup-02 DINE policy. The policy needs Backup Contributor +
//   Virtual Machine Contributor at subscription scope to remediate VMs tagged
//   `Backup:true`.
//
//   The smb-ready-foundation deployment normally lets the policyAssignment
//   create a SystemAssigned identity and grants those roles to it. That works
//   when a customer-tenant principal runs the deploy directly, but it fails
//   when the partner UAMI runs it via Lighthouse: Lighthouse-delegated User
//   Access Administrator can only assign delegated roles to *partner-tenant*
//   principals listed in the registrationDefinition's `authorizations`. A
//   policy's SystemAssigned MI is a customer-tenant principal created on the
//   fly, so it can never appear in that list.
//
//   This module is therefore deployed **once** by the customer admin during
//   onboarding (sub-scope deployment via the management console wizard, using
//   the customer admin's own ARM token — no Lighthouse needed). The resulting
//   UAMI's resourceId is fed back to the worker, which passes it to the
//   foundation as the `policyMiResourceId` parameter so the policy assigns
//   this pre-existing UAMI instead of creating its own.
//
// Idempotent: re-deploying produces no changes.
// ============================================================================

targetScope = 'subscription'

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Region for the onboarding resource group and UAMI. Must match the foundation deployment region.')
param location string

@description('Name of the resource group that will hold the UAMI. Created if it does not exist.')
param resourceGroupName string = 'rg-smbrf-onboarding'

@description('Name of the UAMI. Re-used across deployments; remains stable so the foundation can keep referencing the same resource id.')
param identityName string = 'id-smbrf-policy-backup'

@description('Tags applied to the resource group and the UAMI. Must include `Environment` and `Owner` to satisfy the smb-rf MG baseline tagging policy.')
param tags object = {
  ManagedBy: 'smb-rf-management-console'
  Purpose: 'policy-backup-mi'
  Environment: 'prod'
  Owner: 'partner-ops'
}

// ----------------------------------------------------------------------------
// Built-in role IDs (must match policy-backup-auto.bicep)
// ----------------------------------------------------------------------------

var backupContributorRoleId = '5e467623-bb1f-42f4-a55d-6e525e11384b'
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

// ----------------------------------------------------------------------------
// Resource Group
// ----------------------------------------------------------------------------

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ----------------------------------------------------------------------------
// UAMI (deployed inside the RG via a nested module)
// ----------------------------------------------------------------------------

module uami 'modules/uami.bicep' = {
  name: 'uami-policy-backup'
  scope: resourceGroup(rg.name)
  params: {
    name: identityName
    location: location
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// Role Assignments at Subscription Scope
// ----------------------------------------------------------------------------

@description('Backup Contributor at subscription scope for the policy UAMI')
resource backupContributorRA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, identityName, 'Backup Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', backupContributorRoleId)
    principalId: uami.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Virtual Machine Contributor at subscription scope for the policy UAMI')
resource vmContributorRA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, identityName, 'VM Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId: uami.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('Full resource id of the UAMI. Persisted on the customer record and forwarded to the foundation deployment.')
output policyMiResourceId string = uami.outputs.resourceId

@description('Object (principal) id of the UAMI. Surfaced for diagnostics/RBAC inspection.')
output policyMiPrincipalId string = uami.outputs.principalId

@description('Client (application) id of the UAMI. Surfaced for diagnostics.')
output policyMiClientId string = uami.outputs.clientId
