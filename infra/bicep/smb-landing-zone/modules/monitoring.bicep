// ============================================================================
// SMB Landing Zone - Monitoring (AVM-based)
// ============================================================================
// Purpose: Deploy Log Analytics Workspace with daily cap using AVM
// Version: v0.2 (AVM Migration)
// AVM Module: br/public:avm/res/operational-insights/workspace:0.15.0
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
// Log Analytics Workspace (AVM Module)
// ============================================================================

@description('Log Analytics Workspace using AVM module with daily cap for cost control')
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'deploy-${workspaceName}'
  params: {
    name: workspaceName
    location: location
    tags: tags
    // SKU configuration
    skuName: 'PerGB2018'
    // Retention policy - 30 days for cost optimization
    dataRetention: 30
    // Daily cap for cost control (if > 0)
    dailyQuotaGb: dailyQuotaGbValue > 0 ? dailyQuotaGbValue : -1
    // Network access - enabled for SMB simplicity
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Log Analytics Workspace resource ID')
output workspaceId string = logAnalytics.outputs.resourceId

@description('Log Analytics Workspace name')
output workspaceName string = logAnalytics.outputs.name

@description('Log Analytics Workspace customer ID (for agent configuration)')
output workspaceCustomerId string = logAnalytics.outputs.logAnalyticsWorkspaceId
