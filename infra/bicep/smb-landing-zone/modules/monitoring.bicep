// ============================================================================
// SMB Landing Zone - Monitoring
// ============================================================================
// Purpose: Deploy Log Analytics Workspace with daily cap
// Version: v0.1
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for resource deployment')
param location string

@description('Environment name')
@allowed([
  'dev'
  'staging'
  'prod'
  'slz'
  'slz'
])
param environment string

@description('Region abbreviation for naming')
param regionShort string

@description('Daily ingestion cap in GB (0 = no cap, minimum 0.023 GB if set). Use decimal values e.g., 0.5 for ~500MB')
param dailyCapGb string = '0.5'

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var workspaceName = 'log-smblz-${environment}-${regionShort}'

// Parse daily cap from string to allow decimal values
// Minimum Azure allows is 0.023 GB (~24 MB). If dailyCapGb is '0', omit the cap.
var dailyQuotaGbValue = json(dailyCapGb)

// ============================================================================
// Log Analytics Workspace
// ============================================================================

@description('Log Analytics Workspace with daily cap for cost control')
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: dailyQuotaGbValue > 0 ? {
      dailyQuotaGb: dailyQuotaGbValue
    } : null
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Log Analytics Workspace resource ID')
output workspaceId string = logAnalytics.id

@description('Log Analytics Workspace name')
output workspaceName string = logAnalytics.name

@description('Log Analytics Workspace customer ID (for agent configuration)')
output workspaceCustomerId string = logAnalytics.properties.customerId
