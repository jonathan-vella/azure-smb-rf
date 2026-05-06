output "route_table_id" {
  description = "Spoke route table ID (null when disabled)."
  value       = var.enabled ? azurerm_route_table.spoke[0].id : null
}

output "gateway_route_table_id" {
  description = "Gateway route table ID (empty unless route_hybrid_through_firewall=true and on-prem CIDR set)."
  value       = local.attach_gateway_rt ? azurerm_route_table.gateway[0].id : ""
}
