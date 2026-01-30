// ============================================================================
// SMB Landing Zone - Auto-Backup Policy Assignment
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

// ============================================================================
// Variables
// ============================================================================

// Built-in policy: Configure backup on VMs with a given tag to an existing RSV
var policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/345fa903-145c-4fe1-8bcd-93ec2adccde8'

// Role definition IDs
var backupContributorRoleId = '5e467623-bb1f-42f4-a55d-6e525e11384b'
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

// ============================================================================
// Policy Assignment
// ============================================================================

@description('Auto-configure backup on VMs with Backup:true tag')
resource policyBackupAutoEnroll 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-lz-backup-02'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'SMB LZ: Auto-Backup VMs with Backup Tag'
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

@description('Backup Contributor role for policy managed identity')
resource backupContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, 'smb-lz-backup-02', 'Backup Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', backupContributorRoleId)
    principalId: policyBackupAutoEnroll.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Virtual Machine Contributor role for policy managed identity')
resource vmContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, 'smb-lz-backup-02', 'VM Contributor')
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

@description('Auto-backup policy managed identity principal ID')
output managedIdentityPrincipalId string = policyBackupAutoEnroll.identity.principalId
