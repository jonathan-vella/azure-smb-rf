// ============================================================================
// SMB Ready Foundation - MG-Scoped Policy Set (Initiative)
// ============================================================================
// Purpose: Mirror of infra/terraform/.../modules/policy-assignments-mg/main.tf.
//          Defines ONE custom Policy Set (Initiative) containing 33 built-in
//          policy references and ONE MG-scoped assignment, replacing the
//          30-individual-assignment approach in policy-assignments-mg.bicep.
//
// Rationale (same as the Terraform version):
//   - Atomic lifecycle: all policies enable/disable/version together.
//   - Simpler compliance reporting: one initiative compliance score.
//   - Faster destroy: 2 MG objects instead of 33 assignments.
//
// The DINE policy smb-backup-02 stays sub-scoped in policy-backup-auto.bicep
// because it needs a subscription-scoped SystemAssigned identity with role
// assignments (Backup Contributor, VM Contributor) that cannot be expressed
// via an MG-scoped initiative.
//
// Scope: Management Group (smb-rf)
// Deployment: az deployment mg create --management-group-id smb-rf \
//               --location <region> --template-file policy-assignments-mg-initiative.bicep
// Version: v1.0
// ============================================================================

targetScope = 'managementGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Location metadata for the policy assignment')
param location string = 'swedencentral'

@description('Allowed Azure regions (initiative parameter — feeds smb-governance-01)')
param allowedLocations array = [
  'swedencentral'
  'germanywestcentral'
  'global'
]

@description('Allowed VM SKUs (initiative parameter — feeds smb-compute-01)')
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
// Variables — Built-in policy definition IDs (tenant-scoped)
// ============================================================================

var policyDefinitions = {
  // Compute
  allowedVmSkus: '/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3'
  noPublicIpOnNic: '/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114'
  auditManagedDisks: '/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d'
  auditArmVms: '/providers/Microsoft.Authorization/policyDefinitions/1d84d5fb-01f6-4d12-ba4f-4a26081d403d'
  auditSystemUpdates: '/providers/Microsoft.Authorization/policyDefinitions/86b3d65f-7626-441e-b690-81a8b71cff60'
  auditEndpointProtection: '/providers/Microsoft.Authorization/policyDefinitions/26a828e1-e88f-464e-bbb3-c134a282b9de'
  // Network
  nsgOnSubnets: '/providers/Microsoft.Authorization/policyDefinitions/e71308d3-144b-4262-b144-efdc3cc90517'
  closeManagementPorts: '/providers/Microsoft.Authorization/policyDefinitions/22730e10-96f6-4aac-ad84-9383d35b5917'
  restrictNsgPorts: '/providers/Microsoft.Authorization/policyDefinitions/9daedab3-fb2d-461e-b861-71790eead4f6'
  disableIpForwarding: '/providers/Microsoft.Authorization/policyDefinitions/88c0b9da-ce96-4b03-9635-f29a937e2900'
  nsgFlowLogs: '/providers/Microsoft.Authorization/policyDefinitions/27960feb-a23c-4577-8d36-ef8b5f35e0be'
  // Storage
  storageHttpsOnly: '/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9'
  noPublicBlobAccess: '/providers/Microsoft.Authorization/policyDefinitions/4fa4b6c0-31ca-4c0d-b10d-24b96f62a751'
  storageTls12: '/providers/Microsoft.Authorization/policyDefinitions/fe83a0eb-a853-422d-aac2-1bffd182c5d0'
  restrictStorageNetwork: '/providers/Microsoft.Authorization/policyDefinitions/34c877ad-507e-4c82-993e-3452a6e0ad3c'
  storageArmMigration: '/providers/Microsoft.Authorization/policyDefinitions/37e0d2fe-28a5-43d6-a273-67d37d1f5606'
  auditStorageGeoRedundancy: '/providers/Microsoft.Authorization/policyDefinitions/bf045164-79ba-4215-8f95-f8048dc1780b'
  // Identity
  sqlAzureAdOnly: '/providers/Microsoft.Authorization/policyDefinitions/b3a22bc9-66de-45fb-98fa-00f5df42f41a'
  sqlNoPublicAccess: '/providers/Microsoft.Authorization/policyDefinitions/1b8ca024-1d5c-4dec-8995-b1a932b41780'
  auditMfaOwners: '/providers/Microsoft.Authorization/policyDefinitions/aa633080-8b72-40c4-a2d7-d00c03e80bed'
  auditDeprecatedAccounts: '/providers/Microsoft.Authorization/policyDefinitions/8d7e1fde-fe26-4b5f-8108-f8e432cbc2be'
  // Tagging / Governance
  requireTag: '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
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
}

// Resource types for smb-monitoring-01 (diagnostic settings required)
var diagnosticResourceTypes = [
  'Microsoft.Compute/virtualMachines'
  'Microsoft.Network/virtualNetworks'
  'Microsoft.Network/networkSecurityGroups'
  'Microsoft.Network/azureFirewalls'
  'Microsoft.Network/bastionHosts'
  'Microsoft.KeyVault/vaults'
  'Microsoft.RecoveryServices/vaults'
  'Microsoft.Sql/servers'
]

// ============================================================================
// Policy Set Definition (Initiative) — 33 policy references
// ============================================================================

resource smbBaseline 'Microsoft.Authorization/policySetDefinitions@2023-04-01' = {
  name: 'smb-baseline'
  properties: {
    policyType: 'Custom'
    displayName: 'SMB RF: Baseline Compliance Initiative'
    description: 'Aggregates all SMB Ready Foundation governance policies into a single initiative. Replaces 33 individual MG-scoped assignments.'
    metadata: {
      category: 'SMB Ready Foundation'
      version: '1.0.0'
    }
    parameters: {
      allowedLocations: {
        type: 'Array'
        metadata: {
          displayName: 'Allowed locations'
          description: 'Regions where resources may be deployed (smb-governance-01).'
        }
      }
      allowedVmSkus: {
        type: 'Array'
        metadata: {
          displayName: 'Allowed VM SKUs'
          description: 'VM SKUs permitted by smb-compute-01.'
        }
      }
    }
    policyDefinitions: [
      // ---------- 22 uniform policies (no parameters) ----------
      { policyDefinitionReferenceId: 'smb-compute-02', policyDefinitionId: policyDefinitions.noPublicIpOnNic }
      { policyDefinitionReferenceId: 'smb-compute-03', policyDefinitionId: policyDefinitions.auditManagedDisks }
      { policyDefinitionReferenceId: 'smb-compute-04', policyDefinitionId: policyDefinitions.auditArmVms }
      { policyDefinitionReferenceId: 'smb-compute-05', policyDefinitionId: policyDefinitions.auditSystemUpdates }
      { policyDefinitionReferenceId: 'smb-compute-06', policyDefinitionId: policyDefinitions.auditEndpointProtection }
      { policyDefinitionReferenceId: 'smb-network-01', policyDefinitionId: policyDefinitions.nsgOnSubnets }
      { policyDefinitionReferenceId: 'smb-network-02', policyDefinitionId: policyDefinitions.closeManagementPorts }
      { policyDefinitionReferenceId: 'smb-network-03', policyDefinitionId: policyDefinitions.restrictNsgPorts }
      { policyDefinitionReferenceId: 'smb-network-04', policyDefinitionId: policyDefinitions.disableIpForwarding }
      { policyDefinitionReferenceId: 'smb-network-05', policyDefinitionId: policyDefinitions.nsgFlowLogs }
      { policyDefinitionReferenceId: 'smb-storage-01', policyDefinitionId: policyDefinitions.storageHttpsOnly }
      { policyDefinitionReferenceId: 'smb-storage-02', policyDefinitionId: policyDefinitions.noPublicBlobAccess }
      { policyDefinitionReferenceId: 'smb-storage-03', policyDefinitionId: policyDefinitions.storageTls12 }
      { policyDefinitionReferenceId: 'smb-storage-04', policyDefinitionId: policyDefinitions.restrictStorageNetwork }
      { policyDefinitionReferenceId: 'smb-storage-05', policyDefinitionId: policyDefinitions.storageArmMigration }
      { policyDefinitionReferenceId: 'smb-identity-01', policyDefinitionId: policyDefinitions.sqlAzureAdOnly }
      { policyDefinitionReferenceId: 'smb-identity-02', policyDefinitionId: policyDefinitions.sqlNoPublicAccess }
      { policyDefinitionReferenceId: 'smb-identity-03', policyDefinitionId: policyDefinitions.auditMfaOwners }
      { policyDefinitionReferenceId: 'smb-identity-04', policyDefinitionId: policyDefinitions.auditDeprecatedAccounts }
      { policyDefinitionReferenceId: 'smb-backup-01', policyDefinitionId: policyDefinitions.vmBackupRequired }
      { policyDefinitionReferenceId: 'smb-backup-03', policyDefinitionId: policyDefinitions.auditStorageGeoRedundancy }
      { policyDefinitionReferenceId: 'smb-kv-07', policyDefinitionId: policyDefinitions.kvResourceLogs }

      // ---------- 6 Key Vault audits (effect = Audit) ----------
      {
        policyDefinitionReferenceId: 'smb-kv-01'
        policyDefinitionId: policyDefinitions.kvSoftDelete
        parameters: { effect: { value: 'Audit' } }
      }
      {
        policyDefinitionReferenceId: 'smb-kv-02'
        policyDefinitionId: policyDefinitions.kvDeletionProtection
        parameters: { effect: { value: 'Audit' } }
      }
      {
        policyDefinitionReferenceId: 'smb-kv-03'
        policyDefinitionId: policyDefinitions.kvRbacModel
        parameters: { effect: { value: 'Audit' } }
      }
      {
        policyDefinitionReferenceId: 'smb-kv-04'
        policyDefinitionId: policyDefinitions.kvNoPublicNetwork
        parameters: { effect: { value: 'Audit' } }
      }
      {
        policyDefinitionReferenceId: 'smb-kv-05'
        policyDefinitionId: policyDefinitions.kvSecretsExpiration
        parameters: { effect: { value: 'Audit' } }
      }
      {
        policyDefinitionReferenceId: 'smb-kv-06'
        policyDefinitionId: policyDefinitions.kvKeysExpiration
        parameters: { effect: { value: 'Audit' } }
      }

      // ---------- 5 explicit parameterised policies ----------
      {
        policyDefinitionReferenceId: 'smb-compute-01'
        policyDefinitionId: policyDefinitions.allowedVmSkus
        parameters: {
          listOfAllowedSKUs: { value: '[parameters(\'allowedVmSkus\')]' }
        }
      }
      {
        policyDefinitionReferenceId: 'smb-tagging-01'
        policyDefinitionId: policyDefinitions.requireTag
        parameters: {
          tagName: { value: 'Environment' }
        }
      }
      {
        policyDefinitionReferenceId: 'smb-tagging-02'
        policyDefinitionId: policyDefinitions.requireTag
        parameters: {
          tagName: { value: 'Owner' }
        }
      }
      {
        policyDefinitionReferenceId: 'smb-governance-01'
        policyDefinitionId: policyDefinitions.allowedLocations
        parameters: {
          listOfAllowedLocations: { value: '[parameters(\'allowedLocations\')]' }
        }
      }
      {
        policyDefinitionReferenceId: 'smb-monitoring-01'
        policyDefinitionId: policyDefinitions.diagnosticSettings
        parameters: {
          listOfResourceTypes: { value: diagnosticResourceTypes }
        }
      }
    ]
  }
}

// ============================================================================
// Single initiative assignment
// ============================================================================

resource smbBaselineAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'smb-baseline'
  location: location
  properties: {
    displayName: 'SMB RF: Baseline Compliance'
    description: 'Assigns the SMB baseline initiative (33 policies) to the management group.'
    policyDefinitionId: smbBaseline.id
    enforcementMode: 'Default'
    parameters: {
      allowedLocations: { value: allowedLocations }
      allowedVmSkus: { value: allowedVmSkus }
    }
  }
  identity: {
    type: 'None'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Policy set (initiative) resource ID')
output initiativeId string = smbBaseline.id

@description('Policy set (initiative) name')
output initiativeName string = smbBaseline.name

@description('Number of policy references inside the initiative')
output initiativePolicyCount int = 33

@description('Number of MG-scoped policy assignments created')
output policyAssignmentCount int = 1

@description('Policy assignment scope')
output policyScope string = 'managementGroup'
