// Management group + subscription association
// Mirrors infra/bicep/smb-ready-foundation/deploy-mg.bicep.
// The matching `import` block lives in the root main.tf (import blocks are
// only allowed in the root module).

resource "azurerm_management_group" "smb_rf" {
  name         = var.name
  display_name = var.display_name

  lifecycle {
    ignore_changes = [subscription_ids]
  }
}

resource "azurerm_management_group_subscription_association" "primary" {
  management_group_id = azurerm_management_group.smb_rf.id
  subscription_id     = "/subscriptions/${var.subscription_id}"
}
