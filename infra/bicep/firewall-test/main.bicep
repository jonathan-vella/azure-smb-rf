// ============================================================================
// Firewall Test Lab - Main Orchestrator
// ============================================================================
// Purpose: Deploy isolated Azure Firewall Basic and VPN Gateway VpnGw1AZ for testing
// ============================================================================
// Deployment Order:
// 1. Resource Group (subscription scope)
// 2. VNet with firewall subnets (+ GatewaySubnet if VPN enabled)
// 3. Firewall Policy with rule collection groups
// 4. Firewall with management IP configuration
// 5. VPN Gateway (optional)
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for deployment')
@allowed([
  'swedencentral'
  'germanywestcentral'
])
param location string = 'swedencentral'

@description('Resource group name')
param resourceGroupName string = 'rg-fw-test-swc'

@description('VNet address space')
param vnetAddressSpace string = '10.100.0.0/24'

@description('Deploy VPN Gateway for testing')
param deployVpnGateway bool = false

@description('Tags')
param tags object = {
  Environment: 'test'
  Purpose: 'firewall-validation'
  ManagedBy: 'Bicep'
}

// ============================================================================
// Resource Group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Module Deployments
// ============================================================================

@description('Deploy VNet with firewall subnets (+ GatewaySubnet if VPN enabled)')
module vnet 'vnet.bicep' = {
  scope: rg
  name: 'vnet-deployment'
  params: {
    location: location
    addressSpace: vnetAddressSpace
    includeGatewaySubnet: deployVpnGateway
    tags: tags
  }
}

@description('Deploy Firewall Policy with minimal rules')
module firewallPolicy 'firewall-policy.bicep' = {
  scope: rg
  name: 'firewall-policy-deployment'
  params: {
    location: location
    sourceAddressSpace: vnetAddressSpace
    tags: tags
  }
}

@description('Deploy Azure Firewall Basic')
module firewall 'firewall.bicep' = {
  scope: rg
  name: 'firewall-deployment'
  params: {
    location: location
    firewallSubnetId: vnet.outputs.firewallSubnetId
    firewallManagementSubnetId: vnet.outputs.firewallManagementSubnetId
    firewallPolicyId: firewallPolicy.outputs.policyId
    tags: tags
  }
}

@description('Deploy VPN Gateway Basic (optional)')
module vpnGateway 'vpn-gateway.bicep' = if (deployVpnGateway) {
  scope: rg
  name: 'vpn-gateway-deployment'
  params: {
    location: location
    gatewaySubnetId: vnet.outputs.gatewaySubnetId
    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource group name')
output resourceGroupName string = rg.name

@description('VNet resource ID')
output vnetId string = vnet.outputs.vnetId

@description('Firewall Policy resource ID')
output firewallPolicyId string = firewallPolicy.outputs.policyId

@description('Firewall private IP')
output firewallPrivateIp string = firewall.outputs.firewallPrivateIp

@description('Firewall public IP')
output firewallPublicIp string = firewall.outputs.firewallPublicIp

@description('VPN Gateway public IP (if deployed)')
#disable-next-line BCP318
output vpnGatewayPublicIp string = deployVpnGateway ? vpnGateway.outputs.gatewayPublicIp : ''
