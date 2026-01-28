// ============================================================================
// Firewall Test Lab - Firewall Policy (Basic Tier)
// ============================================================================
// Purpose: Azure Firewall Policy with minimal rules for Basic SKU testing
// ============================================================================
// AVM Reference: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/firewall-policy
// ============================================================================
// Basic SKU Limitations:
// - DNS Proxy: NOT supported
// - Threat Intel: Only 'Alert' or 'Off' (not 'Deny')
// - Network FQDN filtering: NOT supported
// - Web categories: NOT supported
// ============================================================================

@description('Azure region for deployment')
param location string

@description('Source address space for rules (VNet CIDR)')
param sourceAddressSpace string = '10.100.0.0/24'

@description('Tags')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var policyName = 'fwpol-test-${location}'

// ============================================================================
// Firewall Policy (Basic Tier)
// ============================================================================

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' = {
  name: policyName
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Basic'
    }
    // Basic SKU only supports 'Alert' or 'Off' for threat intelligence
    threatIntelMode: 'Alert'
    // DNS Proxy is NOT supported on Basic SKU - do not enable
  }
}

// ============================================================================
// Network Rule Collection Group
// ============================================================================
// Note: Rule collection groups must be deployed sequentially
// Use dependsOn to ensure proper ordering
// ============================================================================

resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  parent: firewallPolicy
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowInfrastructure'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowDNS'
            description: 'Allow DNS queries to Azure DNS'
            ipProtocols: [
              'UDP'
              'TCP'
            ]
            sourceAddresses: [
              sourceAddressSpace
            ]
            destinationAddresses: [
              '168.63.129.16'  // Azure DNS
            ]
            destinationPorts: [
              '53'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowNTP'
            description: 'Allow NTP for time synchronization'
            ipProtocols: [
              'UDP'
            ]
            sourceAddresses: [
              sourceAddressSpace
            ]
            destinationAddresses: [
              '*'
            ]
            destinationPorts: [
              '123'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowHTTP'
            description: 'Allow HTTP outbound traffic'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              sourceAddressSpace
            ]
            destinationAddresses: [
              '*'
            ]
            destinationPorts: [
              '80'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowHTTPS'
            description: 'Allow HTTPS outbound traffic'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              sourceAddressSpace
            ]
            destinationAddresses: [
              '*'
            ]
            destinationPorts: [
              '443'
            ]
          }
        ]
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Firewall Policy resource ID')
output policyId string = firewallPolicy.id

@description('Firewall Policy name')
output policyName string = firewallPolicy.name
