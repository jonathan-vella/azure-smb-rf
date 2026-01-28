// ============================================================================
// SMB Landing Zone - VPN Gateway (Optional)
// ============================================================================
// Purpose: Deploy VPN Gateway for hybrid connectivity
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

@description('Gateway Subnet resource ID')
param gatewaySubnetId string

@description('VPN Gateway SKU')
@allowed([
  'Basic'
  'VpnGw1AZ'
])
param vpnGatewaySku string = 'Basic'

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var gatewayName = 'vpng-hub-${environment}-${regionShort}'
var gatewayPublicIpName = 'pip-vpn-${environment}-${regionShort}'

// Determine if zone-redundant SKU
var isZoneRedundant = vpnGatewaySku == 'VpnGw1AZ'

// ============================================================================
// VPN Gateway Public IP
// ============================================================================

@description('Public IP for VPN Gateway')
resource gatewayPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: gatewayPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: isZoneRedundant ? ['1', '2', '3'] : []
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ============================================================================
// VPN Gateway
// ============================================================================

@description('VPN Gateway for hybrid connectivity')
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-01-01' = {
  name: gatewayName
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: vpnGatewaySku == 'Basic' ? 'None' : 'Generation1'
    sku: {
      name: vpnGatewaySku
      tier: vpnGatewaySku
    }
    enableBgp: false
    activeActive: false
    ipConfigurations: [
      {
        name: 'vpng-ipconfig'
        properties: {
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: gatewayPublicIp.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('VPN Gateway resource ID')
output gatewayId string = vpnGateway.id

@description('VPN Gateway name')
output gatewayName string = vpnGateway.name

@description('VPN Gateway public IP address')
output gatewayPublicIp string = gatewayPublicIp.properties.ipAddress

@description('VPN Gateway SKU')
output gatewaySku string = vpnGatewaySku
