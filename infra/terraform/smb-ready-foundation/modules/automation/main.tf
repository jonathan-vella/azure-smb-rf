// Azure Automation Account — AVM-TF module
// (Azure/avm-res-automation-automationaccount/azurerm). AVM handles diag.
// The Log Analytics linked service is NOT covered by AVM, so it stays
// hand-rolled in this wrapper module.

locals {
  name = "aa-smbrf-smb-${var.region_short}"
}

module "aa" {
  source  = "Azure/avm-res-automation-automationaccount/azurerm"
  version = "0.2.0"

  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
  tags                = var.tags

  public_network_access_enabled = false

  managed_identities = {
    system_assigned = true
  }

  diagnostic_settings = {
    law = {
      name                  = "aa-diag-law"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  }

  enable_telemetry = false
}

resource "azurerm_log_analytics_linked_service" "automation" {
  resource_group_name = var.resource_group_name
  workspace_id        = var.log_analytics_workspace_id
  read_access_id      = module.aa.resource_id
}
