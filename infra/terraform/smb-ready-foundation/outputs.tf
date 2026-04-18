// Root outputs — wired to module outputs.

output "deployment_scenario" {
  description = "Scenario derived from deploy_firewall / deploy_vpn booleans."
  value       = local.scenario
}

output "feature_flags" {
  description = "Feature flags derived from scenario."
  value = {
    firewall    = var.deploy_firewall
    vpn_gateway = var.deploy_vpn
    nat_gateway = local.deploy_spoke_nat_gateway
    peering     = local.deploy_peering
  }
}

output "resource_group_names" {
  description = "Resource group names map."
  value       = local.rg_names
}

output "unique_suffix" {
  description = "Deterministic suffix used for globally-unique names (hash of subscription id)."
  value       = local.unique_suffix
}

output "management_group_id" {
  description = "Resource ID of the smb-rf management group."
  value       = module.management_group.id
}

output "management_group_name" {
  description = "Name (id) of the management group."
  value       = module.management_group.name
}

output "policy_assignment_count" {
  description = "Total number of MG-scoped policy assignments created (always 1 — the smb-baseline initiative)."
  value       = module.policy_assignments_mg.assignment_count
}

output "initiative_policy_count" {
  description = "Number of policy definitions contained within the smb-baseline initiative."
  value       = module.policy_assignments_mg.initiative_policy_count
}

output "hub_vnet_id" {
  description = "Hub virtual network resource ID."
  value       = module.network_hub.vnet_id
}

output "spoke_vnet_id" {
  description = "Spoke virtual network resource ID."
  value       = module.network_spoke.vnet_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID."
  value       = module.monitoring.workspace_id
}

output "recovery_services_vault_id" {
  description = "Recovery Services Vault resource ID."
  value       = module.backup.vault_id
}

output "migrate_project_id" {
  description = "Azure Migrate project resource ID."
  value       = module.migrate.project_id
}

output "nat_gateway_name" {
  description = "NAT Gateway name (empty when firewall is deployed)."
  value       = module.network_spoke.nat_gateway_name
}

output "firewall_private_ip" {
  description = "Private IP of the Azure Firewall data interface (empty when firewall disabled)."
  value       = module.firewall.private_ip
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN gateway (empty when VPN disabled)."
  value       = module.vpn_gateway.public_ip
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = module.keyvault.name
}

output "key_vault_uri" {
  description = "Key Vault DNS URI."
  value       = module.keyvault.uri
}

output "automation_account_name" {
  description = "Automation Account name."
  value       = module.automation.name
}
