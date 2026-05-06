// ============================================================================
// SMB Ready Foundations - VPN Gateway (AVM - Optional)
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
  'smb'
])
param environment string

@description('Region abbreviation for naming')
param regionShort string

@description('Gateway Subnet resource ID')
param gatewaySubnetId string

@description('On-premises address space CIDR (used to create a Local Network Gateway when onPremisesGatewayPublicIp is also set)')
param onPremisesAddressSpace string = ''

@description('Public IP of the on-premises VPN device. Required to create the Local Network Gateway.')
param onPremisesGatewayPublicIp string = ''

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var gatewayName = 'vpng-hub-${environment}-${regionShort}'
var gatewayPublicIpName = 'pip-vpn-${environment}-${regionShort}'
var localNetworkGatewayName = 'lng-onprem-${environment}-${regionShort}'

// Always deploy a Local Network Gateway in vpn/full scenarios so the partner
// has a placeholder to attach the IPsec connection to. If the partner did not
// supply a peer IP / on-prem CIDR yet, fall back to RFC 5737 documentation
// ranges (192.0.2.0/24 / 192.0.2.1) so the resource is structurally valid but
// clearly non-functional until the real values are filled in post-deploy.
var effectiveOnPremCidr = empty(onPremisesAddressSpace) ? '192.0.2.0/24' : onPremisesAddressSpace
var effectiveOnPremGatewayIp = empty(onPremisesGatewayPublicIp) ? '192.0.2.1' : onPremisesGatewayPublicIp

// AVM virtual-network-gateway 0.10.1 defaults the public IP's domainNameLabel to
// the PIP name when none is supplied, which collides across deployments
// (e.g. pip-vpn-smb-swc.swedencentral.cloudapp.azure.com already reserved).
// Append a uniqueString tied to the resource group so the FQDN is globally unique
// while remaining deterministic for repeat deployments into the same RG.
var gatewayPublicIpDnsLabel = '${gatewayPublicIpName}-${uniqueString(resourceGroup().id, gatewayPublicIpName)}'

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
    // Globally unique DNS label so the auto-generated FQDN
    // (<label>.<region>.cloudapp.azure.com) does not collide with prior
    // reservations. Without this, AVM defaults the label to primaryPublicIPName.
    domainNameLabel: [
      gatewayPublicIpDnsLabel
    ]
  }
}

// ============================================================================
// Local Network Gateway
// ============================================================================
// Defines the on-premises side of the VPN. Always created so the partner has
// a placeholder to attach an IPsec connection to. If the on-prem CIDR / peer
// IP are not supplied, RFC 5737 documentation ranges are used as placeholders
// (must be overwritten post-deploy before the tunnel will work).
// Connection (with shared key) is intentionally NOT created here to keep
// secrets out of the template; wire it up post-deploy or via a Key
// Vault-backed extension.
// ============================================================================

@description('Local Network Gateway describing the on-premises network')
resource localNetworkGateway 'Microsoft.Network/localNetworkGateways@2024-05-01' = {
  name: localNetworkGatewayName
  location: location
  tags: tags
  properties: {
    localNetworkAddressSpace: {
      addressPrefixes: [
        effectiveOnPremCidr
      ]
    }
    gatewayIpAddress: effectiveOnPremGatewayIp
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

@description('Local Network Gateway resource ID')
output localNetworkGatewayId string = localNetworkGateway.id

@description('Local Network Gateway name')
output localNetworkGatewayName string = localNetworkGateway.name
