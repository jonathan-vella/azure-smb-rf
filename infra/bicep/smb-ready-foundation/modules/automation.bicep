// ============================================================================
// SMB Ready Foundation - Azure Automation Account
// ============================================================================
// Purpose: Deploy Azure Automation Account for patch management and runbooks,
//          linked to Log Analytics Workspace.
// Version: v0.1
// AVM Module: br/public:avm/res/automation/automation-account:0.11.0
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for resource deployment')
param location string

@description('Environment name')
param environment string

@description('Region abbreviation for naming')
param regionShort string

@description('Log Analytics Workspace resource ID for linking')
param logAnalyticsWorkspaceId string

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

var automationAccountName = 'aa-smbrf-${environment}-${regionShort}'

// ============================================================================
// Automation Account (AVM Module)
// ============================================================================

@description('Azure Automation Account with system-assigned managed identity')
module automationAccount 'br/public:avm/res/automation/automation-account:0.11.0' = {
  name: 'deploy-${automationAccountName}'
  params: {
    name: automationAccountName
    location: location
    tags: tags
    // SKU
    skuName: 'Basic'
    // System-assigned managed identity for secure operations
    managedIdentities: {
      systemAssigned: true
    }
    // Disable public network access is not needed for SMB — keep enabled for simplicity
    publicNetworkAccess: 'Enabled'
    // Link to Log Analytics Workspace
    linkedWorkspaceResourceId: logAnalyticsWorkspaceId
    // Diagnostic settings
    diagnosticSettings: [
      {
        name: 'aa-diag-law'
        workspaceResourceId: logAnalyticsWorkspaceId
        logCategoriesAndGroups: [
          {
            categoryGroup: 'allLogs'
          }
        ]
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Automation Account resource ID')
output automationAccountId string = automationAccount.outputs.resourceId

@description('Automation Account name')
output automationAccountName string = automationAccount.outputs.name

@description('Automation Account system-assigned managed identity principal ID')
output automationAccountPrincipalId string = automationAccount.outputs.?systemAssignedMIPrincipalId ?? ''
