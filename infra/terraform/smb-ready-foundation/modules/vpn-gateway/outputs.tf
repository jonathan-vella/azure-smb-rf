output "id" {
  value = var.enabled ? azurerm_virtual_network_gateway.vpn[0].id : ""
}

output "public_ip" {
  description = "VPN gateway public IP address (empty when disabled)."
  value       = var.enabled ? azurerm_public_ip.vpn[0].ip_address : ""
}

output "local_network_gateway_id" {
  description = "Local Network Gateway ID (empty when VPN disabled)."
  value       = var.enabled ? azurerm_local_network_gateway.onprem[0].id : ""
}
