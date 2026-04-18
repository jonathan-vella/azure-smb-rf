variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  description = "Resource group resource ID (parent_id for the AVM VNet module)."
  type        = string
}

variable "region_short" {
  type = string
}

variable "address_space" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings (smb-monitoring-01 compliance)."
  type        = string
}
