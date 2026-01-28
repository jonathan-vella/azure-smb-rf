// ============================================================================
// SMB Landing Zone - Hub Networking
// ============================================================================
// Purpose: Deploy hub VNet with NSG and Private DNS Zone
// Version: v0.2
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
// Network Security Group
// ============================================================================

@description('Hub NSG with default deny inbound rules')
resource hubNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
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
// Hub Virtual Network
// ============================================================================

@description('Hub VNet with reserved subnets for Firewall, Firewall Management, and Gateway')
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetPrefix
          // Firewall subnet does not support NSG
        }
      }
      {
        name: 'AzureFirewallManagementSubnet'
        properties: {
          addressPrefix: firewallMgmtSubnetPrefix
          // Required for Azure Firewall Basic SKU - management traffic
          // Does not support NSG or UDR
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
          // Gateway subnet does not support NSG
        }
      }
      {
        name: 'snet-management'
        properties: {
          addressPrefix: managementSubnetPrefix
          networkSecurityGroup: {
            id: hubNsg.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// Private DNS Zone
// ============================================================================

@description('Private DNS Zone for Azure Private Link endpoints')
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
  properties: {}
}

@description('Link Private DNS Zone to Hub VNet')
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: 'link-${vnetName}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
    registrationEnabled: true
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Hub VNet resource ID')
output vnetId string = hubVnet.id

@description('Hub VNet name')
output vnetName string = hubVnet.name

@description('Azure Firewall Subnet resource ID')
output firewallSubnetId string = hubVnet.properties.subnets[0].id

@description('Azure Firewall Management Subnet resource ID (required for Basic SKU)')
output firewallManagementSubnetId string = hubVnet.properties.subnets[1].id

@description('Gateway Subnet resource ID')
output gatewaySubnetId string = hubVnet.properties.subnets[2].id

@description('Management Subnet resource ID')
output managementSubnetId string = hubVnet.properties.subnets[3].id

@description('Hub NSG resource ID')
output nsgId string = hubNsg.id

@description('Private DNS Zone resource ID')
output privateDnsZoneId string = privateDnsZone.id
