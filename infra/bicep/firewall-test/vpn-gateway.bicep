// ============================================================================
// Firewall Test Lab - VPN Gateway (Basic SKU)
// ============================================================================
// Purpose: Test VPN Gateway Basic with Standard/Static public IP
// ============================================================================
// Azure Requirement (2024+):
// "New Basic SKU VPN gateways use the Static allocation method for public IP
// address and the Standard public IP address SKU."
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
// VPN Gateway Public IP
// ============================================================================
// Per Azure docs: Basic SKU VPN gateways now require Standard public IP
// with Static allocation method
// Note: Basic VPN SKU doesn't support zone-redundancy, so we omit zones
// However, some regions enforce zones for Standard IPs - in that case use VpnGw1AZ
// ============================================================================

resource vpnPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'  // Required for new Basic SKU VPN gateways
    tier: 'Regional'
  }
  // Zones required in regions that enforce it for Standard IPs
  // This makes the gateway effectively zone-pinned, but Basic SKU accepts it
  zones: ['1']
  properties: {
    publicIPAllocationMethod: 'Static'  // Required for new Basic SKU VPN gateways
    publicIPAddressVersion: 'IPv4'
  }
}

// ============================================================================
// VPN Gateway (Basic SKU)
// ============================================================================

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-01-01' = {
  name: gatewayName
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: {
      name: 'Basic'
      tier: 'Basic'
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
