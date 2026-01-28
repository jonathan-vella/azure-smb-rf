// ============================================================================
// Firewall Test Lab - VPN Gateway (VpnGw1AZ SKU)
// ============================================================================
// Purpose: Test VPN Gateway VpnGw1AZ (zone-redundant)
// ============================================================================
// VpnGw1AZ requires:
// - Standard public IP with Static allocation
// - Zones ['1', '2', '3'] for zone-redundancy
// - Generation1 gateway
// ============================================================================

@description('Azure region for deployment')
param location string

@description('GatewaySubnet resource ID')
param gatewaySubnetId string

@description('Tags')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var gatewayName = 'vpng-test-${location}'
var publicIpName = 'pip-vpn-test-${location}'

// ============================================================================
// VPN Gateway Public IP (Zone-Redundant)
// ============================================================================

resource vpnPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: ['1', '2', '3']  // Zone-redundant for VpnGw1AZ
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ============================================================================
// VPN Gateway (VpnGw1AZ - Zone-Redundant)
// ============================================================================

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-01-01' = {
  name: gatewayName
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation1'
    sku: {
      name: 'VpnGw1AZ'
      tier: 'VpnGw1AZ'
    }
    enableBgp: false
    activeActive: false
    ipConfigurations: [
      {
        name: 'vpng-ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: vpnPublicIp.id
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
output gatewayPublicIp string = vpnPublicIp.properties.ipAddress
