variable "location" {
  type = string
}

variable "region_short" {
  type = string
}

variable "resource_group_id" {
  description = "Parent resource group resource ID."
  type        = string
}

variable "tags" {
  description = "Resource tags (must include Environment and Owner for MG tagging policies)."
  type        = map(string)
  default     = {}
}
