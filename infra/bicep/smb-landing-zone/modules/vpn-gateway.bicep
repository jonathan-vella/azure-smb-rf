// ============================================================================
// SMB Landing Zone - VPN Gateway (AVM - Optional)
// ============================================================================
// Purpose: Deploy VPN Gateway VpnGw1AZ for hybrid connectivity
// Version: v0.3 (AVM Migration)
// AVM Modules:
//   - VPN Gateway: br/public:avm/res/network/virtual-network-gateway:0.10.1
// ============================================================================
// VpnGw1AZ: Zone-redundant, 650 Mbps, BGP support, ~$140/month
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

@description('Gateway Subnet resource ID')
param gatewaySubnetId string

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var gatewayName = 'vpng-hub-${environment}-${regionShort}'
var gatewayPublicIpName = 'pip-vpn-${environment}-${regionShort}'

// Extract VNet resource ID from Gateway Subnet ID
var vnetResourceId = split(gatewaySubnetId, '/subnets/')[0]

// ============================================================================
// VPN Gateway (AVM)
// ============================================================================

@description('VPN Gateway VpnGw1AZ for hybrid connectivity')
module vpnGateway 'br/public:avm/res/network/virtual-network-gateway:0.10.1' = {
  name: 'deploy-vpn-gateway'
  params: {
    name: gatewayName
    location: location
    tags: tags
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation1'
    skuName: 'VpnGw1AZ'
    // Required in AVM 0.10.1: virtualNetworkResourceId (replaces vNetResourceId)
    virtualNetworkResourceId: vnetResourceId
    // Required in AVM 0.10.1: clusterSettings with discriminator
    clusterSettings: {
      clusterMode: 'activePassiveNoBgp' // Active-passive without BGP (simplest config)
    }
    // Name for the auto-created public IP
    primaryPublicIPName: gatewayPublicIpName
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('VPN Gateway resource ID')
output gatewayId string = vpnGateway.outputs.resourceId

@description('VPN Gateway name')
output gatewayName string = vpnGateway.outputs.name

@description('VPN Gateway public IP address')
output gatewayPublicIp string = vpnGateway.outputs.?primaryPublicIpAddress ?? ''
