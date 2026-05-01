// ============================================================================
// SMB Ready Foundations - Auto-Backup Policy Assignment
// ============================================================================
// Purpose: Deploy DeployIfNotExists policy to auto-configure VM backup
// Policy: Configure backup on VMs with a given tag to an existing RSV
// Policy ID: 345fa903-145c-4fe1-8bcd-93ec2adccde8
// Version: v0.1
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Location for policy assignment metadata')
param location string

@description('Default VM Backup Policy ID (full resource ID)')
param defaultVmBackupPolicyId string

@description('Optional resource id of a pre-created User-Assigned Managed Identity (UAMI) with Backup Contributor + Virtual Machine Contributor at subscription scope. When provided, the policy assignment uses this UAMI instead of a SystemAssigned identity, and the in-template role assignments are skipped. Used by the partner management console (Lighthouse-delegated UAA cannot grant roles to a customer-tenant SystemAssigned MI). Leave empty for direct customer-admin deployments — the original SystemAssigned + role-assignment behavior is preserved.')
param policyMiResourceId string = ''

// ============================================================================
// Variables
// ============================================================================

// Built-in policy: Configure backup on VMs with a given tag to an existing RSV
var policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/345fa903-145c-4fe1-8bcd-93ec2adccde8'

// Role definition IDs
var backupContributorRoleId = '5e467623-bb1f-42f4-a55d-6e525e11384b'
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

// True when the caller pre-created a UAMI for the policy. Selects between
// UserAssigned (partner-managed-console flow) and SystemAssigned (default).
var useUserAssignedMi = !empty(policyMiResourceId)

// ============================================================================
// Policy Assignment
// ============================================================================

@description('Auto-configure backup on VMs with Backup:true tag')
resource policyBackupAutoEnroll 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-backup-02'
  location: location
  identity: useUserAssignedMi ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${policyMiResourceId}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'SMB RF: Auto-Backup VMs with Backup Tag'
    description: 'Automatically configure backup on VMs tagged with Backup:true to the central Recovery Services Vault using DefaultVMPolicy (30d daily, 12w weekly, 12m monthly retention)'
    policyDefinitionId: policyDefinitionId
    enforcementMode: 'Default'
    parameters: {
      vaultLocation: {
        value: location
      }
      inclusionTagName: {
        value: 'Backup'
      }
      inclusionTagValue: {
        value: [
          'true'
          'True'
          'yes'
          'Yes'
        ]
      }
      backupPolicyId: {
        value: defaultVmBackupPolicyId
      }
      effect: {
        value: 'DeployIfNotExists'
      }
    }
  }
}

// ============================================================================
// Role Assignments for Policy Managed Identity
// ============================================================================

// Role assignments only when using SystemAssigned. The UserAssigned path
// expects the caller to have pre-granted these roles to the UAMI (see
// management-console/infra/onboarding/policy-mi.bicep).
@description('Backup Contributor role for policy managed identity (SystemAssigned only)')
resource backupContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!useUserAssignedMi) {
  name: guid(subscription().id, 'smb-backup-02', 'Backup Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', backupContributorRoleId)
    principalId: policyBackupAutoEnroll.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Virtual Machine Contributor role for policy managed identity (SystemAssigned only)')
resource vmContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!useUserAssignedMi) {
  name: guid(subscription().id, 'smb-backup-02', 'VM Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId: policyBackupAutoEnroll.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Auto-backup policy assignment name')
output policyAssignmentName string = policyBackupAutoEnroll.name

@description('Auto-backup policy managed identity principal ID (SystemAssigned only; empty when a pre-created UAMI is used)')
output managedIdentityPrincipalId string = useUserAssignedMi ? '' : policyBackupAutoEnroll.identity.principalId
