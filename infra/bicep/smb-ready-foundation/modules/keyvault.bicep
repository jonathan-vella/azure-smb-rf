// ============================================================================
// SMB Ready Foundations - Key Vault with Private Endpoint
// ============================================================================
// Purpose: Deploy Azure Key Vault (Standard) with RBAC, soft delete,
//          purge protection, private endpoint in spoke VNet, and
//          diagnostic settings to Log Analytics.
// Version: v0.1
// AVM Module: br/public:avm/res/key-vault/vault:0.13.3
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for resource deployment')
param location string

@description('Region abbreviation for naming')
param regionShort string

@description('Environment name (dev/staging/prod) — included in the Key Vault and private endpoint names so each environment gets its own vault and PE.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Unique suffix for globally unique Key Vault name')
param uniqueSuffix string

@description('Private endpoint subnet resource ID (spoke snet-pep)')
param pepSubnetId string

@description('Log Analytics Workspace resource ID for diagnostic settings')
param logAnalyticsWorkspaceId string

@description('Spoke VNet resource ID. Linked to the Key Vault private DNS zone so workloads in the spoke resolve the private endpoint IP.')
param spokeVnetId string

@description('Hub VNet resource ID. Linked to the Key Vault private DNS zone so on-prem clients (via VPN) and any hub-resident DNS resolver return the private endpoint IP. Optional — leave empty to skip the hub link.')
param hubVnetId string = ''

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Abbreviate 'staging' to 'stg' so the 24-char Key Vault name budget isn't
// blown by the environment segment alone.
var envShort = environment == 'staging' ? 'stg' : environment

// Key Vault names are globally unique and capped at 24 characters. Including
// the environment ensures dev/staging/prod each get a distinct vault (and
// therefore distinct private endpoints in their own spoke subnets). take()
// guards against the 24-char ceiling as a defence-in-depth.
var keyVaultName = take('kv-${envShort}-${regionShort}-${uniqueSuffix}', 24)
var pepName = 'pep-kv-${envShort}-${regionShort}'

// ============================================================================
// Key Vault (AVM Module)
// ============================================================================

@description('Key Vault with RBAC, soft delete, purge protection, and private endpoint')
module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
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
module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  name: 'deploy-pdz-keyvault'
  params: {
    name: 'privatelink.vaultcore.azure.net'
    location: 'global'
    tags: tags
    // Without these links, clients in the spoke (and on-prem via the hub)
    // resolve `*.vaultcore.azure.net` to the public name and fail because
    // publicNetworkAccess is disabled.
    virtualNetworkLinks: concat(
      [
        {
          name: 'link-spoke'
          virtualNetworkResourceId: spokeVnetId
          registrationEnabled: false
        }
      ],
      empty(hubVnetId) ? [] : [
        {
          name: 'link-hub'
          virtualNetworkResourceId: hubVnetId
          registrationEnabled: false
        }
      ]
    )
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
