// ============================================================================
// SMB Ready Foundation - Hub Networking (AVM)
// ============================================================================
// Purpose: Deploy hub VNet with NSG and Private DNS Zone using Azure Verified Modules
// Version: v0.3 (AVM Migration)
// AVM Modules:
//   - Virtual Network: br/public:avm/res/network/virtual-network:0.7.2
//   - NSG: br/public:avm/res/network/network-security-group:0.5.2
//   - Private DNS Zone: br/public:avm/res/network/private-dns-zone:0.8.0
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
])
param environment string

@description('Region abbreviation for naming')
param regionShort string

@description('Hub VNet address space CIDR')
param vnetAddressSpace string

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var vnetName = 'vnet-hub-${environment}-${regionShort}'
var nsgName = 'nsg-hub-${environment}-${regionShort}'
var privateDnsZoneName = 'privatelink.azure.com'

// Subnet address ranges (derived from VNet address space)
// Designed for /23 VNet (512 IPs) with service subnets:
// For 10.0.0.0/23 (10.0.0.0 - 10.0.1.255):
// - AzureFirewallSubnet: 10.0.0.0/26 (64 addresses, index 0)
// - AzureFirewallManagementSubnet: 10.0.0.64/26 (64 addresses, index 1) - Required for Basic SKU
// - snet-management: 10.0.0.128/26 (64 addresses, index 2)
// - GatewaySubnet: 10.0.0.192/27 (32 addresses, index 6 of /27)
// Remaining: 10.0.0.224 - 10.0.1.255 (288 addresses for future use)
var firewallSubnetPrefix = cidrSubnet(vnetAddressSpace, 26, 0)          // /26 = 64 IPs
var firewallMgmtSubnetPrefix = cidrSubnet(vnetAddressSpace, 26, 1)      // /26 = 64 IPs (required for Basic)
var managementSubnetPrefix = cidrSubnet(vnetAddressSpace, 26, 2)        // /26 = 64 IPs
var gatewaySubnetPrefix = cidrSubnet(vnetAddressSpace, 27, 6)           // /27 = 32 IPs (starts at 10.0.0.192)

// ============================================================================
// Network Security Group (AVM)
// ============================================================================

@description('Hub NSG with default deny inbound rules')
module hubNsg 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'deploy-hub-nsg'
  params: {
    name: nsgName
    location: location
    tags: tags
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Default deny all inbound traffic'
        }
      }
    ]
  }
}

// ============================================================================
// Hub Virtual Network (AVM)
// ============================================================================

@description('Hub VNet with reserved subnets for Firewall, Firewall Management, and Gateway')
module hubVnet 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'deploy-hub-vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: [
      vnetAddressSpace
    ]
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        addressPrefix: firewallSubnetPrefix
        // Firewall subnet does not support NSG
      }
      {
        name: 'AzureFirewallManagementSubnet'
        addressPrefix: firewallMgmtSubnetPrefix
        // Required for Azure Firewall Basic SKU - management traffic
        // Does not support NSG or UDR
      }
      {
        name: 'GatewaySubnet'
        addressPrefix: gatewaySubnetPrefix
        // Gateway subnet does not support NSG
      }
      {
        name: 'snet-management'
        addressPrefix: managementSubnetPrefix
        networkSecurityGroupResourceId: hubNsg.outputs.resourceId
      }
    ]
  }
}

// ============================================================================
// Private DNS Zone (AVM)
// ============================================================================

@description('Private DNS Zone for Azure Private Link endpoints')
module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'deploy-private-dns-zone'
  params: {
    name: privateDnsZoneName
    location: 'global'
    tags: tags
    virtualNetworkLinks: [
      {
        name: 'link-${vnetName}'
        virtualNetworkResourceId: hubVnet.outputs.resourceId
        registrationEnabled: true
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Hub VNet resource ID')
output vnetId string = hubVnet.outputs.resourceId

@description('Hub VNet name')
output vnetName string = hubVnet.outputs.name

@description('Azure Firewall Subnet resource ID')
output firewallSubnetId string = hubVnet.outputs.subnetResourceIds[0]

@description('Azure Firewall Management Subnet resource ID (required for Basic SKU)')
output firewallManagementSubnetId string = hubVnet.outputs.subnetResourceIds[1]

@description('Gateway Subnet resource ID')
output gatewaySubnetId string = hubVnet.outputs.subnetResourceIds[2]

@description('Management Subnet resource ID')
output managementSubnetId string = hubVnet.outputs.subnetResourceIds[3]

@description('Hub NSG resource ID')
output nsgId string = hubNsg.outputs.resourceId

@description('Private DNS Zone resource ID')
output privateDnsZoneId string = privateDnsZone.outputs.resourceId
