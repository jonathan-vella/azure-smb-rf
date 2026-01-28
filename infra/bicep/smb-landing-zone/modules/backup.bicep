// ============================================================================
// SMB Landing Zone - Backup
// ============================================================================
// Purpose: Deploy Recovery Services Vault for VM backup
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

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var vaultName = 'rsv-smblz-${environment}-${regionShort}'

// ============================================================================
// Recovery Services Vault
// ============================================================================

@description('Recovery Services Vault for VM backup with LRS storage')
resource recoveryVault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: vaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    securitySettings: {
      softDeleteSettings: {
        softDeleteState: 'Enabled'
        softDeleteRetentionPeriodInDays: 14
      }
    }
    // Note: Storage redundancy (LRS/GRS) is configured at vault creation and cannot be changed
    // For new vaults, default is GRS. For cost optimization, use Azure CLI during initial setup:
    // az backup vault backup-properties set --resource-group $rg --name $vault --backup-storage-redundancy LocallyRedundant
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Recovery Services Vault resource ID')
output vaultId string = recoveryVault.id

@description('Recovery Services Vault name')
output vaultName string = recoveryVault.name
