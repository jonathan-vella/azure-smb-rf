output "id" {
  description = "Firewall resource ID (empty when disabled)."
  value       = var.enabled ? module.fw[0].resource_id : ""
}

output "private_ip" {
  description = "Private IP of the firewall data interface (empty when disabled)."
  value       = var.enabled ? module.fw[0].resource.ip_configuration[0].private_ip_address : ""
}
