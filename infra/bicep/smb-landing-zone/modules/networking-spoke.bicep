// ============================================================================
// SMB Landing Zone - Spoke Networking
// ============================================================================
// Purpose: Deploy spoke VNet with NAT Gateway and NSG
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

@description('Spoke VNet address space CIDR')
param vnetAddressSpace string

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
// Assuming 10.1.0.0/16:
// - WorkloadSubnet: 10.1.0.0/24 (256 addresses)
// - DataSubnet: 10.1.1.0/24 (256 addresses)
// - AppSubnet: 10.1.2.0/24 (256 addresses)
var workloadSubnetPrefix = cidrSubnet(vnetAddressSpace, 24, 0)
var dataSubnetPrefix = cidrSubnet(vnetAddressSpace, 24, 1)
var appSubnetPrefix = cidrSubnet(vnetAddressSpace, 24, 2)

// ============================================================================
// NAT Gateway Public IP
// ============================================================================

@description('Public IP for NAT Gateway (Standard SKU, Static allocation)')
resource natPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
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
// NAT Gateway
// ============================================================================

@description('NAT Gateway for secure outbound internet access')
resource natGateway 'Microsoft.Network/natGateways@2024-01-01' = {
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

@description('Spoke VNet with workload subnets and NAT Gateway')
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
          natGateway: {
            id: natGateway.id
          }
        }
      }
      {
        name: 'snet-data'
        properties: {
          addressPrefix: dataSubnetPrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
          natGateway: {
            id: natGateway.id
          }
        }
      }
      {
        name: 'snet-app'
        properties: {
          addressPrefix: appSubnetPrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
          natGateway: {
            id: natGateway.id
          }
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

@description('NAT Gateway resource ID')
output natGatewayId string = natGateway.id

@description('NAT Gateway public IP address')
output natGatewayPublicIp string = natPublicIp.properties.ipAddress
