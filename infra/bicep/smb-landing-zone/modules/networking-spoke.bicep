// ============================================================================
// SMB Landing Zone - Spoke Networking
// ============================================================================
// Purpose: Deploy spoke VNet with conditional NAT Gateway or UDR for firewall
// Version: v0.2
// ============================================================================
// Routing Logic:
// - If firewall deployed: Use UDR to route traffic through firewall
// - If no firewall: Use NAT Gateway for outbound internet
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

@description('Spoke VNet address space CIDR')
param vnetAddressSpace string

@description('Deploy NAT Gateway (false when firewall handles outbound)')
param deployNatGateway bool = true

@description('Route table ID to associate with subnets (when using firewall)')
param routeTableId string = ''

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var vnetName = 'vnet-spoke-${environment}-${regionShort}'
var nsgName = 'nsg-spoke-${environment}-${regionShort}'
var natGatewayName = 'nat-spoke-${environment}-${regionShort}'
var natPublicIpName = 'pip-nat-${environment}-${regionShort}'

// Subnet address ranges (derived from VNet address space)
// Using /25 subnets (128 addresses each) to fit within /23 VNet:
// For 10.0.2.0/23:
// - WorkloadSubnet: 10.0.2.0/25 (128 addresses)
// - DataSubnet: 10.0.2.128/25 (128 addresses)
// - AppSubnet: 10.0.3.0/25 (128 addresses)
// - Reserved: 10.0.3.128/25 (128 addresses for future use)
var workloadSubnetPrefix = cidrSubnet(vnetAddressSpace, 25, 0)
var dataSubnetPrefix = cidrSubnet(vnetAddressSpace, 25, 1)
var appSubnetPrefix = cidrSubnet(vnetAddressSpace, 25, 2)

// Determine if UDR should be applied
var hasRouteTable = !empty(routeTableId)

// ============================================================================
// NAT Gateway Public IP (Conditional)
// ============================================================================

@description('Public IP for NAT Gateway (only deployed when no firewall)')
resource natPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = if (deployNatGateway) {
  name: natPublicIpName
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
// NAT Gateway (Conditional)
// ============================================================================

@description('NAT Gateway for outbound internet (only deployed when no firewall)')
resource natGateway 'Microsoft.Network/natGateways@2024-01-01' = if (deployNatGateway) {
  name: natGatewayName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
    idleTimeoutInMinutes: 4
  }
}

// ============================================================================
// Network Security Group
// ============================================================================

@description('Spoke NSG with default deny inbound rules')
resource spokeNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          description: 'Allow inbound traffic within VNet'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          description: 'Allow Azure Load Balancer health probes'
        }
      }
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
// Spoke Virtual Network
// ============================================================================

@description('Spoke VNet with workload subnets')
resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
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
        name: 'snet-workload'
        properties: {
          addressPrefix: workloadSubnetPrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
          // Use NAT Gateway if deployed, otherwise rely on UDR for firewall routing
          natGateway: deployNatGateway ? {
            id: natGateway.id
          } : null
          // Apply route table if provided (when using firewall)
          routeTable: hasRouteTable ? {
            id: routeTableId
          } : null
        }
      }
      {
        name: 'snet-data'
        properties: {
          addressPrefix: dataSubnetPrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
          natGateway: deployNatGateway ? {
            id: natGateway.id
          } : null
          routeTable: hasRouteTable ? {
            id: routeTableId
          } : null
        }
      }
      {
        name: 'snet-app'
        properties: {
          addressPrefix: appSubnetPrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
          natGateway: deployNatGateway ? {
            id: natGateway.id
          } : null
          routeTable: hasRouteTable ? {
            id: routeTableId
          } : null
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Spoke VNet resource ID')
output vnetId string = spokeVnet.id

@description('Spoke VNet name')
output vnetName string = spokeVnet.name

@description('Workload Subnet resource ID')
output workloadSubnetId string = spokeVnet.properties.subnets[0].id

@description('Data Subnet resource ID')
output dataSubnetId string = spokeVnet.properties.subnets[1].id

@description('App Subnet resource ID')
output appSubnetId string = spokeVnet.properties.subnets[2].id

@description('Spoke NSG resource ID')
output nsgId string = spokeNsg.id

@description('NAT Gateway resource ID (empty if firewall deployed)')
#disable-next-line BCP318
output natGatewayId string = deployNatGateway ? natGateway.id : ''

@description('NAT Gateway public IP address (empty if firewall deployed)')
#disable-next-line BCP318
output natGatewayPublicIp string = deployNatGateway ? natPublicIp.properties.ipAddress : ''
