output "vnet_id" {
  value = module.vnet.resource_id
}

output "vnet_name" {
  value = module.vnet.name
}

output "afw_subnet_id" {
  value = module.vnet.subnets["afw"].resource_id
}

output "afw_mgmt_subnet_id" {
  value = module.vnet.subnets["afw_mgmt"].resource_id
}

output "gateway_subnet_id" {
  value = module.vnet.subnets["gateway"].resource_id
}

output "gateway_subnet_address_prefix" {
  description = "GatewaySubnet CIDR (re-emitted for the route-tables module's azapi PATCH which must include addressPrefix)."
  value       = local.gw_subnet_cidr
}

output "management_subnet_id" {
  value = module.vnet.subnets["management"].resource_id
}

output "shared_private_dns_zone_id" {
  value = azurerm_private_dns_zone.shared.id
}
