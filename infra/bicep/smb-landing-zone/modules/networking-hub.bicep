// ============================================================================
// SMB Landing Zone - Hub Networking
// ============================================================================
// Purpose: Deploy hub VNet with Bastion, NSG, and Private DNS Zone
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
var bastionName = 'bas-hub-${environment}-${regionShort}'
var privateDnsZoneName = 'privatelink.azure.com'

// Subnet address ranges (derived from VNet address space)
// Assuming 10.0.0.0/16:
// - AzureBastionSubnet: 10.0.0.0/26 (64 addresses)
// - AzureFirewallSubnet: 10.0.0.64/26 (64 addresses, reserved)
// - GatewaySubnet: 10.0.0.128/27 (32 addresses, reserved)
// - ManagementSubnet: 10.0.1.0/24 (256 addresses)
var bastionSubnetPrefix = cidrSubnet(vnetAddressSpace, 26, 0)      // /26
var firewallSubnetPrefix = cidrSubnet(vnetAddressSpace, 26, 1)     // /26
var gatewaySubnetPrefix = cidrSubnet(vnetAddressSpace, 27, 4)      // /27
var managementSubnetPrefix = cidrSubnet(vnetAddressSpace, 24, 1)   // /24

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

@description('Hub VNet with reserved subnets for Bastion, Firewall, and Gateway')
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
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          // Bastion subnet does not support NSG
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetPrefix
          // Firewall subnet does not support NSG
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
// Azure Bastion (Developer SKU)
// ============================================================================

@description('Azure Bastion with Developer SKU (cost-optimized, no public IP required)')
resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
  }
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
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

@description('Azure Bastion Subnet resource ID')
output bastionSubnetId string = hubVnet.properties.subnets[0].id

@description('Azure Firewall Subnet resource ID')
output firewallSubnetId string = hubVnet.properties.subnets[1].id

@description('Gateway Subnet resource ID')
output gatewaySubnetId string = hubVnet.properties.subnets[2].id

@description('Management Subnet resource ID')
output managementSubnetId string = hubVnet.properties.subnets[3].id

@description('Hub NSG resource ID')
output nsgId string = hubNsg.id

@description('Azure Bastion resource ID')
output bastionId string = bastion.id

@description('Azure Bastion name')
output bastionName string = bastion.name

@description('Private DNS Zone resource ID')
output privateDnsZoneId string = privateDnsZone.id
