// ============================================================================
// SMB Ready Foundations - Azure Firewall (Full AVM-based)
// ============================================================================
// Purpose: Deploy Azure Firewall Basic using Azure Verified Modules (AVM)
// Version: v0.5 (Full AVM Migration)
// AVM Modules:
//   - br/public:avm/res/network/public-ip-address:0.12.0
//   - br/public:avm/res/network/firewall-policy:0.3.4
//   - br/public:avm/res/network/azure-firewall:0.10.1
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

@description('Hub Virtual Network resource ID')
param hubVnetId string

@description('Spoke VNet address space for firewall rules')
param spokeAddressSpace string

@description('On-premises address space CIDR. When non-empty, bidirectional spoke<->on-prem allow rules are added so traffic forced through the firewall (scenario=full) is permitted. Leave empty for scenarios where hybrid traffic bypasses the firewall.')
param onPremisesAddressSpace string = ''

@description('Log Analytics workspace ID for firewall diagnostic settings (smb-monitoring-01 compliance).')
param logAnalyticsWorkspaceId string

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

// Hybrid traffic (spoke <-> on-prem) bypasses the firewall in scenarios
// `firewall` and `vpn` and is routed directly via the VPN Gateway. In
// scenario `full`, route-tables.bicep installs UDRs that force hybrid
// traffic through this firewall; the AllowHybrid rule collection below is
// added (gated on a non-empty onPremisesAddressSpace) to permit it.

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

// Note: On-premises rule collection group removed. Hybrid traffic
// (spoke <-> on-prem) bypasses the firewall and routes via the VPN Gateway
// (BGP/system routes). See route-tables.bicep and vpn-gateway.bicep.

// ----------------------------------------------------------------------------
// Hybrid (spoke <-> on-prem) allow rules - scenario=full only
// ----------------------------------------------------------------------------
// Deployed only when the caller passes a non-empty onPremisesAddressSpace.
// In scenario=full, route-tables.bicep adds UDRs that force hybrid traffic
// through this firewall; without these rules, that traffic would be dropped.
// In scenarios `firewall` and `vpn`, hybrid traffic bypasses the firewall
// (no UDR) and these rules are not deployed.
@description('Bidirectional spoke<->on-prem allow rules (scenario=full)')
resource hybridRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = if (!empty(onPremisesAddressSpace)) {
  name: '${firewallPolicyName}/HybridRuleCollectionGroup'
  properties: {
    priority: 150
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'AllowHybrid'
        priority: 100
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowSpokeToOnprem'
            description: 'Allow spoke -> on-prem traffic forced through firewall (scenario=full)'
            ipProtocols: ['Any']
            sourceAddresses: [spokeAddressSpace]
            destinationAddresses: [onPremisesAddressSpace]
            destinationPorts: ['*']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowOnpremToSpoke'
            description: 'Allow on-prem -> spoke return traffic forced through firewall (scenario=full)'
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
    firewallPolicy
    networkRuleCollectionGroup
  ]
}

// ============================================================================
// Phase 4: Azure Firewall (AVM Module - depends on PIPs + Policy)
// ============================================================================

@description('Azure Firewall Basic using AVM module with pre-created PIPs')
module firewall 'br/public:avm/res/network/azure-firewall:0.10.1' = {
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
    diagnosticSettings: [
      {
        name: 'afw-diag-law'
        workspaceResourceId: logAnalyticsWorkspaceId
        logCategoriesAndGroups: [
          {
            categoryGroup: 'allLogs'
          }
        ]
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
      }
    ]
  }
  dependsOn: [
    networkRuleCollectionGroup
    hybridRuleCollectionGroup
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
