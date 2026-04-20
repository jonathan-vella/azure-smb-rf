// Hub-spoke peering — conditional on firewall OR vpn.
// vpn_gateway_id sentinel carries the gateway id (or empty string) to gate
// peering apply on VPN gateway creation without unknown-count-at-plan issues.

resource "terraform_data" "vpn_ready" {
  triggers_replace = length(var.vpn_gateway_id) > 0 ? [var.vpn_gateway_id] : []
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count = var.enabled ? 1 : 0

  name                      = "peer-hub-to-spoke"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = var.spoke_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.deploy_vpn
  use_remote_gateways          = false

  depends_on = [terraform_data.vpn_ready]
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count = var.enabled ? 1 : 0

  name                      = "peer-spoke-to-hub"
  resource_group_name       = var.spoke_resource_group_name
  virtual_network_name      = var.spoke_vnet_name
  remote_virtual_network_id = var.hub_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.deploy_vpn

  depends_on = [
    azurerm_virtual_network_peering.hub_to_spoke,
    terraform_data.vpn_ready,
  ]
}
