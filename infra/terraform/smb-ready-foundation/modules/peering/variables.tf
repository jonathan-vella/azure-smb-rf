variable "enabled" {
  type = bool
}

variable "deploy_vpn" {
  type = bool
}

variable "hub_resource_group_name" {
  type = string
}

variable "spoke_resource_group_name" {
  type = string
}

variable "hub_vnet_name" {
  type = string
}

variable "spoke_vnet_name" {
  type = string
}

variable "hub_vnet_id" {
  type = string
}

variable "spoke_vnet_id" {
  type = string
}

variable "vpn_gateway_id" {
  description = "VPN gateway id (or empty string). Drives the terraform_data relay."
  type        = string
}
