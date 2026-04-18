output "vnet_id" {
  value = module.vnet.resource_id
}

output "vnet_name" {
  value = module.vnet.name
}

output "workload_subnet_id" {
  value = module.vnet.subnets["workload"].resource_id
}

output "data_subnet_id" {
  value = module.vnet.subnets["data"].resource_id
}

output "app_subnet_id" {
  value = module.vnet.subnets["app"].resource_id
}

output "pep_subnet_id" {
  value = module.vnet.subnets["pep"].resource_id
}

output "workload_subnet_ids" {
  description = "Map of workload/data/app subnet ids for route-table + NAT associations."
  value       = local.workload_subnet_ids
}

output "nat_gateway_name" {
  description = "NAT gateway name (empty when disabled)."
  value       = var.deploy_nat_gateway ? azurerm_nat_gateway.spoke[0].name : ""
}
