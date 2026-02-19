// ============================================================================
// SMB Ready Foundation - Azure Policy Assignments
// ============================================================================
// Purpose: Deploy 20 Azure Policy assignments at subscription scope
// Note: Auto-backup policy (smb-backup-02) is deployed separately via
//       policy-backup-auto.bicep after the Recovery Services Vault is created
// Version: v0.2
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Location for policy assignment metadata')
param location string = 'swedencentral'

@description('Allowed Azure regions for resources')
param allowedLocations array = [
  'swedencentral'
  'germanywestcentral'
  'global'
]

@description('Allowed VM SKUs (B-series and D/E v5/v6 series)')
param allowedVmSkus array = [
  'Standard_B1ls'
  'Standard_B1s'
  'Standard_B1ms'
  'Standard_B2s'
  'Standard_B2ms'
  'Standard_B2ls_v2'
  'Standard_B2s_v2'
  'Standard_B2ms_v2'
  'Standard_B4ms'
  'Standard_B4ls_v2'
  'Standard_B4s_v2'
  'Standard_B4ms_v2'
  'Standard_B8ms'
  'Standard_B8ls_v2'
  'Standard_B8s_v2'
  'Standard_B8ms_v2'
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D8s_v5'
  'Standard_D16s_v5'
  'Standard_D2ds_v5'
  'Standard_D4ds_v5'
  'Standard_D8ds_v5'
  'Standard_D2s_v6'
  'Standard_D4s_v6'
  'Standard_D8s_v6'
  'Standard_E2s_v5'
  'Standard_E4s_v5'
  'Standard_E8s_v5'
  'Standard_E2ds_v5'
  'Standard_E4ds_v5'
  'Standard_E2s_v6'
  'Standard_E4s_v6'
]

// ============================================================================
// Variables
// ============================================================================

// Policy definition IDs (built-in)
var policyDefinitions = {
  // Compute policies
  allowedVmSkus: '/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3'
  noPublicIpOnNic: '/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114'
  auditManagedDisks: '/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d'
  auditArmVms: '/providers/Microsoft.Authorization/policyDefinitions/1d84d5fb-01f6-4d12-ba4f-4a26081d403d'

  // Network policies
  nsgOnSubnets: '/providers/Microsoft.Authorization/policyDefinitions/e71308d3-144b-4262-b144-efdc3cc90517'
  closeManagementPorts: '/providers/Microsoft.Authorization/policyDefinitions/22730e10-96f6-4aac-ad84-9383d35b5917'
  restrictNsgPorts: '/providers/Microsoft.Authorization/policyDefinitions/9daedab3-fb2d-461e-b861-71790eead4f6'
  disableIpForwarding: '/providers/Microsoft.Authorization/policyDefinitions/88c0b9da-ce96-4b03-9635-f29a937e2900'

  // Storage policies
  storageHttpsOnly: '/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9'
  noPublicBlobAccess: '/providers/Microsoft.Authorization/policyDefinitions/4fa4b6c0-31ca-4c0d-b10d-24b96f62a751'
  storageTls12: '/providers/Microsoft.Authorization/policyDefinitions/fe83a0eb-a853-422d-aac2-1bffd182c5d0'
  restrictStorageNetwork: '/providers/Microsoft.Authorization/policyDefinitions/34c877ad-507e-4c82-993e-3452a6e0ad3c'
  storageArmMigration: '/providers/Microsoft.Authorization/policyDefinitions/37e0d2fe-28a5-43d6-a273-67d37d1f5606'

  // Identity policies
  sqlAzureAdOnly: '/providers/Microsoft.Authorization/policyDefinitions/b3a22bc9-66de-45fb-98fa-00f5df42f41a'
  sqlNoPublicAccess: '/providers/Microsoft.Authorization/policyDefinitions/1b8ca024-1d5c-4dec-8995-b1a932b41780'

  // Tagging policies
  requireTag: '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'

  // Governance policies
  allowedLocations: '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'

  // Backup & Monitoring policies
  vmBackupRequired: '/providers/Microsoft.Authorization/policyDefinitions/013e242c-8828-4970-87b3-ab247555486d'
  diagnosticSettings: '/providers/Microsoft.Authorization/policyDefinitions/7f89b1eb-583c-429a-8828-af049802c1d9'
}

// ============================================================================
// Policy Assignments - Compute Guardrails
// ============================================================================

@description('Restrict VM SKUs to B-series and D/E v5/v6 series')
resource policyCompute01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-compute-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Allowed VM SKUs'
    description: 'Restrict VM deployments to cost-effective B-series and D/E v5/v6 series SKUs'
    policyDefinitionId: policyDefinitions.allowedVmSkus
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedSKUs: {
        value: allowedVmSkus
      }
    }
  }
}

@description('Deny public IP addresses on VM network interfaces')
resource policyCompute02 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-compute-02'
  location: location
  properties: {
    displayName: 'SMB LZ: No Public IPs on NICs'
    description: 'Prevent VMs from having public IP addresses for security'
    policyDefinitionId: policyDefinitions.noPublicIpOnNic
    enforcementMode: 'Default'
  }
}

@description('Audit VMs not using managed disks')
resource policyCompute03 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-compute-03'
  location: location
  properties: {
    displayName: 'SMB LZ: Audit Managed Disks'
    description: 'Audit VMs that do not use managed disks'
    policyDefinitionId: policyDefinitions.auditManagedDisks
    enforcementMode: 'Default'
  }
}

@description('Audit VMs not deployed via ARM')
resource policyCompute04 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-compute-04'
  location: location
  properties: {
    displayName: 'SMB LZ: Audit ARM VMs'
    description: 'Audit VMs created using classic deployment model'
    policyDefinitionId: policyDefinitions.auditArmVms
    enforcementMode: 'Default'
  }
}

// ============================================================================
// Policy Assignments - Network Guardrails
// ============================================================================

@description('Audit subnets without NSG')
resource policyNetwork01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-network-01'
  location: location
  properties: {
    displayName: 'SMB LZ: NSG on Subnets'
    description: 'Audit subnets that do not have a Network Security Group'
    policyDefinitionId: policyDefinitions.nsgOnSubnets
    enforcementMode: 'Default'
  }
}

@description('Audit VMs with management ports exposed to internet')
resource policyNetwork02 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-network-02'
  location: location
  properties: {
    displayName: 'SMB LZ: Close Management Ports'
    description: 'Audit VMs with management ports (22, 3389) exposed to the internet'
    policyDefinitionId: policyDefinitions.closeManagementPorts
    enforcementMode: 'Default'
  }
}

@description('Audit NSG rules with unrestricted ports')
resource policyNetwork03 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-network-03'
  location: location
  properties: {
    displayName: 'SMB LZ: Restrict NSG Ports'
    description: 'Audit NSG rules that allow unrestricted access'
    policyDefinitionId: policyDefinitions.restrictNsgPorts
    enforcementMode: 'Default'
  }
}

@description('Deny IP forwarding on VM network interfaces')
resource policyNetwork04 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-network-04'
  location: location
  properties: {
    displayName: 'SMB LZ: Disable IP Forwarding'
    description: 'Deny enabling IP forwarding on network interfaces'
    policyDefinitionId: policyDefinitions.disableIpForwarding
    enforcementMode: 'Default'
  }
}

// ============================================================================
// Policy Assignments - Storage Guardrails
// ============================================================================

@description('Deny storage accounts without HTTPS')
resource policyStorage01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-storage-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Storage HTTPS Only'
    description: 'Deny storage accounts that do not require HTTPS'
    policyDefinitionId: policyDefinitions.storageHttpsOnly
    enforcementMode: 'Default'
  }
}

@description('Deny public blob access on storage accounts')
resource policyStorage02 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-storage-02'
  location: location
  properties: {
    displayName: 'SMB LZ: No Public Blob Access'
    description: 'Deny public blob access on storage accounts'
    policyDefinitionId: policyDefinitions.noPublicBlobAccess
    enforcementMode: 'Default'
  }
}

@description('Deny storage accounts with TLS version below 1.2')
resource policyStorage03 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-storage-03'
  location: location
  properties: {
    displayName: 'SMB LZ: Storage TLS 1.2'
    description: 'Deny storage accounts with minimum TLS version below 1.2'
    policyDefinitionId: policyDefinitions.storageTls12
    enforcementMode: 'Default'
  }
}

@description('Audit storage accounts with unrestricted network access')
resource policyStorage04 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-storage-04'
  location: location
  properties: {
    displayName: 'SMB LZ: Restrict Storage Network'
    description: 'Audit storage accounts with unrestricted network access'
    policyDefinitionId: policyDefinitions.restrictStorageNetwork
    enforcementMode: 'Default'
  }
}

@description('Audit storage accounts not migrated to ARM')
resource policyStorage05 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-storage-05'
  location: location
  properties: {
    displayName: 'SMB LZ: Storage ARM Migration'
    description: 'Audit classic storage accounts that should be migrated to ARM'
    policyDefinitionId: policyDefinitions.storageArmMigration
    enforcementMode: 'Default'
  }
}

// ============================================================================
// Policy Assignments - Identity & Access
// ============================================================================

@description('Audit SQL servers without Azure AD-only authentication')
resource policyIdentity01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-identity-01'
  location: location
  properties: {
    displayName: 'SMB LZ: SQL Azure AD Only'
    description: 'Audit SQL servers that do not use Azure AD-only authentication'
    policyDefinitionId: policyDefinitions.sqlAzureAdOnly
    enforcementMode: 'Default'
  }
}

@description('Audit SQL servers with public network access')
resource policyIdentity02 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-identity-02'
  location: location
  properties: {
    displayName: 'SMB LZ: SQL No Public Access'
    description: 'Audit SQL servers with public network access enabled'
    policyDefinitionId: policyDefinitions.sqlNoPublicAccess
    enforcementMode: 'Default'
  }
}

// ============================================================================
// Policy Assignments - Tagging & Governance
// ============================================================================

@description('Deny resources without Environment tag')
resource policyTagging01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-tagging-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Require Environment Tag'
    description: 'Deny resource creation without Environment tag'
    policyDefinitionId: policyDefinitions.requireTag
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: 'Environment'
      }
    }
  }
}

@description('Deny resources without Owner tag')
resource policyTagging02 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-tagging-02'
  location: location
  properties: {
    displayName: 'SMB LZ: Require Owner Tag'
    description: 'Deny resource creation without Owner tag'
    policyDefinitionId: policyDefinitions.requireTag
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: 'Owner'
      }
    }
  }
}

@description('Restrict resource deployment to allowed regions')
resource policyGovernance01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-governance-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Allowed Locations'
    description: 'Restrict resource deployment to swedencentral, germanywestcentral, and global'
    policyDefinitionId: policyDefinitions.allowedLocations
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedLocations: {
        value: allowedLocations
      }
    }
  }
}

// ============================================================================
// Policy Assignments - Backup & Monitoring
// ============================================================================

@description('Audit VMs without backup configured')
resource policyBackup01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-backup-01'
  location: location
  properties: {
    displayName: 'SMB LZ: VM Backup Required'
    description: 'Audit VMs that do not have backup configured'
    policyDefinitionId: policyDefinitions.vmBackupRequired
    enforcementMode: 'Default'
  }
}

@description('Audit resources without diagnostic settings')
resource policyMonitoring01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-monitoring-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Diagnostic Settings Required'
    description: 'Audit resources that do not have diagnostic settings configured'
    policyDefinitionId: policyDefinitions.diagnosticSettings
    enforcementMode: 'Default'
    parameters: {
      listOfResourceTypes: {
        value: [
          'Microsoft.Compute/virtualMachines'
          'Microsoft.Network/virtualNetworks'
          'Microsoft.Network/networkSecurityGroups'
          'Microsoft.Network/azureFirewalls'
          'Microsoft.Network/bastionHosts'
          'Microsoft.KeyVault/vaults'
          'Microsoft.RecoveryServices/vaults'
          'Microsoft.Sql/servers'
        ]
      }
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('List of policy assignment names for reference')
output policyAssignmentNames array = [
  policyCompute01.name
  policyCompute02.name
  policyCompute03.name
  policyCompute04.name
  policyNetwork01.name
  policyNetwork02.name
  policyNetwork03.name
  policyNetwork04.name
  policyStorage01.name
  policyStorage02.name
  policyStorage03.name
  policyStorage04.name
  policyStorage05.name
  policyIdentity01.name
  policyIdentity02.name
  policyTagging01.name
  policyTagging02.name
  policyGovernance01.name
  policyBackup01.name
  policyMonitoring01.name
]

@description('Total number of policy assignments (excludes auto-backup policy deployed separately)')
output policyCount int = 20
