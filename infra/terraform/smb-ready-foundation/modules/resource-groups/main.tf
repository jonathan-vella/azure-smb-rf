// Resource groups — 5 shared + 1 spoke.

locals {
  shared_rg_keys = ["hub", "monitor", "backup", "migrate", "security"]
}

resource "azurerm_resource_group" "shared" {
  for_each = toset(local.shared_rg_keys)

  name     = var.rg_names[each.key]
  location = var.location
  tags     = var.shared_services_tags
}

resource "azurerm_resource_group" "spoke" {
  name     = var.rg_names["spoke"]
  location = var.location
  tags     = var.spoke_tags
}
