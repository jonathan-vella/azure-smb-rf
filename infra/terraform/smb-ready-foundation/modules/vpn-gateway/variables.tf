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

variable "gateway_subnet_id" {
  type = string
}

variable "firewall_serialisation_sentinel" {
  description = "Firewall id (or empty string). Creates a plan-time data-flow edge from firewall → vpn gateway so the two do not mutate the hub VNet in parallel."
  type        = string
}
