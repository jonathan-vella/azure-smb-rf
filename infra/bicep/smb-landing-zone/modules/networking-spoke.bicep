// ============================================================================
// SMB Landing Zone - Spoke Networking (AVM)
// ============================================================================
// Purpose: Deploy spoke VNet with conditional NAT Gateway or UDR for firewall
// Version: v0.3 (AVM Migration)
// AVM Modules:
//   - Virtual Network: br/public:avm/res/network/virtual-network:0.7.2
//   - NSG: br/public:avm/res/network/network-security-group:0.5.2
//   - NAT Gateway: br/public:avm/res/network/nat-gateway:2.0.1
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
// Network Security Group (AVM)
// ============================================================================

@description('Spoke NSG with default deny inbound rules')
module spokeNsg 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'deploy-spoke-nsg'
  params: {
    name: nsgName
    location: location
    tags: tags
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
// NAT Gateway (AVM - Conditional)
// ============================================================================

@description('NAT Gateway for outbound internet (only deployed when no firewall)')
module natGateway 'br/public:avm/res/network/nat-gateway:2.0.1' = if (deployNatGateway) {
  name: 'deploy-nat-gateway'
  params: {
    name: natGatewayName
    location: location
    tags: tags
    idleTimeoutInMinutes: 4
    // Required: -1 for no zone, or 1/2/3 for specific zone
    availabilityZone: -1
    // AVM NAT Gateway module creates public IPs automatically via publicIPAddresses array
    publicIPAddresses: [
      {
        name: 'pip-nat-${environment}-${regionShort}'
        skuName: 'Standard'
        publicIPAllocationMethod: 'Static'
      }
    ]
  }
}

// ============================================================================
// Spoke Virtual Network (AVM)
// ============================================================================

@description('Spoke VNet with workload subnets')
module spokeVnet 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'deploy-spoke-vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: [
      vnetAddressSpace
    ]
    subnets: [
      {
        name: 'snet-workload'
        addressPrefix: workloadSubnetPrefix
        networkSecurityGroupResourceId: spokeNsg.outputs.resourceId
        natGatewayResourceId: deployNatGateway ? natGateway.outputs.resourceId : null
        routeTableResourceId: hasRouteTable ? routeTableId : null
      }
      {
        name: 'snet-data'
        addressPrefix: dataSubnetPrefix
        networkSecurityGroupResourceId: spokeNsg.outputs.resourceId
        natGatewayResourceId: deployNatGateway ? natGateway.outputs.resourceId : null
        routeTableResourceId: hasRouteTable ? routeTableId : null
      }
      {
        name: 'snet-app'
        addressPrefix: appSubnetPrefix
        networkSecurityGroupResourceId: spokeNsg.outputs.resourceId
        natGatewayResourceId: deployNatGateway ? natGateway.outputs.resourceId : null
        routeTableResourceId: hasRouteTable ? routeTableId : null
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Spoke VNet resource ID')
output vnetId string = spokeVnet.outputs.resourceId

@description('Spoke VNet name')
output vnetName string = spokeVnet.outputs.name

@description('Workload Subnet resource ID')
output workloadSubnetId string = spokeVnet.outputs.subnetResourceIds[0]

@description('Data Subnet resource ID')
output dataSubnetId string = spokeVnet.outputs.subnetResourceIds[1]

@description('App Subnet resource ID')
output appSubnetId string = spokeVnet.outputs.subnetResourceIds[2]

@description('Spoke NSG resource ID')
output nsgId string = spokeNsg.outputs.resourceId

@description('NAT Gateway resource ID (empty if firewall deployed)')
output natGatewayId string = deployNatGateway ? natGateway.outputs.resourceId : ''

@description('NAT Gateway name (empty if firewall deployed)')
output natGatewayName string = deployNatGateway ? natGateway.outputs.name : ''
