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

variable "tenant_id" {
  type = string
}

variable "unique_suffix" {
  type = string
}

variable "pep_subnet_id" {
  type = string
}

variable "log_analytics_workspace_id" {
  type = string
}
