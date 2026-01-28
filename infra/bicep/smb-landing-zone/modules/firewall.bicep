// ============================================================================
// SMB Landing Zone - Azure Firewall (Optional)
// ============================================================================
// Purpose: Deploy Azure Firewall Basic with best-practice rules
// Version: v0.2
// ============================================================================
// Azure Firewall Basic SKU Limitations:
// - Throughput: 250 Mbps max
// - DNS proxy: NOT supported (VMs use Azure DNS directly)
// - Threat intelligence: Alert mode only
// - Network FQDN filtering: NOT supported (application rules only)
// - Web categories: NOT supported
// - Forced tunneling: NOT supported
// - Multiple public IPs: NOT supported
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

@description('Azure Firewall Subnet resource ID')
param firewallSubnetId string

@description('Azure Firewall Management Subnet resource ID (required for Basic SKU)')
param firewallManagementSubnetId string

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

// ============================================================================
// Firewall Public IPs
// ============================================================================

@description('Public IP for Azure Firewall data traffic')
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: firewallPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

@description('Public IP for Azure Firewall management traffic (required for Basic SKU)')
resource firewallMgmtPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: firewallMgmtPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ============================================================================
// Firewall Policy
// ============================================================================

@description('Firewall Policy with Basic tier and best-practice rules')
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' = {
  name: firewallPolicyName
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Basic'
    }
    threatIntelMode: 'Alert' // Basic SKU only supports Alert mode
  }
}

// ============================================================================
// Network Rule Collection Group - Infrastructure Rules
// ============================================================================

@description('Network rules for DNS, NTP, ICMP, and Azure services')
resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  parent: firewallPolicy
  name: 'NetworkRuleCollectionGroup'
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
            ipProtocols: [
              'UDP'
              'TCP'
            ]
            sourceAddresses: [
              spokeAddressSpace
            ]
            destinationAddresses: [
              '168.63.129.16' // Azure DNS
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
              spokeAddressSpace
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
            name: 'AllowICMP'
            description: 'Allow all ICMP traffic for diagnostics'
            ipProtocols: [
              'ICMP'
            ]
            sourceAddresses: [
              spokeAddressSpace
            ]
            destinationAddresses: [
              '*'
            ]
            destinationPorts: [
              '*'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowOutboundHTTP'
            description: 'Allow outbound HTTP traffic'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              spokeAddressSpace
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
            name: 'AllowOutboundHTTPS'
            description: 'Allow outbound HTTPS traffic'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              spokeAddressSpace
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
// On-Premises Network Rule Collection (Conditional)
// ============================================================================

@description('Network rules for on-premises connectivity (conditional)')
resource onPremRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = if (hasOnPremises) {
  parent: firewallPolicy
  name: 'OnPremisesRuleCollectionGroup'
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
            ipProtocols: [
              'Any'
            ]
            sourceAddresses: [
              spokeAddressSpace
            ]
            destinationAddresses: [
              onPremisesAddressSpace
            ]
            destinationPorts: [
              '*'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowOnPremToAzure'
            description: 'Allow on-premises to reach Azure spoke resources'
            ipProtocols: [
              'Any'
            ]
            sourceAddresses: [
              onPremisesAddressSpace
            ]
            destinationAddresses: [
              spokeAddressSpace
            ]
            destinationPorts: [
              '*'
            ]
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
// Application Rule Collection Group - Outbound Internet
// ============================================================================

@description('Application rules for outbound internet access')
resource applicationRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  parent: firewallPolicy
  name: 'ApplicationRuleCollectionGroup'
  properties: {
    priority: 400
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'AllowWindowsUpdate'
        priority: 100
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'WindowsUpdate'
            description: 'Allow Windows Update using FQDN tag'
            sourceAddresses: [
              spokeAddressSpace
            ]
            fqdnTags: [
              'WindowsUpdate'
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
              {
                protocolType: 'Http'
                port: 80
              }
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'AllowAzureBackupFqdn'
        priority: 200
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'AzureBackup'
            description: 'Allow Azure Backup using FQDN tag'
            sourceAddresses: [
              spokeAddressSpace
            ]
            fqdnTags: [
              'AzureBackup'
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'AllowOutboundInternet'
        priority: 1000
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'AllowHttpHttps'
            description: 'Allow general outbound HTTP/HTTPS internet access'
            sourceAddresses: [
              spokeAddressSpace
            ]
            targetFqdns: [
              '*'
            ]
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [
    networkRuleCollectionGroup
    onPremRuleCollectionGroup
  ]
}

// ============================================================================
// Azure Firewall
// ============================================================================

@description('Azure Firewall with Basic SKU and management IP configuration')
resource firewall 'Microsoft.Network/azureFirewalls@2024-01-01' = {
  name: firewallName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Basic'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          subnet: {
            id: firewallSubnetId
          }
          publicIPAddress: {
            id: firewallPublicIp.id
          }
        }
      }
    ]
    managementIpConfiguration: {
      name: 'fw-mgmt-ipconfig'
      properties: {
        subnet: {
          id: firewallManagementSubnetId
        }
        publicIPAddress: {
          id: firewallMgmtPublicIp.id
        }
      }
    }
  }
  dependsOn: [
    applicationRuleCollectionGroup
  ]
}

// ============================================================================
// Outputs
// ============================================================================

@description('Azure Firewall resource ID')
output firewallId string = firewall.id

@description('Azure Firewall name')
output firewallName string = firewall.name

@description('Azure Firewall private IP address (for UDR next hop)')
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress

@description('Azure Firewall public IP address')
output firewallPublicIp string = firewallPublicIp.properties.ipAddress

@description('Azure Firewall management public IP address')
output firewallMgmtPublicIp string = firewallMgmtPublicIp.properties.ipAddress
