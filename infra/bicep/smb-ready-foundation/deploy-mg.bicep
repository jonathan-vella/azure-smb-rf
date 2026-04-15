// ============================================================================
// SMB Ready Foundation - Management Group Creation
// ============================================================================
// Purpose: Create the smb-rf intermediate management group and associate
//          the target subscription under it.
// Version: v0.1
// Deployment: az deployment mg create --management-group-id <tenantRootMgId>
//             --location swedencentral --template-file deploy-mg.bicep
//             --parameters subscriptionId=<subId>
// ============================================================================
// Hierarchy:
//   Tenant Root Management Group
//   └── smb-rf (SMB Ready Foundation)
//       └── Customer Subscription
// ============================================================================

targetScope = 'managementGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the management group to create')
param managementGroupName string = 'smb-rf'

@description('Display name for the management group')
param managementGroupDisplayName string = 'SMB Ready Foundation'

@description('Subscription ID to move under the management group')
param subscriptionId string

// ============================================================================
// Management Group
// ============================================================================

@description('Create the smb-rf management group under the current MG (tenant root)')
resource smbrfMg 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: managementGroupName
  properties: {
    displayName: managementGroupDisplayName
    details: {
      parent: {
        id: managementGroup().id
      }
    }
  }
}

// ============================================================================
// Subscription Association
// ============================================================================

@description('Move the target subscription under the smb-rf management group')
resource mgSubAssociation 'Microsoft.Management/managementGroups/subscriptions@2023-04-01' = {
  parent: smbrfMg
  name: subscriptionId
}

// ============================================================================
// Outputs
// ============================================================================

@description('Management group resource ID')
output managementGroupId string = smbrfMg.id

@description('Management group name')
output managementGroupName string = smbrfMg.name
