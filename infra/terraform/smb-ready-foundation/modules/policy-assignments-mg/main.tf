// MG-scoped governance via a single custom Policy Set (Initiative).
//
// Replaces 33 individual policy assignments with one initiative containing
// 33 policyDefinitionReferences and one initiative assignment.
//
// Rationale:
//   - Atomic lifecycle: all policies enable/disable/version together.
//   - Simpler compliance reporting: one initiative compliance score.
//   - Faster destroy: 2 MG objects instead of 33 assignments.
//
// The DINE `smb-backup-02` policy stays sub-scoped in the separate
// `policy-backup-auto` module because it needs a subscription-scoped
// SystemAssigned identity with role assignments (Backup Contributor,
// VM Contributor) that cannot be expressed via a MG-scoped initiative.

locals {
  # ------------------------------------------------------------------
  # Built-in policy definition IDs
  # ------------------------------------------------------------------
  policy_definitions = {
    allowedVmSkus             = "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3"
    noPublicIpOnNic           = "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114"
    auditManagedDisks         = "/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d"
    auditArmVms               = "/providers/Microsoft.Authorization/policyDefinitions/1d84d5fb-01f6-4d12-ba4f-4a26081d403d"
    auditSystemUpdates        = "/providers/Microsoft.Authorization/policyDefinitions/86b3d65f-7626-441e-b690-81a8b71cff60"
    auditEndpointProtection   = "/providers/Microsoft.Authorization/policyDefinitions/26a828e1-e88f-464e-bbb3-c134a282b9de"
    nsgOnSubnets              = "/providers/Microsoft.Authorization/policyDefinitions/e71308d3-144b-4262-b144-efdc3cc90517"
    closeManagementPorts      = "/providers/Microsoft.Authorization/policyDefinitions/22730e10-96f6-4aac-ad84-9383d35b5917"
    restrictNsgPorts          = "/providers/Microsoft.Authorization/policyDefinitions/9daedab3-fb2d-461e-b861-71790eead4f6"
    disableIpForwarding       = "/providers/Microsoft.Authorization/policyDefinitions/88c0b9da-ce96-4b03-9635-f29a937e2900"
    nsgFlowLogs               = "/providers/Microsoft.Authorization/policyDefinitions/27960feb-a23c-4577-8d36-ef8b5f35e0be"
    storageHttpsOnly          = "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9"
    noPublicBlobAccess        = "/providers/Microsoft.Authorization/policyDefinitions/4fa4b6c0-31ca-4c0d-b10d-24b96f62a751"
    storageTls12              = "/providers/Microsoft.Authorization/policyDefinitions/fe83a0eb-a853-422d-aac2-1bffd182c5d0"
    restrictStorageNetwork    = "/providers/Microsoft.Authorization/policyDefinitions/34c877ad-507e-4c82-993e-3452a6e0ad3c"
    storageArmMigration       = "/providers/Microsoft.Authorization/policyDefinitions/37e0d2fe-28a5-43d6-a273-67d37d1f5606"
    auditStorageGeoRedundancy = "/providers/Microsoft.Authorization/policyDefinitions/bf045164-79ba-4215-8f95-f8048dc1780b"
    sqlAzureAdOnly            = "/providers/Microsoft.Authorization/policyDefinitions/b3a22bc9-66de-45fb-98fa-00f5df42f41a"
    sqlNoPublicAccess         = "/providers/Microsoft.Authorization/policyDefinitions/1b8ca024-1d5c-4dec-8995-b1a932b41780"
    auditMfaOwners            = "/providers/Microsoft.Authorization/policyDefinitions/aa633080-8b72-40c4-a2d7-d00c03e80bed"
    auditDeprecatedAccounts   = "/providers/Microsoft.Authorization/policyDefinitions/8d7e1fde-fe26-4b5f-8108-f8e432cbc2be"
    requireTag                = "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99"
    allowedLocations          = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    vmBackupRequired          = "/providers/Microsoft.Authorization/policyDefinitions/013e242c-8828-4970-87b3-ab247555486d"
    diagnosticSettings        = "/providers/Microsoft.Authorization/policyDefinitions/7f89b1eb-583c-429a-8828-af049802c1d9"
    kvSoftDelete              = "/providers/Microsoft.Authorization/policyDefinitions/1e66c121-a66a-4b1f-9b83-0fd99bf0fc2d"
    kvDeletionProtection      = "/providers/Microsoft.Authorization/policyDefinitions/0b60c0b2-2dc2-4e1c-b5c9-abbed971de53"
    kvRbacModel               = "/providers/Microsoft.Authorization/policyDefinitions/12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5"
    kvNoPublicNetwork         = "/providers/Microsoft.Authorization/policyDefinitions/405c5871-3e91-4644-8a63-58e19d68ff5b"
    kvSecretsExpiration       = "/providers/Microsoft.Authorization/policyDefinitions/98728c90-32c7-4049-8429-847dc0f4fe37"
    kvKeysExpiration          = "/providers/Microsoft.Authorization/policyDefinitions/152b15f7-8e1f-4c1f-ab71-8c010ba5dbc0"
    kvResourceLogs            = "/providers/Microsoft.Authorization/policyDefinitions/cf820ca0-f99e-4f3e-84fb-66e913812d21"
  }

  # ------------------------------------------------------------------
  # Policy references with hard-coded parameters (initiative body).
  # reference_id = the short smb-* policy name; identical to the
  # previous per-assignment name for compliance-report continuity.
  # ------------------------------------------------------------------
  uniform_refs = {
    "smb-compute-02"  = local.policy_definitions.noPublicIpOnNic
    "smb-compute-03"  = local.policy_definitions.auditManagedDisks
    "smb-compute-04"  = local.policy_definitions.auditArmVms
    "smb-compute-05"  = local.policy_definitions.auditSystemUpdates
    "smb-compute-06"  = local.policy_definitions.auditEndpointProtection
    "smb-network-01"  = local.policy_definitions.nsgOnSubnets
    "smb-network-02"  = local.policy_definitions.closeManagementPorts
    "smb-network-03"  = local.policy_definitions.restrictNsgPorts
    "smb-network-04"  = local.policy_definitions.disableIpForwarding
    "smb-network-05"  = local.policy_definitions.nsgFlowLogs
    "smb-storage-01"  = local.policy_definitions.storageHttpsOnly
    "smb-storage-02"  = local.policy_definitions.noPublicBlobAccess
    "smb-storage-03"  = local.policy_definitions.storageTls12
    "smb-storage-04"  = local.policy_definitions.restrictStorageNetwork
    "smb-storage-05"  = local.policy_definitions.storageArmMigration
    "smb-identity-01" = local.policy_definitions.sqlAzureAdOnly
    "smb-identity-02" = local.policy_definitions.sqlNoPublicAccess
    "smb-identity-03" = local.policy_definitions.auditMfaOwners
    "smb-identity-04" = local.policy_definitions.auditDeprecatedAccounts
    "smb-backup-01"   = local.policy_definitions.vmBackupRequired
    "smb-backup-03"   = local.policy_definitions.auditStorageGeoRedundancy
    "smb-kv-07"       = local.policy_definitions.kvResourceLogs
  }

  # Key Vault audit policies — `effect = Audit` parameter.
  kv_audit_refs = {
    "smb-kv-01" = local.policy_definitions.kvSoftDelete
    "smb-kv-02" = local.policy_definitions.kvDeletionProtection
    "smb-kv-03" = local.policy_definitions.kvRbacModel
    "smb-kv-04" = local.policy_definitions.kvNoPublicNetwork
    "smb-kv-05" = local.policy_definitions.kvSecretsExpiration
    "smb-kv-06" = local.policy_definitions.kvKeysExpiration
  }

  diagnostic_resource_types = [
    "Microsoft.Compute/virtualMachines",
    "Microsoft.Network/virtualNetworks",
    "Microsoft.Network/networkSecurityGroups",
    "Microsoft.Network/azureFirewalls",
    "Microsoft.Network/bastionHosts",
    "Microsoft.KeyVault/vaults",
    "Microsoft.RecoveryServices/vaults",
    "Microsoft.Sql/servers",
  ]

  # Total references = 22 uniform + 6 kv_audit + 5 parameterised = 33
  total_policy_refs = length(local.uniform_refs) + length(local.kv_audit_refs) + 5
}

# ============================================================================
# Policy Set Definition (Initiative)
# ============================================================================
resource "azurerm_management_group_policy_set_definition" "smb_baseline" {
  name                = "smb-baseline"
  policy_type         = "Custom"
  display_name        = "SMB RF: Baseline Compliance Initiative"
  description         = "Aggregates all SMB Ready Foundation governance policies into a single initiative. Replaces 33 individual MG-scoped assignments."
  management_group_id = var.management_group_id

  metadata = jsonencode({
    category = "SMB Ready Foundation"
    version  = "1.0.0"
  })

  parameters = jsonencode({
    allowedLocations = {
      type = "Array"
      metadata = {
        displayName = "Allowed locations"
        description = "Regions where resources may be deployed (smb-governance-01)."
      }
    }
    allowedVmSkus = {
      type = "Array"
      metadata = {
        displayName = "Allowed VM SKUs"
        description = "VM SKUs permitted by smb-compute-01."
      }
    }
  })

  # ---- Uniform policies (no parameters) -----------------------------
  dynamic "policy_definition_reference" {
    for_each = local.uniform_refs
    content {
      reference_id         = policy_definition_reference.key
      policy_definition_id = policy_definition_reference.value
    }
  }

  # ---- Key Vault audits (effect=Audit) ------------------------------
  dynamic "policy_definition_reference" {
    for_each = local.kv_audit_refs
    content {
      reference_id         = policy_definition_reference.key
      policy_definition_id = policy_definition_reference.value
      parameter_values = jsonencode({
        effect = { value = "Audit" }
      })
    }
  }

  # ---- smb-compute-01 : Allowed VM SKUs (initiative param) ----------
  policy_definition_reference {
    reference_id         = "smb-compute-01"
    policy_definition_id = local.policy_definitions.allowedVmSkus
    parameter_values = jsonencode({
      listOfAllowedSKUs = { value = "[parameters('allowedVmSkus')]" }
    })
  }

  # ---- smb-tagging-01 : Require Environment tag ---------------------
  policy_definition_reference {
    reference_id         = "smb-tagging-01"
    policy_definition_id = local.policy_definitions.requireTag
    parameter_values = jsonencode({
      tagName = { value = "Environment" }
    })
  }

  # ---- smb-tagging-02 : Require Owner tag ---------------------------
  policy_definition_reference {
    reference_id         = "smb-tagging-02"
    policy_definition_id = local.policy_definitions.requireTag
    parameter_values = jsonencode({
      tagName = { value = "Owner" }
    })
  }

  # ---- smb-governance-01 : Allowed locations (initiative param) -----
  policy_definition_reference {
    reference_id         = "smb-governance-01"
    policy_definition_id = local.policy_definitions.allowedLocations
    parameter_values = jsonencode({
      listOfAllowedLocations = { value = "[parameters('allowedLocations')]" }
    })
  }

  # ---- smb-monitoring-01 : Diagnostic settings required -------------
  policy_definition_reference {
    reference_id         = "smb-monitoring-01"
    policy_definition_id = local.policy_definitions.diagnosticSettings
    parameter_values = jsonencode({
      listOfResourceTypes = { value = local.diagnostic_resource_types }
    })
  }
}

# ============================================================================
# Single initiative assignment
# ============================================================================
resource "azurerm_management_group_policy_assignment" "smb_baseline" {
  name                 = "smb-baseline"
  display_name         = "SMB RF: Baseline Compliance"
  description          = "Assigns the SMB baseline initiative (${local.total_policy_refs} policies) to the management group."
  policy_definition_id = azurerm_management_group_policy_set_definition.smb_baseline.id
  management_group_id  = var.management_group_id
  enforce              = true
  location             = var.assignment_location

  parameters = jsonencode({
    allowedLocations = { value = var.allowed_locations }
    allowedVmSkus    = { value = var.allowed_vm_skus }
  })
}
