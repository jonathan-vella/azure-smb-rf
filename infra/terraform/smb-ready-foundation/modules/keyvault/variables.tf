variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "region_short" {
  type = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod). Included in the Key Vault and private endpoint names so each environment gets its own vault and PE."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "tags" {
  type = map(string)
}

variable "tenant_id" {
  type = string
}

variable "unique_suffix" {
  type = string
}

variable "pep_subnet_id" {
  type = string
}

variable "spoke_vnet_id" {
  description = "Spoke VNet resource ID. Linked to the Key Vault private DNS zone so workloads in the spoke resolve the private endpoint IP."
  type        = string
}

variable "hub_vnet_id" {
  description = "Hub VNet resource ID. Linked to the Key Vault private DNS zone so on-prem clients (via VPN) and any hub-resident DNS resolver return the private endpoint IP. Optional — leave null to skip the hub link."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  type = string
}
