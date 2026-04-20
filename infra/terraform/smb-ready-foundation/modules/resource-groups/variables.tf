variable "location" {
  description = "Azure region for all RGs."
  type        = string
}

variable "rg_names" {
  description = "Map with keys: hub, monitor, backup, migrate, security, spoke."
  type        = map(string)
}

variable "shared_services_tags" {
  description = "Tags for shared-service resource groups."
  type        = map(string)
}

variable "spoke_tags" {
  description = "Tags for the spoke resource group."
  type        = map(string)
}
