// ============================================================================
// SMB Landing Zone - Azure Migrate
// ============================================================================
// Purpose: Deploy Azure Migrate Project for VMware assessment
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

@description('Tags (not supported by Azure Migrate API, kept for interface consistency)')
#disable-next-line no-unused-params
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var projectName = 'migrate-smblz-${environment}-${regionShort}'

// ============================================================================
// Azure Migrate Project
// ============================================================================

@description('Azure Migrate Project for VMware discovery and assessment')
resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-05-01' = {
  name: projectName
  location: location
  // Note: Azure Migrate projects do not support tags at this API version
  properties: {}
}

// ============================================================================
// Outputs
// ============================================================================

@description('Azure Migrate Project resource ID')
output projectId string = migrateProject.id

@description('Azure Migrate Project name')
output projectName string = migrateProject.name
