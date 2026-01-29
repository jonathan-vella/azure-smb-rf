// ============================================================================
// SMB Landing Zone - VNet Peering (Consolidated)
// ============================================================================
// Purpose: Configure bi-directional hub-spoke VNet peering
// Version: v0.2
// ============================================================================
// This module handles BOTH directions of peering:
// - Hub → Spoke: Deployed in hub resource group (this module's scope)
// - Spoke → Hub: Deployed in spoke resource group (cross-RG deployment)
//
// Gateway transit is automatically configured based on VPN Gateway deployment.
// ============================================================================

// ============================================================================
// Parameters (Standardized Interface)
// ============================================================================

@description('Azure region for deployment (unused but kept for interface consistency)')
param location string = ''

@description('Environment name (unused but kept for interface consistency)')
param environment string = ''

@description('Region abbreviation (unused but kept for interface consistency)')
param regionShort string = ''

@description('Tags to apply to resources (peering has no tags but kept for consistency)')
param tags object = {}

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

@description('Allow gateway transit (true when VPN Gateway is deployed in hub)')
param allowGatewayTransit bool = false

@description('Use remote gateways from hub (true when VPN Gateway is deployed)')
param useRemoteGateways bool = false

// ============================================================================
// Variables
// ============================================================================

// Suppress unused parameter warnings (parameters kept for interface consistency)
#disable-next-line no-unused-vars
var _location = location
#disable-next-line no-unused-vars
var _environment = environment
#disable-next-line no-unused-vars
var _regionShort = regionShort
#disable-next-line no-unused-vars
var _tags = tags

// ============================================================================
// Hub to Spoke Peering
// ============================================================================

@description('Peering from hub VNet to spoke VNet (allows gateway transit when VPN deployed)')
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  name: '${hubVnetName}/peer-hub-to-spoke'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: false
  }
}

// ============================================================================
// Spoke to Hub Peering (Cross Resource Group - via Module)
// ============================================================================

@description('Peering from spoke VNet to hub VNet (uses remote gateways when VPN deployed)')
module spokeToHubPeering 'networking-peering-spoke.bicep' = {
  name: 'spoke-to-hub-peering'
  scope: resourceGroup(spokeResourceGroupName)
  params: {
    spokeVnetName: spokeVnetName
    hubVnetId: hubVnetId
    useRemoteGateways: useRemoteGateways
  }
  dependsOn: [
    hubToSpokePeering
  ]
}

// ============================================================================
// Outputs
// ============================================================================

@description('Hub to Spoke peering resource ID')
output hubToSpokePeeringId string = hubToSpokePeering.id

@description('Spoke to Hub peering resource ID')
output spokeToHubPeeringId string = spokeToHubPeering.outputs.peeringId

@description('Gateway transit enabled status')
output gatewayTransitEnabled bool = allowGatewayTransit
