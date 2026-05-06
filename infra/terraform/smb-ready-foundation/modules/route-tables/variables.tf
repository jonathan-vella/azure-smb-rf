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

variable "firewall_private_ip" {
  type = string
}

variable "spoke_vnet_address_space" {
  type = string
}

variable "on_premises_address_space" {
  type = string
}

variable "route_hybrid_through_firewall" {
  description = "Force spoke<->on-prem traffic through the firewall (scenario=full). When true, adds a more-specific spoke->on-prem UDR and a GatewaySubnet UDR for the return path. Requires on_premises_address_space, hub_vnet_id, and gateway_subnet_address_prefix to be set."
  type        = bool
  default     = false
}

variable "hub_vnet_id" {
  description = "Hub VNet resource ID. Required when route_hybrid_through_firewall=true so the GatewaySubnet UDR can be attached via azapi_update_resource."
  type        = string
  default     = ""
}

variable "hub_vnet_name" {
  description = "Hub VNet name (kept for parity with Bicep; the azapi update uses hub_vnet_id directly)."
  type        = string
  default     = ""
}

variable "gateway_subnet_address_prefix" {
  description = "GatewaySubnet address prefix. Required when route_hybrid_through_firewall=true so azapi_update_resource can re-PUT the subnet with addressPrefix + routeTable."
  type        = string
  default     = ""
}
