// ============================================================================
// Firewall Test Lab - Azure Firewall (Basic Tier)
// ============================================================================
// Purpose: Azure Firewall Basic with management IP configuration
// ============================================================================
// AVM Reference: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/azure-firewall
// ============================================================================
// Basic SKU Requirements:
// - Management NIC with AzureFirewallManagementSubnet: REQUIRED
// - Management Public IP: REQUIRED (separate from data IP)
// - Policy tier must match: Basic
// ============================================================================

@description('Azure region for deployment')
param location string

@description('AzureFirewallSubnet resource ID')
param firewallSubnetId string

@description('AzureFirewallManagementSubnet resource ID')
param firewallManagementSubnetId string

@description('Firewall Policy resource ID')
param firewallPolicyId string

@description('Tags')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var firewallName = 'fw-test-${location}'
var publicIpName = 'pip-fw-test-${location}'
var mgmtPublicIpName = 'pip-fw-mgmt-test-${location}'

// ============================================================================
// Public IP - Data Traffic
// ============================================================================

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: publicIpName
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
// Public IP - Management Traffic (Required for Basic SKU)
// ============================================================================

resource firewallMgmtPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: mgmtPublicIpName
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
// Azure Firewall (Basic Tier)
// ============================================================================

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
      id: firewallPolicyId
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
    // Management IP Configuration is REQUIRED for Basic SKU
    managementIpConfiguration: {
      name: 'fw-mgmt-ipconfig'
      properties: {
        subnet: {
          id: firewallManagementSubnetId
        }
        publicIPAddress: {
          id: firewallMgmtPublicIp.id
        }
      }
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Firewall resource ID')
output firewallId string = firewall.id

@description('Firewall name')
output firewallName string = firewall.name

@description('Firewall private IP address')
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress

@description('Firewall public IP address')
output firewallPublicIp string = firewallPublicIp.properties.ipAddress

@description('Firewall management public IP address')
output firewallMgmtPublicIp string = firewallMgmtPublicIp.properties.ipAddress
