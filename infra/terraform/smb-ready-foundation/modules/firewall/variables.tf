variable "enabled" {
  type = bool
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "region_short" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "afw_subnet_id" {
  type = string
}

variable "afw_mgmt_subnet_id" {
  type = string
}

variable "spoke_vnet_address_space" {
  type = string
}

variable "on_premises_address_space" {
  type    = string
  default = ""
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for firewall diagnostic settings (smb-monitoring-01 compliance)."
  type        = string
}
