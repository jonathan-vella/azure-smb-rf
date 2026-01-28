// ============================================================================
// SMB Landing Zone - Spoke to Hub Peering (Helper Module)
// ============================================================================
// Purpose: Configure spoke to hub VNet peering from spoke resource group
// Version: v0.1
// Note: This module is called by networking-peering.bicep for cross-RG peering
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Spoke VNet name')
param spokeVnetName string

@description('Hub VNet resource ID')
param hubVnetId string

@description('Use remote gateway (requires VPN Gateway deployed in hub)')
param useRemoteGateway bool = false

// ============================================================================
// Spoke to Hub Peering
// ============================================================================

@description('Peering from spoke VNet to hub VNet')
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  name: '${spokeVnetName}/peer-spoke-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: useRemoteGateway
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Spoke to Hub peering resource ID')
output peeringId string = spokeToHubPeering.id
