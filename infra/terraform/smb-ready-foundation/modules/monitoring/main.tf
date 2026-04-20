// Log Analytics Workspace — AVM-TF module
// (Azure/avm-res-operationalinsights-workspace/azurerm).

locals {
  name           = "log-smbrf-smb-${var.region_short}"
  daily_quota_gb = var.daily_cap_gb > 0 ? var.daily_cap_gb : -1
}

module "law" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  log_analytics_workspace_sku                        = "PerGB2018"
  log_analytics_workspace_retention_in_days          = 30
  log_analytics_workspace_daily_quota_gb             = local.daily_quota_gb
  log_analytics_workspace_internet_ingestion_enabled = "true"
  log_analytics_workspace_internet_query_enabled     = "true"

  enable_telemetry = false
}
