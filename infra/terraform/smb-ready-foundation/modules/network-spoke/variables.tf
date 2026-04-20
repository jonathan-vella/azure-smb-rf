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

variable "environment" {
  type = string
}

variable "address_space" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "deploy_nat_gateway" {
  type = bool
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings (smb-monitoring-01 compliance)."
  type        = string
}

variable "route_table_id" {
  description = "Optional route table ID to associate with workload/data/app subnets (null when firewall not deployed)."
  type        = string
  default     = null
}
