// Recovery Services Vault + DefaultVMPolicy — AVM-TF module
// (Azure/avm-res-recoveryservices-vault/azurerm).

locals {
  name           = "rsv-smbrf-smb-${var.region_short}"
  vm_policy_name = "DefaultVMPolicy"
}

module "rsv" {
  source  = "Azure/avm-res-recoveryservices-vault/azurerm"
  version = "1.0.2"

  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  # storage_mode_type defaults to GeoRedundant — matches prior config.
  # soft_delete_enabled defaults to true — matches prior config.

  vm_backup_policy = {
    (local.vm_policy_name) = {
      name                           = local.vm_policy_name
      timezone                       = "UTC"
      policy_type                    = "V1"
      frequency                      = "Daily"
      instant_restore_retention_days = 2

      backup = {
        time = "02:00"
      }

      retention_daily = 30

      retention_weekly = {
        count    = 12
        weekdays = ["Sunday"]
      }

      retention_monthly = {
        count    = 12
        weekdays = ["Sunday"]
        weeks    = ["First"]
      }
    }
  }

  diagnostic_settings = {
    law = {
      name                  = "rsv-diag-law"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  }

  enable_telemetry = false
}
