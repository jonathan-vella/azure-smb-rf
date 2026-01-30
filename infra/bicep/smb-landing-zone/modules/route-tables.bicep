// ============================================================================
// SMB Landing Zone - Route Tables (AVM-based)
// ============================================================================
// Purpose: Deploy route tables for forced tunneling through Azure Firewall
// Version: v0.2 (AVM Migration)
// AVM Module: br/public:avm/res/network/route-table:0.5.0
// ============================================================================
// Routing Requirements:
// - Spoke → Internet: Via Azure Firewall (0.0.0.0/0 → FW)
// - Spoke → On-prem: Via Azure Firewall
// - On-prem → Azure: Via Azure Firewall (Gateway UDR)
// - On-prem → Internet: Direct (no Azure routing required)
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

@description('Azure Firewall private IP address for next hop')
param firewallPrivateIp string

@description('Spoke VNet address space (for Gateway UDR)')
param spokeAddressSpace string

@description('On-premises address space (optional, for spoke routing)')
param onPremisesAddressSpace string = ''

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var spokeRouteTableName = 'rt-spoke-${environment}-${regionShort}'
var gatewayRouteTableName = 'rt-gateway-${environment}-${regionShort}'

// Determine if on-prem routes are needed
var hasOnPremises = !empty(onPremisesAddressSpace)

// ============================================================================
// Spoke Route Table (AVM Module)
// ============================================================================
// Forces all spoke traffic through Azure Firewall:
// - 0.0.0.0/0 (internet) → Firewall
// - On-prem CIDR (if VPN) → Firewall
// ============================================================================

@description('Route table for spoke subnets using AVM - forces traffic through firewall')
module spokeRouteTable 'br/public:avm/res/network/route-table:0.5.0' = {
  name: 'deploy-${spokeRouteTableName}'
  params: {
    name: spokeRouteTableName
    location: location
    tags: tags
    // Allow BGP routes from VPN Gateway
    disableBgpRoutePropagation: false
    // Routes for spoke subnets
    routes: concat(
      [
        {
          name: 'route-to-internet-via-firewall'
          properties: {
            addressPrefix: '0.0.0.0/0'
            nextHopType: 'VirtualAppliance'
            nextHopIpAddress: firewallPrivateIp
          }
        }
      ],
      // Add on-prem route only if VPN is configured
      hasOnPremises ? [
        {
          name: 'route-to-onprem-via-firewall'
          properties: {
            addressPrefix: onPremisesAddressSpace
            nextHopType: 'VirtualAppliance'
            nextHopIpAddress: firewallPrivateIp
          }
        }
      ] : []
    )
  }
}

// ============================================================================
// Gateway Route Table (AVM Module - Conditional)
// ============================================================================
// Forces on-prem → Azure traffic through Azure Firewall
// Only deployed when VPN is configured (on-prem exists)
// ============================================================================

@description('Route table for GatewaySubnet using AVM - forces on-prem to Azure traffic through firewall')
module gatewayRouteTable 'br/public:avm/res/network/route-table:0.5.0' = if (hasOnPremises) {
  name: 'deploy-${gatewayRouteTableName}'
  params: {
    name: gatewayRouteTableName
    location: location
    tags: tags
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'route-to-spoke-via-firewall'
        properties: {
          addressPrefix: spokeAddressSpace
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Spoke route table resource ID')
output spokeRouteTableId string = spokeRouteTable.outputs.resourceId

@description('Spoke route table name')
output spokeRouteTableName string = spokeRouteTable.outputs.name

@description('Gateway route table resource ID (empty if no VPN)')
output gatewayRouteTableId string = gatewayRouteTable.?outputs.?resourceId ?? ''

@description('Gateway route table name (empty if no VPN)')
output gatewayRouteTableName string = gatewayRouteTable.?outputs.?name ?? ''
