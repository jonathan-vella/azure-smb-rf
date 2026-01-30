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

// Daily cap - pass as-is since AVM expects string, or '-1' to disable
// If dailyCapGb is '0' or empty, we pass '-1' to indicate no cap
var dailyQuotaGbString = !empty(dailyCapGb) && dailyCapGb != '0' ? dailyCapGb : '-1'

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
    // Daily cap for cost control - AVM expects string format or -1 for no cap
    dailyQuotaGb: dailyQuotaGbString
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
