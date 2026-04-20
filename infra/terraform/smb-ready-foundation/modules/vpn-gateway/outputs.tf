output "id" {
  value = var.enabled ? azurerm_virtual_network_gateway.vpn[0].id : ""
}

output "public_ip" {
  description = "VPN gateway public IP address (empty when disabled)."
  value       = var.enabled ? azurerm_public_ip.vpn[0].ip_address : ""
}
