// ============================================================================
// SMB Ready Foundations - Route Tables (AVM-based)
// ============================================================================
// Purpose: Deploy spoke (and optionally GatewaySubnet) route tables for
//          firewall-mediated traffic flows.
// Version: v0.4 (Adds full-scenario hybrid routing through firewall)
// AVM Module: br/public:avm/res/network/route-table:0.5.0
// ============================================================================
// Routing Requirements:
// - Spoke -> Internet: Always via Azure Firewall (0.0.0.0/0 -> FW)
// - Scenario `firewall` or `vpn` only:
//   * Spoke -> On-prem: gateway-propagated route from the VPN Gateway
//     (Local Network Gateway prefixes; BGP is disabled). Bypasses firewall.
//   * On-prem -> Spoke: direct via VPN Gateway, no GatewaySubnet UDR.
// - Scenario `full` (firewall + VPN, on-prem CIDR set):
//   * Spoke -> On-prem: more-specific UDR `onPremCIDR -> FW` overrides the
//     gateway-propagated route, forcing east-west through the firewall.
//   * On-prem -> Spoke: GatewaySubnet UDR `spokeCIDR -> FW` forces the
//     return path through the firewall (no 0.0.0.0/0 on GatewaySubnet —
//     that would break the VPN control plane).
//   Pair with bidirectional spoke<->on-prem allow rules in firewall.bicep.
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

@description('Azure Firewall private IP address for next hop')
param firewallPrivateIp string

@description('Tags to apply to all resources')
param tags object

@description('On-premises address space CIDR. When non-empty AND routeHybridThroughFirewall=true, a more-specific UDR is added on the spoke route table to force spoke->on-prem traffic through the firewall.')
param onPremisesAddressSpace string = ''

@description('Spoke VNet address space CIDR. Used as the destination prefix on the GatewaySubnet UDR so on-prem->spoke return traffic is forced through the firewall.')
param spokeVnetAddressSpace string = ''

@description('Hub VNet name (used to PATCH GatewaySubnet with the gateway route table when routeHybridThroughFirewall=true).')
param hubVnetName string = ''

@description('GatewaySubnet address prefix (must match the value in networking-hub when re-PATCHing the subnet to attach the gateway route table).')
param gatewaySubnetAddressPrefix string = ''

@description('Force spoke<->on-prem traffic through the firewall (scenario=full). Requires onPremisesAddressSpace, spokeVnetAddressSpace, hubVnetName, and gatewaySubnetAddressPrefix to be set.')
param routeHybridThroughFirewall bool = false

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var spokeRouteTableName = 'rt-spoke-${environment}-${regionShort}'
var gatewayRouteTableName = 'rt-gateway-${environment}-${regionShort}'

// Only attach the GatewaySubnet UDR when all required inputs are present.
var attachGatewayRouteTable = routeHybridThroughFirewall && !empty(onPremisesAddressSpace) && !empty(spokeVnetAddressSpace) && !empty(hubVnetName) && !empty(gatewaySubnetAddressPrefix)

// Spoke routes: always force internet via firewall; conditionally force on-prem via firewall.
var spokeBaseRoutes = [
  {
    name: 'route-to-internet-via-firewall'
    properties: {
      addressPrefix: '0.0.0.0/0'
      nextHopType: 'VirtualAppliance'
      nextHopIpAddress: firewallPrivateIp
    }
  }
]
var spokeHybridRoutes = (routeHybridThroughFirewall && !empty(onPremisesAddressSpace)) ? [
  {
    name: 'route-to-onprem-via-firewall'
    properties: {
      addressPrefix: onPremisesAddressSpace
      nextHopType: 'VirtualAppliance'
      nextHopIpAddress: firewallPrivateIp
    }
  }
] : []
var spokeRoutes = concat(spokeBaseRoutes, spokeHybridRoutes)

// ============================================================================
// Spoke Route Table (AVM Module)
// ============================================================================

@description('Route table for spoke subnets - forces internet egress (and optionally on-prem) through firewall')
module spokeRouteTable 'br/public:avm/res/network/route-table:0.5.0' = {
  name: 'deploy-${spokeRouteTableName}'
  params: {
    name: spokeRouteTableName
    location: location
    tags: tags
    // Keep gateway route propagation enabled: still needed in scenario=vpn (no
    // FW) and harmless in scenario=full (the more-specific on-prem UDR wins
    // over the gateway-propagated route).
    disableBgpRoutePropagation: false
    routes: spokeRoutes
  }
}

// ============================================================================
// GatewaySubnet Route Table (AVM Module - scenario=full only)
// ============================================================================
// Forces on-prem -> spoke return traffic through the firewall. CRITICAL: do
// NOT add a 0.0.0.0/0 route here — it would break the VPN Gateway control
// plane (gateway must reach Azure management endpoints directly).

@description('Route table for GatewaySubnet - forces on-prem->spoke return traffic through firewall (scenario=full)')
module gatewayRouteTable 'br/public:avm/res/network/route-table:0.5.0' = if (attachGatewayRouteTable) {
  name: 'deploy-${gatewayRouteTableName}'
  params: {
    name: gatewayRouteTableName
    location: location
    tags: tags
    // BGP propagation is irrelevant on GatewaySubnet (no remote gateway peer).
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'route-to-spoke-via-firewall'
        properties: {
          addressPrefix: spokeVnetAddressSpace
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

// ----------------------------------------------------------------------------
// Attach the gateway route table to the existing GatewaySubnet via a child
// subnet resource. We re-PUT the subnet with its addressPrefix + routeTable
// so this works even though the parent VNet is owned by networking-hub.bicep.
// Order: hub VNet (Phase 3) -> firewall (Phase 5) -> route-tables (this
// module) -> subnet PATCH below. Each Bicep run will momentarily reset the
// route table when networking-hub PUTs the VNet, then this PATCH re-applies
// it; final converged state is stable.
// ----------------------------------------------------------------------------

resource hubVnetExisting 'Microsoft.Network/virtualNetworks@2024-05-01' existing = if (attachGatewayRouteTable) {
  name: hubVnetName
}

resource gatewaySubnetWithUdr 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (attachGatewayRouteTable) {
  parent: hubVnetExisting
  name: 'GatewaySubnet'
  properties: {
    addressPrefix: gatewaySubnetAddressPrefix
    routeTable: {
      #disable-next-line BCP318
      id: gatewayRouteTable.outputs.resourceId
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Spoke route table resource ID')
output spokeRouteTableId string = spokeRouteTable.outputs.resourceId

@description('Spoke route table name')
output spokeRouteTableName string = spokeRouteTable.outputs.name

@description('Gateway route table resource ID (empty unless scenario=full)')
output gatewayRouteTableId string = attachGatewayRouteTable ? gatewayRouteTable.?outputs.?resourceId ?? '' : ''
