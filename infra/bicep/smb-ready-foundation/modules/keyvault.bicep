// ============================================================================
// SMB Ready Foundation - Key Vault with Private Endpoint
// ============================================================================
// Purpose: Deploy Azure Key Vault (Standard) with RBAC, soft delete,
//          purge protection, private endpoint in spoke VNet, and
//          diagnostic settings to Log Analytics.
// Version: v0.1
// AVM Module: br/public:avm/res/key-vault/vault:0.11.0
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for resource deployment')
param location string

@description('Region abbreviation for naming')
param regionShort string

@description('Unique suffix for globally unique Key Vault name')
param uniqueSuffix string

@description('Private endpoint subnet resource ID (spoke snet-pep)')
param pepSubnetId string

@description('Log Analytics Workspace resource ID for diagnostic settings')
param logAnalyticsWorkspaceId string

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

var keyVaultName = 'kv-smbrf-${regionShort}-${take(uniqueSuffix, 8)}'
var pepName = 'pep-kv-smbrf-smb-${regionShort}'

// ============================================================================
// Key Vault (AVM Module)
// ============================================================================

@description('Key Vault with RBAC, soft delete, purge protection, and private endpoint')
module keyVault 'br/public:avm/res/key-vault/vault:0.11.0' = {
  name: 'deploy-${keyVaultName}'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    // RBAC permission model (no access policies)
    enableRbacAuthorization: true
    // Soft delete with 90-day retention
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    // Purge protection — prevents permanent deletion
    enablePurgeProtection: true
    // Disable public network access — private endpoint only
    publicNetworkAccess: 'Disabled'
    // Allow Azure services to bypass network rules (ARM deployments)
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    // SKU
    sku: 'standard'
    // Private endpoint in spoke PE subnet
    privateEndpoints: [
      {
        name: pepName
        subnetResourceId: pepSubnetId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
    // Diagnostic settings to Log Analytics
    diagnosticSettings: [
      {
        name: 'kv-diag-law'
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
// Private DNS Zone for Key Vault
// ============================================================================

@description('Private DNS Zone for Key Vault private endpoint resolution')
module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'deploy-pdz-keyvault'
  params: {
    name: 'privatelink.vaultcore.azure.net'
    location: 'global'
    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Key Vault resource ID')
output keyVaultId string = keyVault.outputs.resourceId

@description('Key Vault name')
output keyVaultName string = keyVault.outputs.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.uri

@description('Private DNS Zone resource ID')
output privateDnsZoneId string = privateDnsZone.outputs.resourceId
