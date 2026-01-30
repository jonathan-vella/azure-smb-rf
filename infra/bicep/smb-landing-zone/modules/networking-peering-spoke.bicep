// ============================================================================
// SMB Landing Zone - Spoke to Hub Peering (Internal Module)
// ============================================================================
// Purpose: Deploy spoke-to-hub peering in spoke resource group scope
// Version: v0.3
// AVM Status: Raw Bicep (No dedicated AVM module for VNet peering)
// Note: Internal module called by networking-peering.bicep for cross-RG deployment
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Spoke VNet name')
param spokeVnetName string

@description('Hub VNet resource ID')
param hubVnetId string

@description('Use remote gateways from hub (true when VPN Gateway is deployed)')
param useRemoteGateways bool = false

// ============================================================================
// Spoke to Hub Peering
// ============================================================================

@description('Peering from spoke VNet to hub VNet (uses remote gateways when VPN deployed)')
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  name: '${spokeVnetName}/peer-spoke-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: useRemoteGateways
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Spoke to Hub peering resource ID')
output peeringId string = spokeToHubPeering.id
