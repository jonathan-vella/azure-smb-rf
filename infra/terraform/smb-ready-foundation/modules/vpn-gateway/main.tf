// VPN Gateway VpnGw1AZ (conditional via var.enabled).
// firewall_depends_on carries the firewall id (or "") so Terraform serialises
// on the hub VNet even with no explicit resource reference.

locals {
  gw_name  = "vpng-hub-smb-${var.region_short}"
  pip_name = "pip-vpn-smb-${var.region_short}"
}

resource "azurerm_public_ip" "vpn" {
  count = var.enabled ? 1 : 0

  name                = local.pip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count = var.enabled ? 1 : 0

  name                = local.gw_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  type          = "Vpn"
  vpn_type      = "RouteBased"
  generation    = "Generation1"
  sku           = "VpnGw1AZ"
  active_active = false
  bgp_enabled   = false

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = var.gateway_subnet_id
  }

  # The sentinel input forces TF to wait for the firewall module if one exists.
  lifecycle {
    precondition {
      condition     = var.firewall_serialisation_sentinel != null
      error_message = "firewall_serialisation_sentinel must be provided (empty string is fine when firewall disabled)."
    }
  }
}
