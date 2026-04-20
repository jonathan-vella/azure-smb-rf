// Microsoft Defender for Cloud — Free tier, auto-provisioning Off.

locals {
  plans = ["VirtualMachines", "StorageAccounts", "KeyVaults", "Arm"]
}

resource "azurerm_security_center_subscription_pricing" "free" {
  for_each = toset(local.plans)

  tier          = "Free"
  resource_type = each.key
}

// Note: azurerm_security_center_auto_provisioning was removed in azurerm v5.
// It deployed the legacy MMA agent, which Microsoft has retired in favour of
// AMA auto-deployment via the Defender for Servers plan. On the Free tier
// (which this module uses) there is no plan to trigger deployment, so
// removing this resource is a safe no-op.
