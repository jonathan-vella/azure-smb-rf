// ============================================================================
// Input variables
// ============================================================================
// 1:1 port of params in infra/bicep/smb-ready-foundation/main.bicep with
// Terraform-idiomatic per-feature booleans replacing the `scenario` enum.
// The preprovision hook translates azd's SCENARIO env var into
// TF_VAR_deploy_firewall / TF_VAR_deploy_vpn for partner UX parity.
// ============================================================================

variable "subscription_id" {
  description = "Target Azure subscription ID. Set automatically by preprovision hook from AZURE_SUBSCRIPTION_ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid GUID."
  }
}

variable "location" {
  description = "Primary deployment region."
  type        = string
  default     = "swedencentral"

  validation {
    condition     = contains(["swedencentral", "germanywestcentral"], var.location)
    error_message = "location must be swedencentral or germanywestcentral."
  }
}

variable "environment" {
  description = "Environment name used for spoke resource naming/tagging. Shared services always tag Environment=smb."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "owner" {
  description = "Owner email or team name. Required for tagging and budget alerts."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "hub_vnet_address_space" {
  description = "Hub VNet address space (CIDR)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/(1[6-9]|2[0-9])$", var.hub_vnet_address_space))
    error_message = "hub_vnet_address_space must be a CIDR with /16–/29 prefix."
  }
}

variable "spoke_vnet_address_space" {
  description = "Spoke VNet address space (CIDR)."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/(1[6-9]|2[0-9])$", var.spoke_vnet_address_space))
    error_message = "spoke_vnet_address_space must be a CIDR with /16–/29 prefix."
  }
}

variable "on_premises_address_space" {
  description = "On-premises network CIDR used for VPN routing. Leave empty when not using VPN."
  type        = string
  default     = ""

  validation {
    condition     = var.on_premises_address_space == "" || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/\\d{1,2}$", var.on_premises_address_space))
    error_message = "on_premises_address_space must be empty or a valid CIDR."
  }
}

variable "log_analytics_daily_cap_gb" {
  description = "Log Analytics daily ingestion cap in GB. azurerm requires a number (Bicep used a string)."
  type        = number
  default     = 0.5

  validation {
    condition     = var.log_analytics_daily_cap_gb >= 0.023 && var.log_analytics_daily_cap_gb <= 100
    error_message = "log_analytics_daily_cap_gb must be between 0.023 (minimum billable) and 100 GB."
  }
}

variable "budget_amount" {
  description = "Monthly budget amount in USD."
  type        = number
  default     = 500

  validation {
    condition     = var.budget_amount >= 100 && var.budget_amount <= 10000
    error_message = "budget_amount must be between 100 and 10000 USD."
  }
}

variable "budget_alert_email" {
  description = "Budget alert email. Defaults to owner."
  type        = string
  default     = ""
}

variable "budget_start_date" {
  description = "Budget start date (YYYY-MM-01). Injected at apply time by the preprovision hook to avoid timestamp() drift."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-01$", var.budget_start_date))
    error_message = "budget_start_date must be formatted YYYY-MM-01."
  }
}

# ----- Scenario-derived booleans (authoritative input surface) ---------------

variable "deploy_firewall" {
  description = "Deploy Azure Firewall + UDR. Mirrors Bicep scenarios `firewall` and `full`."
  type        = bool
  default     = false
}

variable "deploy_vpn" {
  description = "Deploy VPN Gateway (VpnGw1AZ). Mirrors Bicep scenarios `vpn` and `full`."
  type        = bool
  default     = false
}

# ----- Management group + policy assignments ---------------------------------

variable "management_group_name" {
  description = "Name (id) of the intermediate management group to create under tenant root."
  type        = string
  default     = "smb-rf"
}

variable "management_group_display_name" {
  description = "Display name of the management group."
  type        = string
  default     = "SMB Ready Foundation"
}

variable "assignment_location" {
  description = "Location for policy assignment metadata."
  type        = string
  default     = "swedencentral"
}

variable "allowed_locations" {
  description = "Allowed Azure regions for the allowed-locations policy."
  type        = list(string)
  default = [
    "swedencentral",
    "germanywestcentral",
    "global",
  ]
}

variable "allowed_vm_skus" {
  description = "Allowed VM SKUs (B-series + D/E v5/v6). Must match the Bicep list exactly."
  type        = list(string)
  default = [
    "Standard_B1ls",
    "Standard_B1s",
    "Standard_B1ms",
    "Standard_B2s",
    "Standard_B2ms",
    "Standard_B2ls_v2",
    "Standard_B2s_v2",
    "Standard_B2ms_v2",
    "Standard_B4ms",
    "Standard_B4ls_v2",
    "Standard_B4s_v2",
    "Standard_B4ms_v2",
    "Standard_B8ms",
    "Standard_B8ls_v2",
    "Standard_B8s_v2",
    "Standard_B8ms_v2",
    "Standard_D2s_v5",
    "Standard_D4s_v5",
    "Standard_D8s_v5",
    "Standard_D16s_v5",
    "Standard_D2ds_v5",
    "Standard_D4ds_v5",
    "Standard_D8ds_v5",
    "Standard_D2s_v6",
    "Standard_D4s_v6",
    "Standard_D8s_v6",
    "Standard_E2s_v5",
    "Standard_E4s_v5",
    "Standard_E8s_v5",
    "Standard_E2ds_v5",
    "Standard_E4ds_v5",
    "Standard_E2s_v6",
    "Standard_E4s_v6",
  ]
}
