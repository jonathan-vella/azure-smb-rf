output "route_table_id" {
  description = "Spoke route table ID (null when disabled)."
  value       = var.enabled ? azurerm_route_table.spoke[0].id : null
}
