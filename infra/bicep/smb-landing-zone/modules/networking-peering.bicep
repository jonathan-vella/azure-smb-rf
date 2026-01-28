// ============================================================================
// SMB Landing Zone - VNet Peering
// ============================================================================
// Purpose: Configure hub-spoke VNet peering (conditional)
// Version: v0.1
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Hub VNet name')
param hubVnetName string

@description('Hub VNet resource ID')
param hubVnetId string

@description('Spoke VNet name')
param spokeVnetName string

@description('Spoke VNet resource ID')
param spokeVnetId string

@description('Spoke resource group name for cross-RG peering')
param spokeResourceGroupName string

@description('Use remote gateway (requires VPN Gateway deployed)')
param useRemoteGateway bool = false

// ============================================================================
// Hub to Spoke Peering
// ============================================================================

@description('Peering from hub VNet to spoke VNet')
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  name: '${hubVnetName}/peer-hub-to-spoke'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: useRemoteGateway
    useRemoteGateways: false
  }
}

// ============================================================================
// Spoke to Hub Peering (Cross Resource Group)
// ============================================================================

@description('Peering from spoke VNet to hub VNet')
module spokeToHubPeering 'networking-peering-spoke.bicep' = {
  name: 'spoke-to-hub-peering'
  scope: resourceGroup(spokeResourceGroupName)
  params: {
    spokeVnetName: spokeVnetName
    hubVnetId: hubVnetId
    useRemoteGateway: useRemoteGateway
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Hub to Spoke peering resource ID')
output hubToSpokePeeringId string = hubToSpokePeering.id

@description('Spoke to Hub peering resource ID')
output spokeToHubPeeringId string = spokeToHubPeering.outputs.peeringId
