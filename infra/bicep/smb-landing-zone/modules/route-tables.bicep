// ============================================================================
// SMB Landing Zone - Route Tables (UDRs)
// ============================================================================
// Purpose: Deploy route tables for forced tunneling through Azure Firewall
// Version: v0.1
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
// Spoke Route Table
// ============================================================================
// Forces all spoke traffic through Azure Firewall:
// - 0.0.0.0/0 (internet) → Firewall
// - On-prem CIDR (if VPN) → Firewall
// ============================================================================

@description('Route table for spoke subnets - forces traffic through firewall')
resource spokeRouteTable 'Microsoft.Network/routeTables@2024-01-01' = {
  name: spokeRouteTableName
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false // Allow BGP routes from VPN Gateway
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
// Gateway Route Table (Conditional)
// ============================================================================
// Forces on-prem → Azure traffic through Azure Firewall
// Only deployed when VPN is configured (on-prem exists)
// ============================================================================

@description('Route table for GatewaySubnet - forces on-prem to Azure traffic through firewall')
resource gatewayRouteTable 'Microsoft.Network/routeTables@2024-01-01' = if (hasOnPremises) {
  name: gatewayRouteTableName
  location: location
  tags: tags
  properties: {
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
output spokeRouteTableId string = spokeRouteTable.id

@description('Spoke route table name')
output spokeRouteTableName string = spokeRouteTable.name

@description('Gateway route table resource ID (empty if no VPN)')
output gatewayRouteTableId string = hasOnPremises ? gatewayRouteTable.id : ''

@description('Gateway route table name (empty if no VPN)')
output gatewayRouteTableName string = hasOnPremises ? gatewayRouteTable.name : ''
