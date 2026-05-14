// Route tables for firewall-based egress (conditional via var.enabled).
//
// Hybrid (spoke <-> on-prem) routing:
//   - var.route_hybrid_through_firewall = false (default): only the spoke
//     egress UDR (0.0.0.0/0 -> firewall) is created. Hybrid traffic is
//     allowed to bypass the firewall via gateway-propagated routes.
//   - var.route_hybrid_through_firewall = true (scenario=full): adds a
//     more-specific spoke UDR (on-prem CIDR -> firewall) AND a
//     GatewaySubnet UDR (spoke CIDR -> firewall) for the return path.
//     The GatewaySubnet UDR is attached via azapi_update_resource to
//     avoid two-writer drift with the AVM hub VNet module.
//   Mirrors the Bicep route-tables module.

terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

locals {
  has_on_premises = length(var.on_premises_address_space) > 0
  spoke_rt_name   = "rt-spoke-smb-${var.region_short}"
  gateway_rt_name = "rt-gateway-smb-${var.region_short}"

  # Only create + attach the GatewaySubnet UDR when scenario=full and all
  # required inputs are present.
  attach_gateway_rt = var.enabled && var.route_hybrid_through_firewall && local.has_on_premises && length(var.hub_vnet_name) > 0 && length(var.gateway_subnet_address_prefix) > 0
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
    for_each = var.route_hybrid_through_firewall && local.has_on_premises ? [1] : []
    content {
      name                   = "route-to-onprem-via-firewall"
      address_prefix         = var.on_premises_address_space
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.firewall_private_ip
    }
  }
}

resource "azurerm_route_table" "gateway" {
  count = local.attach_gateway_rt ? 1 : 0

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

# Attach the gateway route table to the existing GatewaySubnet via azapi
# update. This mirrors the Bicep child-subnet PATCH and avoids a cycle with
# the AVM-managed hub VNet module (network-hub does not need to know about
# route-tables to render the VNet).
resource "azapi_update_resource" "gateway_subnet_rt" {
  count = local.attach_gateway_rt ? 1 : 0

  type        = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  resource_id = "${var.hub_vnet_id}/subnets/GatewaySubnet"

  body = {
    properties = {
      addressPrefix = var.gateway_subnet_address_prefix
      routeTable = {
        id = azurerm_route_table.gateway[0].id
      }
    }
  }
}

// Spoke route-table association is done inside the AVM spoke vnet subnet map
// (via var.route_table_id in modules/network-spoke) to avoid two-writer
// drift with the AVM-managed subnets.
