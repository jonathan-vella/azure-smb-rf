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

variable "on_premises_address_space" {
  description = "On-premises CIDR for the Local Network Gateway. RFC 5737 placeholder (192.0.2.0/24) is used when empty so the LNG can still be created and partners can update it post-deploy without touching code."
  type        = string
  default     = ""
}

variable "on_premises_gateway_public_ip" {
  description = "On-premises VPN device public IP for the Local Network Gateway. RFC 5737 placeholder (192.0.2.1) is used when empty."
  type        = string
  default     = ""
}
