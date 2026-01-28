// ============================================================================
// SMB Landing Zone - Resource Groups
// ============================================================================
// Purpose: Create 5 resource groups for landing zone workloads
// Version: v0.1
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for resource group deployment')
param location string

@description('Environment name for spoke resources')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Region abbreviation for naming')
param regionShort string

@description('Tags for shared services resource groups (Environment = slz)')
param sharedServicesTags object

@description('Tags for spoke resource group (Environment = dev/staging/prod)')
param spokeTags object

// ============================================================================
// Resource Groups - Shared Services (hardcoded 'slz')
// ============================================================================

@description('Hub resource group - VNet, Bastion, Firewall, VPN Gateway')
resource rgHub 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-hub-slz-${regionShort}'
  location: location
  tags: sharedServicesTags
}

@description('Monitoring resource group - Log Analytics')
resource rgMonitor 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-monitor-slz-${regionShort}'
  location: location
  tags: sharedServicesTags
}

@description('Backup resource group - Recovery Services Vault')
resource rgBackup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-backup-slz-${regionShort}'
  location: location
  tags: sharedServicesTags
}

@description('Migration resource group - Azure Migrate Project')
resource rgMigrate 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-migrate-slz-${regionShort}'
  location: location
  tags: sharedServicesTags
}

// ============================================================================
// Resource Groups - Spoke (environment-specific)
// ============================================================================

@description('Spoke resource group - Workload VNet, NAT Gateway')
resource rgSpoke 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-spoke-${environment}-${regionShort}'
  location: location
  tags: spokeTags
}

// ============================================================================
// Outputs
// ============================================================================

@description('Hub resource group name')
output hubResourceGroupName string = rgHub.name

@description('Hub resource group ID')
output hubResourceGroupId string = rgHub.id

@description('Spoke resource group name')
output spokeResourceGroupName string = rgSpoke.name

@description('Spoke resource group ID')
output spokeResourceGroupId string = rgSpoke.id

@description('Monitor resource group name')
output monitorResourceGroupName string = rgMonitor.name

@description('Monitor resource group ID')
output monitorResourceGroupId string = rgMonitor.id

@description('Backup resource group name')
output backupResourceGroupName string = rgBackup.name

@description('Backup resource group ID')
output backupResourceGroupId string = rgBackup.id

@description('Migrate resource group name')
output migrateResourceGroupName string = rgMigrate.name

@description('Migrate resource group ID')
output migrateResourceGroupId string = rgMigrate.id
