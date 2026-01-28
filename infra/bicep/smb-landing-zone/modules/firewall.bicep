// ============================================================================
// SMB Landing Zone - Azure Firewall (Optional)
// ============================================================================
// Purpose: Deploy Azure Firewall Basic (cost-optimized)
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

@description('Azure Firewall Subnet resource ID')
param firewallSubnetId string

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var firewallName = 'fw-hub-${environment}-${regionShort}'
var firewallPolicyName = 'fwpol-hub-${environment}-${regionShort}'
var firewallPublicIpName = 'pip-fw-${environment}-${regionShort}'

// ============================================================================
// Firewall Public IP
// ============================================================================

@description('Public IP for Azure Firewall')
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: firewallPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ============================================================================
// Firewall Policy
// ============================================================================

@description('Firewall Policy with Basic tier')
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' = {
  name: firewallPolicyName
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Basic'
    }
    threatIntelMode: 'Alert'
  }
}

// ============================================================================
// Default Rule Collection Group
// ============================================================================

@description('Default network rule collection group')
resource defaultRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  parent: firewallPolicy
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'AllowAzureServices'
        priority: 100
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowAzureMonitor'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              '*'
            ]
            destinationAddresses: [
              'AzureMonitor'
            ]
            destinationPorts: [
              '443'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowAzureBackup'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              '*'
            ]
            destinationAddresses: [
              'AzureBackup'
            ]
            destinationPorts: [
              '443'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowAzureStorage'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              '*'
            ]
            destinationAddresses: [
              'Storage'
            ]
            destinationPorts: [
              '443'
            ]
          }
        ]
      }
    ]
  }
}

// ============================================================================
// Azure Firewall
// ============================================================================

@description('Azure Firewall with Basic SKU')
resource firewall 'Microsoft.Network/azureFirewalls@2024-01-01' = {
  name: firewallName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Basic'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          subnet: {
            id: firewallSubnetId
          }
          publicIPAddress: {
            id: firewallPublicIp.id
          }
        }
      }
    ]
  }
  dependsOn: [
    defaultRuleCollectionGroup
  ]
}

// ============================================================================
// Outputs
// ============================================================================

@description('Azure Firewall resource ID')
output firewallId string = firewall.id

@description('Azure Firewall name')
output firewallName string = firewall.name

@description('Azure Firewall private IP address')
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress

@description('Azure Firewall public IP address')
output firewallPublicIp string = firewallPublicIp.properties.ipAddress
