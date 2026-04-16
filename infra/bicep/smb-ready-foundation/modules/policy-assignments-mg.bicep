// ============================================================================
// SMB Ready Foundation - MG-Scoped Azure Policy Assignments
// ============================================================================
// Purpose: Deploy 30 Azure Policy assignments at management group scope.
//          These policies inherit to all subscriptions under the smb-rf MG.
// Scope: Management Group (smb-rf)
// Deployment: az deployment mg create --management-group-id smb-rf
// Note: 3 remaining policies (auto-backup DeployIfNotExists, budget,
//       Defender config) stay at subscription scope in main.bicep.
// Version: v1.0
// ============================================================================

targetScope = 'managementGroup'

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

// Policy definition IDs (built-in — tenant-scoped, work at any deployment scope)
var policyDefinitions = {
  // Compute
  allowedVmSkus: '/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3'
  noPublicIpOnNic: '/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114'
  auditManagedDisks: '/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d'
  auditArmVms: '/providers/Microsoft.Authorization/policyDefinitions/1d84d5fb-01f6-4d12-ba4f-4a26081d403d'
  // Network
  nsgOnSubnets: '/providers/Microsoft.Authorization/policyDefinitions/e71308d3-144b-4262-b144-efdc3cc90517'
  closeManagementPorts: '/providers/Microsoft.Authorization/policyDefinitions/22730e10-96f6-4aac-ad84-9383d35b5917'
  restrictNsgPorts: '/providers/Microsoft.Authorization/policyDefinitions/9daedab3-fb2d-461e-b861-71790eead4f6'
  disableIpForwarding: '/providers/Microsoft.Authorization/policyDefinitions/88c0b9da-ce96-4b03-9635-f29a937e2900'
  // Storage
  storageHttpsOnly: '/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9'
  noPublicBlobAccess: '/providers/Microsoft.Authorization/policyDefinitions/4fa4b6c0-31ca-4c0d-b10d-24b96f62a751'
  storageTls12: '/providers/Microsoft.Authorization/policyDefinitions/fe83a0eb-a853-422d-aac2-1bffd182c5d0'
  restrictStorageNetwork: '/providers/Microsoft.Authorization/policyDefinitions/34c877ad-507e-4c82-993e-3452a6e0ad3c'
  storageArmMigration: '/providers/Microsoft.Authorization/policyDefinitions/37e0d2fe-28a5-43d6-a273-67d37d1f5606'
  // Identity
  sqlAzureAdOnly: '/providers/Microsoft.Authorization/policyDefinitions/b3a22bc9-66de-45fb-98fa-00f5df42f41a'
  sqlNoPublicAccess: '/providers/Microsoft.Authorization/policyDefinitions/1b8ca024-1d5c-4dec-8995-b1a932b41780'
  // Tagging
  requireTag: '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
  // Governance
  allowedLocations: '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
  // Backup & Monitoring
  vmBackupRequired: '/providers/Microsoft.Authorization/policyDefinitions/013e242c-8828-4970-87b3-ab247555486d'
  diagnosticSettings: '/providers/Microsoft.Authorization/policyDefinitions/7f89b1eb-583c-429a-8828-af049802c1d9'
  // Key Vault
  kvSoftDelete: '/providers/Microsoft.Authorization/policyDefinitions/1e66c121-a66a-4b1f-9b83-0fd99bf0fc2d'
  kvDeletionProtection: '/providers/Microsoft.Authorization/policyDefinitions/0b60c0b2-2dc2-4e1c-b5c9-abbed971de53'
  kvRbacModel: '/providers/Microsoft.Authorization/policyDefinitions/12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5'
  kvNoPublicNetwork: '/providers/Microsoft.Authorization/policyDefinitions/405c5871-3e91-4644-8a63-58e19d68ff5b'
  kvSecretsExpiration: '/providers/Microsoft.Authorization/policyDefinitions/98728c90-32c7-4049-8429-847dc0f4fe37'
  kvKeysExpiration: '/providers/Microsoft.Authorization/policyDefinitions/152b15f7-8e1f-4c1f-ab71-8c010ba5dbc0'
  kvResourceLogs: '/providers/Microsoft.Authorization/policyDefinitions/cf820ca0-f99e-4f3e-84fb-66e913812d21'
  // General
  nsgFlowLogs: '/providers/Microsoft.Authorization/policyDefinitions/27960feb-a23c-4577-8d36-ef8b5f35e0be'
  auditSystemUpdates: '/providers/Microsoft.Authorization/policyDefinitions/86b3d65f-7626-441e-b690-81a8b71cff60'
  auditEndpointProtection: '/providers/Microsoft.Authorization/policyDefinitions/26a828e1-e88f-464e-bbb3-c134a282b9de'
  auditMfaOwners: '/providers/Microsoft.Authorization/policyDefinitions/aa633080-8b72-40c4-a2d7-d00c03e80bed'
  auditDeprecatedAccounts: '/providers/Microsoft.Authorization/policyDefinitions/8d7e1fde-fe26-4b5f-8108-f8e432cbc2be'
  auditStorageGeoRedundancy: '/providers/Microsoft.Authorization/policyDefinitions/bf045164-79ba-4215-8f95-f8048dc1780b'
}

// ============================================================================
// Policy Assignments - Compute Guardrails (4 Deny + 2 Audit)
// ============================================================================

resource policyCompute01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-compute-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Allowed VM SKUs'
    description: 'Restrict VM deployments to cost-effective B-series and D/E v5/v6 series SKUs'
    policyDefinitionId: policyDefinitions.allowedVmSkus
    enforcementMode: 'Default'
    parameters: { listOfAllowedSKUs: { value: allowedVmSkus } }
  }
}

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

resource policyCompute05 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-compute-05'
  location: location
  properties: {
    displayName: 'SMB LZ: Audit System Updates on VMs'
    description: 'Audit VMs that are missing system updates'
    policyDefinitionId: policyDefinitions.auditSystemUpdates
    enforcementMode: 'Default'
  }
}

resource policyCompute06 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-compute-06'
  location: location
  properties: {
    displayName: 'SMB LZ: Audit Endpoint Protection'
    description: 'Audit VMs that do not have endpoint protection installed'
    policyDefinitionId: policyDefinitions.auditEndpointProtection
    enforcementMode: 'Default'
  }
}

// ============================================================================
// Policy Assignments - Network Guardrails (1 Deny + 4 Audit)
// ============================================================================

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

resource policyNetwork05 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-network-05'
  location: location
  properties: {
    displayName: 'SMB LZ: Audit NSG Flow Logs'
    description: 'Audit Network Security Groups that do not have flow logs configured'
    policyDefinitionId: policyDefinitions.nsgFlowLogs
    enforcementMode: 'Default'
  }
}

// ============================================================================
// Policy Assignments - Storage Guardrails (3 Deny + 2 Audit)
// ============================================================================

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
// Policy Assignments - Identity & Access (4 Audit)
// ============================================================================

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

resource policyIdentity03 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-identity-03'
  location: location
  properties: {
    displayName: 'SMB LZ: Audit MFA for Owners'
    description: 'Audit accounts with owner permissions that do not have MFA enabled'
    policyDefinitionId: policyDefinitions.auditMfaOwners
    enforcementMode: 'Default'
  }
}

resource policyIdentity04 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-identity-04'
  location: location
  properties: {
    displayName: 'SMB LZ: Audit Blocked Accounts'
    description: 'Audit blocked accounts with read and write permissions on Azure resources'
    policyDefinitionId: policyDefinitions.auditDeprecatedAccounts
    enforcementMode: 'Default'
  }
}

// ============================================================================
// Policy Assignments - Tagging & Governance (3 Deny)
// ============================================================================

resource policyTagging01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-tagging-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Require Environment Tag'
    description: 'Deny resource creation without Environment tag'
    policyDefinitionId: policyDefinitions.requireTag
    enforcementMode: 'Default'
    parameters: { tagName: { value: 'Environment' } }
  }
}

resource policyTagging02 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-tagging-02'
  location: location
  properties: {
    displayName: 'SMB LZ: Require Owner Tag'
    description: 'Deny resource creation without Owner tag'
    policyDefinitionId: policyDefinitions.requireTag
    enforcementMode: 'Default'
    parameters: { tagName: { value: 'Owner' } }
  }
}

resource policyGovernance01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-governance-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Allowed Locations'
    description: 'Restrict resource deployment to swedencentral, germanywestcentral, and global'
    policyDefinitionId: policyDefinitions.allowedLocations
    enforcementMode: 'Default'
    parameters: { listOfAllowedLocations: { value: allowedLocations } }
  }
}

// ============================================================================
// Policy Assignments - Backup & Monitoring (3 Audit)
// Note: smb-backup-02 (DeployIfNotExists) stays at subscription scope
// ============================================================================

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

resource policyBackup03 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-backup-03'
  location: location
  properties: {
    displayName: 'SMB LZ: Audit Storage Geo-Redundancy'
    description: 'Audit storage accounts that do not use geo-redundant storage'
    policyDefinitionId: policyDefinitions.auditStorageGeoRedundancy
    enforcementMode: 'Default'
  }
}

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
// Policy Assignments - Key Vault Guardrails (7 Audit)
// ============================================================================

resource policyKv01 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-kv-01'
  location: location
  properties: {
    displayName: 'SMB LZ: Key Vault Soft Delete'
    description: 'Audit Key Vaults that do not have soft delete enabled'
    policyDefinitionId: policyDefinitions.kvSoftDelete
    enforcementMode: 'Default'
    parameters: { effect: { value: 'Audit' } }
  }
}

resource policyKv02 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-kv-02'
  location: location
  properties: {
    displayName: 'SMB LZ: Key Vault Deletion Protection'
    description: 'Audit Key Vaults without purge protection and soft delete'
    policyDefinitionId: policyDefinitions.kvDeletionProtection
    enforcementMode: 'Default'
    parameters: { effect: { value: 'Audit' } }
  }
}

resource policyKv03 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-kv-03'
  location: location
  properties: {
    displayName: 'SMB LZ: Key Vault RBAC Model'
    description: 'Audit Key Vaults that do not use RBAC permission model'
    policyDefinitionId: policyDefinitions.kvRbacModel
    enforcementMode: 'Default'
    parameters: { effect: { value: 'Audit' } }
  }
}

resource policyKv04 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-kv-04'
  location: location
  properties: {
    displayName: 'SMB LZ: Key Vault No Public Network'
    description: 'Audit Key Vaults that have public network access enabled'
    policyDefinitionId: policyDefinitions.kvNoPublicNetwork
    enforcementMode: 'Default'
    parameters: { effect: { value: 'Audit' } }
  }
}

resource policyKv05 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-kv-05'
  location: location
  properties: {
    displayName: 'SMB LZ: Key Vault Secrets Expiration'
    description: 'Audit secrets that do not have an expiration date set'
    policyDefinitionId: policyDefinitions.kvSecretsExpiration
    enforcementMode: 'Default'
    parameters: { effect: { value: 'Audit' } }
  }
}

resource policyKv06 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-kv-06'
  location: location
  properties: {
    displayName: 'SMB LZ: Key Vault Keys Expiration'
    description: 'Audit keys that do not have an expiration date set'
    policyDefinitionId: policyDefinitions.kvKeysExpiration
    enforcementMode: 'Default'
    parameters: { effect: { value: 'Audit' } }
  }
}

resource policyKv07 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-kv-07'
  location: location
  properties: {
    displayName: 'SMB LZ: Key Vault Resource Logs'
    description: 'Audit Key Vaults that do not have resource logs enabled'
    policyDefinitionId: policyDefinitions.kvResourceLogs
    enforcementMode: 'Default'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Number of MG-scoped policy assignments')
output policyCount int = 30

@description('Policy assignment scope')
output policyScope string = 'managementGroup'
