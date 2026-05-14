// VPN Gateway VpnGw1AZ (conditional via var.enabled).
// firewall_depends_on carries the firewall id (or "") so Terraform serialises
// on the hub VNet even with no explicit resource reference.

locals {
  gw_name  = "vpng-hub-smb-${var.region_short}"
  pip_name = "pip-vpn-smb-${var.region_short}"
  lng_name = "lng-onprem-smb-${var.region_short}"

  # Deterministic, globally-unique DNS label so the auto-generated FQDN
  # (<label>.<region>.cloudapp.azure.com) does not collide with prior
  # reservations. Mirrors the Bicep module which uses uniqueString(rg.id).
  # 13-char hex suffix matches Bicep's uniqueString length.
  pip_dns_label = "${local.pip_name}-${substr(sha1("${var.resource_group_name}/${local.pip_name}"), 0, 13)}"

  # Mirror Bicep: always create the LNG when VPN is enabled, falling back
  # to RFC 5737 placeholders when partner has not provided real values.
  # This lets the LNG be provisioned in `vpn` scenario and updated later.
  effective_onprem_cidr  = length(var.on_premises_address_space) > 0 ? var.on_premises_address_space : "192.0.2.0/24"
  effective_onprem_gw_ip = length(var.on_premises_gateway_public_ip) > 0 ? var.on_premises_gateway_public_ip : "192.0.2.1"
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
  domain_name_label   = local.pip_dns_label
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

# Local Network Gateway — mirrors Bicep: always created when VPN is enabled,
# uses RFC 5737 placeholders when on-prem details are not yet known. The
# IPsec connection is intentionally NOT created (manual partner step).
resource "azurerm_local_network_gateway" "onprem" {
  count = var.enabled ? 1 : 0

  name                = local.lng_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  gateway_address = local.effective_onprem_gw_ip
  address_space   = [local.effective_onprem_cidr]
}
