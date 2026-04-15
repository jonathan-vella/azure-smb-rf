// ============================================================================
// SMB Ready Foundation - Microsoft Defender for Cloud (Free Tier)
// ============================================================================
// Purpose: Enable Microsoft Defender for Cloud Free tier at subscription scope
// Version: v0.1
// ============================================================================
// The Free tier provides:
// - Security recommendations
// - Secure Score
// - Basic CSPM (Cloud Security Posture Management)
// - Security alerts for Azure resources
// No additional cost — included with Azure subscription.
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for Defender configuration (unused - Defender resources are global)')
#disable-next-line no-unused-params
param location string = 'swedencentral'

// ============================================================================
// Defender for Cloud - Free Tier Pricing Configuration
// ============================================================================
// Enable Free tier for key resource types. This registers the subscription
// with Defender and enables security recommendations without extra cost.

@description('Defender for Servers - Free tier (security recommendations only)')
resource defenderServers 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'VirtualMachines'
  properties: {
    pricingTier: 'Free'
  }
}

@description('Defender for Storage - Free tier')
resource defenderStorage 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'StorageAccounts'
  properties: {
    pricingTier: 'Free'
  }
}

@description('Defender for Key Vaults - Free tier')
resource defenderKeyVaults 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'KeyVaults'
  properties: {
    pricingTier: 'Free'
  }
}

@description('Defender for ARM - Free tier')
resource defenderArm 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'Arm'
  properties: {
    pricingTier: 'Free'
  }
}

// ============================================================================
// Security Contact Configuration
// ============================================================================

@description('Auto-provisioning of Log Analytics agent - disabled (use Azure Monitor Agent instead)')
resource autoProvision 'Microsoft.Security/autoProvisioningSettings@2017-08-01-preview' = {
  name: 'default'
  properties: {
    autoProvision: 'Off'
  }
}
