// ============================================================================
// SMB Landing Zone - Azure Firewall (Full AVM-based)
// ============================================================================
// Purpose: Deploy Azure Firewall Basic using Azure Verified Modules (AVM)
// Version: v0.5 (Full AVM Migration)
// AVM Modules:
//   - br/public:avm/res/network/public-ip-address:0.12.0
//   - br/public:avm/res/network/firewall-policy:0.3.4
//   - br/public:avm/res/network/azure-firewall:0.9.2
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

@description('Hub Virtual Network resource ID')
param hubVnetId string

@description('Spoke VNet address space for firewall rules')
param spokeAddressSpace string

@description('On-premises address space for VPN routing (optional)')
param onPremisesAddressSpace string = ''

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var firewallName = 'fw-hub-${environment}-${regionShort}'
var firewallPolicyName = 'fwpol-hub-${environment}-${regionShort}'
var firewallPublicIpName = 'pip-fw-${environment}-${regionShort}'
var firewallMgmtPublicIpName = 'pip-fw-mgmt-${environment}-${regionShort}'

// Determine if on-prem rules are needed
var hasOnPremises = !empty(onPremisesAddressSpace)

// Availability zones for zone-redundant deployment
var availabilityZones = [
  1
  2
  3
]

// ============================================================================
// Phase 1: Public IP Addresses (AVM Modules - Created FIRST for reliability)
// ============================================================================

@description('Public IP for Azure Firewall data traffic using AVM (zone-redundant)')
module firewallPublicIp 'br/public:avm/res/network/public-ip-address:0.12.0' = {
  name: 'deploy-${firewallPublicIpName}'
  params: {
    name: firewallPublicIpName
    location: location
    tags: tags
    skuName: 'Standard'
    skuTier: 'Regional'
    availabilityZones: [1, 2, 3]
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

@description('Public IP for Azure Firewall management traffic using AVM (zone-redundant)')
module firewallMgmtPublicIp 'br/public:avm/res/network/public-ip-address:0.12.0' = {
  name: 'deploy-${firewallMgmtPublicIpName}'
  params: {
    name: firewallMgmtPublicIpName
    location: location
    tags: tags
    skuName: 'Standard'
    skuTier: 'Regional'
    availabilityZones: [1, 2, 3]
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ============================================================================
// Phase 2: Firewall Policy (AVM Module)
// ============================================================================

@description('Firewall Policy with Basic tier')
module firewallPolicy 'br/public:avm/res/network/firewall-policy:0.3.4' = {
  name: 'deploy-${firewallPolicyName}'
  params: {
    name: firewallPolicyName
    location: location
    tier: 'Basic'
    threatIntelMode: 'Alert' // Basic SKU only supports Alert mode
    enableProxy: false // DNS proxy not supported on Basic SKU
    tags: tags
  }
}

// ============================================================================
// Phase 3: Network Rule Collection Groups (after Policy)
// ============================================================================

@description('Network rules for DNS, NTP, ICMP, and Azure services')
resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  name: '${firewallPolicyName}/NetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'AllowInfrastructure'
        priority: 100
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowDNS'
            description: 'Allow DNS queries to Azure DNS'
            ipProtocols: ['UDP', 'TCP']
            sourceAddresses: [spokeAddressSpace]
            destinationAddresses: ['168.63.129.16']
            destinationPorts: ['53']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowNTP'
            description: 'Allow NTP for time synchronization'
            ipProtocols: ['UDP']
            sourceAddresses: [spokeAddressSpace]
            destinationAddresses: ['*']
            destinationPorts: ['123']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowICMP'
            description: 'Allow all ICMP traffic for diagnostics'
            ipProtocols: ['ICMP']
            sourceAddresses: [spokeAddressSpace]
            destinationAddresses: ['*']
            destinationPorts: ['*']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowOutboundHTTP'
            description: 'Allow outbound HTTP traffic'
            ipProtocols: ['TCP']
            sourceAddresses: [spokeAddressSpace]
            destinationAddresses: ['*']
            destinationPorts: ['80']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowOutboundHTTPS'
            description: 'Allow outbound HTTPS traffic'
            ipProtocols: ['TCP']
            sourceAddresses: [spokeAddressSpace]
            destinationAddresses: ['*']
            destinationPorts: ['443']
          }
        ]
      }
    ]
  }
  dependsOn: [
    firewallPolicy
  ]
}

@description('Network rules for on-premises connectivity (conditional)')
resource onPremRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = if (hasOnPremises) {
  name: '${firewallPolicyName}/OnPremisesRuleCollectionGroup'
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'AllowOnPremisesTraffic'
        priority: 100
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowAzureToOnPrem'
            description: 'Allow Azure spoke resources to reach on-premises'
            ipProtocols: ['Any']
            sourceAddresses: [spokeAddressSpace]
            destinationAddresses: [onPremisesAddressSpace]
            destinationPorts: ['*']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowOnPremToAzure'
            description: 'Allow on-premises to reach Azure spoke resources'
            ipProtocols: ['Any']
            sourceAddresses: [onPremisesAddressSpace]
            destinationAddresses: [spokeAddressSpace]
            destinationPorts: ['*']
          }
        ]
      }
    ]
  }
  dependsOn: [
    networkRuleCollectionGroup
  ]
}

// ============================================================================
// Phase 4: Azure Firewall (AVM Module - depends on PIPs + Policy)
// ============================================================================

@description('Azure Firewall Basic using AVM module with pre-created PIPs')
module firewall 'br/public:avm/res/network/azure-firewall:0.9.2' = {
  name: 'deploy-${firewallName}'
  params: {
    name: firewallName
    location: location
    azureSkuTier: 'Basic'
    virtualNetworkResourceId: hubVnetId
    firewallPolicyId: firewallPolicy.outputs.resourceId
    // Reference pre-created Public IPs from AVM modules
    publicIPResourceID: firewallPublicIp.outputs.resourceId
    managementIPResourceID: firewallMgmtPublicIp.outputs.resourceId
    // Zone redundancy for High Availability
    availabilityZones: availabilityZones
    tags: tags
  }
  dependsOn: [
    networkRuleCollectionGroup
    onPremRuleCollectionGroup
  ]
}

// ============================================================================
// Outputs
// ============================================================================

@description('Azure Firewall resource ID')
output firewallId string = firewall.outputs.resourceId

@description('Azure Firewall name')
output firewallName string = firewall.outputs.name

@description('Azure Firewall private IP address (for UDR next hop)')
output firewallPrivateIp string = firewall.outputs.privateIp

@description('Azure Firewall public IP address')
output firewallPublicIpAddress string = firewallPublicIp.outputs.ipAddress

@description('Azure Firewall management public IP address')
output firewallMgmtPublicIpAddress string = firewallMgmtPublicIp.outputs.ipAddress
