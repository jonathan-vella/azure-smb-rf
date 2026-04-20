// Auto-backup policy (DINE) — subscription scope.
// Mirrors modules/policy-backup-auto.bicep.

locals {
  backup_policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/345fa903-145c-4fe1-8bcd-93ec2adccde8"
  backup_contributor_role_id  = "5e467623-bb1f-42f4-a55d-6e525e11384b"
  vm_contributor_role_id      = "9980e02c-c2be-4d73-94e8-173b1dc7cf3c"
}

resource "azurerm_subscription_policy_assignment" "backup_auto" {
  name                 = "smb-backup-02"
  display_name         = "SMB RF: Auto-Backup VMs with Backup Tag"
  description          = "Automatically configure backup on VMs tagged with Backup:true to the central Recovery Services Vault using DefaultVMPolicy (30d daily, 12w weekly, 12m monthly retention)"
  policy_definition_id = local.backup_policy_definition_id
  subscription_id      = var.subscription_resource_id
  location             = var.location
  enforce              = true

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    vaultLocation     = { value = var.location }
    inclusionTagName  = { value = "Backup" }
    inclusionTagValue = { value = ["true", "True", "yes", "Yes"] }
    backupPolicyId    = { value = var.default_vm_policy_id }
    effect            = { value = "DeployIfNotExists" }
  })
}

resource "azurerm_role_assignment" "backup_contributor" {
  scope              = var.subscription_resource_id
  role_definition_id = "${var.subscription_resource_id}/providers/Microsoft.Authorization/roleDefinitions/${local.backup_contributor_role_id}"
  principal_id       = azurerm_subscription_policy_assignment.backup_auto.identity[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "vm_contributor" {
  scope              = var.subscription_resource_id
  role_definition_id = "${var.subscription_resource_id}/providers/Microsoft.Authorization/roleDefinitions/${local.vm_contributor_role_id}"
  principal_id       = azurerm_subscription_policy_assignment.backup_auto.identity[0].principal_id
  principal_type     = "ServicePrincipal"
}
