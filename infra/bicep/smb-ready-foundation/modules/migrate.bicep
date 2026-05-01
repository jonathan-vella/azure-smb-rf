// ============================================================================
// SMB Ready Foundations - Azure Migrate
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
  'smb'
  'smb'
])
param environment string

@description('Region abbreviation for naming')
param regionShort string

@description('Tags applied to the Azure Migrate project')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var projectName = 'migrate-smbrf-${environment}-${regionShort}'

// ============================================================================
// Azure Migrate Project
// ============================================================================

@description('Azure Migrate Project for VMware discovery and assessment')
resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-05-01' = {
  name: projectName
  location: location
  tags: tags
  properties: {}
}

// ============================================================================
// Outputs
// ============================================================================

@description('Azure Migrate Project resource ID')
output projectId string = migrateProject.id

@description('Azure Migrate Project name')
output projectName string = migrateProject.name
