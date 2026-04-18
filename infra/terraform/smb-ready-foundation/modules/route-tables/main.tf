// Route tables for firewall-based egress (conditional via var.enabled).

locals {
  has_on_premises = length(var.on_premises_address_space) > 0
  spoke_rt_name   = "rt-spoke-smb-${var.region_short}"
  gateway_rt_name = "rt-gateway-smb-${var.region_short}"
}

resource "azurerm_route_table" "spoke" {
  count = var.enabled ? 1 : 0

  name                          = local.spoke_rt_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tags                          = var.tags
  bgp_route_propagation_enabled = true

  route {
    name                   = "route-to-internet-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  dynamic "route" {
    for_each = local.has_on_premises ? [1] : []
    content {
      name                   = "route-to-onprem-via-firewall"
      address_prefix         = var.on_premises_address_space
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.firewall_private_ip
    }
  }
}

resource "azurerm_route_table" "gateway" {
  count = var.enabled && local.has_on_premises ? 1 : 0

  name                          = local.gateway_rt_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tags                          = var.tags
  bgp_route_propagation_enabled = true

  route {
    name                   = "route-to-spoke-via-firewall"
    address_prefix         = var.spoke_vnet_address_space
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
}

// Route-table association is now done inside the AVM spoke vnet subnet map
// (via var.route_table_id in modules/network-spoke) to avoid two-writer
// drift with azapi_resource.subnet.

