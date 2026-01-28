// ============================================================================
// Firewall Test Lab - Virtual Network
// ============================================================================
// Purpose: Minimal hub VNet for Azure Firewall Basic testing
// ============================================================================

@description('Azure region for deployment')
param location string

@description('VNet address space')
param addressSpace string = '10.100.0.0/24'

@description('Include GatewaySubnet for VPN testing')
param includeGatewaySubnet bool = false

@description('Tags')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var vnetName = 'vnet-fw-test-${location}'

// Subnet layout for /24:
// - AzureFirewallSubnet: /26 (64 IPs) - index 0
// - AzureFirewallManagementSubnet: /26 (64 IPs) - index 1
// - GatewaySubnet: /27 (32 IPs) - index 4 of /27 (starts at .128)
var firewallSubnetPrefix = cidrSubnet(addressSpace, 26, 0)
var firewallMgmtSubnetPrefix = cidrSubnet(addressSpace, 26, 1)
var gatewaySubnetPrefix = cidrSubnet(addressSpace, 27, 4)  // 10.100.0.128/27

// ============================================================================
// Virtual Network
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    subnets: concat([
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetPrefix
          // No NSG allowed on AzureFirewallSubnet
        }
      }
      {
        name: 'AzureFirewallManagementSubnet'
        properties: {
          addressPrefix: firewallMgmtSubnetPrefix
          // No NSG or UDR allowed on AzureFirewallManagementSubnet
        }
      }
    ], includeGatewaySubnet ? [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
          // No NSG allowed on GatewaySubnet
        }
      }
    ] : [])
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('VNet resource ID')
output vnetId string = vnet.id

@description('VNet name')
output vnetName string = vnet.name

@description('AzureFirewallSubnet resource ID')
output firewallSubnetId string = vnet.properties.subnets[0].id

@description('AzureFirewallManagementSubnet resource ID')
output firewallManagementSubnetId string = vnet.properties.subnets[1].id

@description('GatewaySubnet resource ID (empty if not included)')
output gatewaySubnetId string = includeGatewaySubnet ? vnet.properties.subnets[2].id : ''
