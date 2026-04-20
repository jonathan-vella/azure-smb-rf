// ============================================================================
// SMB Ready Foundation — Root composition
// ============================================================================
// Each domain lives under ./modules/<name>/. This file wires them together.
// Deployment order is enforced by variable references between modules;
// explicit depends_on / sentinels are used where the dependency is not
// visible to Terraform's graph (VPN gateway serialisation with firewall,
// peering gating on VPN gateway creation).
// ============================================================================

module "management_group" {
  source = "./modules/management-group"

  name            = var.management_group_name
  display_name    = var.management_group_display_name
  subscription_id = var.subscription_id
}

# Import block lives in the root (import blocks are not allowed in child
# modules). The target addresses the resource inside the module so Terraform
# adopts a pre-existing MG instead of failing with "already exists".
import {
  to = module.management_group.azurerm_management_group.smb_rf
  id = "/providers/Microsoft.Management/managementGroups/${var.management_group_name}"
}

module "policy_assignments_mg" {
  source = "./modules/policy-assignments-mg"

  management_group_id = module.management_group.id
  assignment_location = var.assignment_location
  allowed_vm_skus     = var.allowed_vm_skus
  allowed_locations   = var.allowed_locations
}

module "resource_groups" {
  source = "./modules/resource-groups"

  location             = var.location
  rg_names             = local.rg_names
  shared_services_tags = local.shared_services_tags
  spoke_tags           = local.spoke_tags
}

module "defender" {
  source = "./modules/defender"
}

module "budget" {
  source = "./modules/budget"

  subscription_resource_id = data.azurerm_subscription.current.id
  amount                   = var.budget_amount
  alert_email              = local.effective_budget_alert_email
  start_date               = var.budget_start_date
}

module "network_hub" {
  source = "./modules/network-hub"

  location                   = var.location
  resource_group_name        = module.resource_groups.shared["hub"].name
  resource_group_id          = module.resource_groups.shared["hub"].id
  region_short               = local.region_short
  address_space              = var.hub_vnet_address_space
  tags                       = local.shared_services_tags
  log_analytics_workspace_id = module.monitoring.workspace_id
}

module "network_spoke" {
  source = "./modules/network-spoke"

  location                   = var.location
  resource_group_name        = module.resource_groups.spoke.name
  resource_group_id          = module.resource_groups.spoke.id
  region_short               = local.region_short
  environment                = var.environment
  address_space              = var.spoke_vnet_address_space
  tags                       = local.spoke_tags
  deploy_nat_gateway         = local.deploy_spoke_nat_gateway
  log_analytics_workspace_id = module.monitoring.workspace_id
  route_table_id             = module.route_tables.route_table_id
}

module "firewall" {
  source = "./modules/firewall"

  enabled                    = var.deploy_firewall
  location                   = var.location
  resource_group_name        = module.resource_groups.shared["hub"].name
  region_short               = local.region_short
  tags                       = local.shared_services_tags
  afw_subnet_id              = module.network_hub.afw_subnet_id
  afw_mgmt_subnet_id         = module.network_hub.afw_mgmt_subnet_id
  spoke_vnet_address_space   = var.spoke_vnet_address_space
  on_premises_address_space  = var.on_premises_address_space
  log_analytics_workspace_id = module.monitoring.workspace_id
}

module "route_tables" {
  source = "./modules/route-tables"

  enabled                   = var.deploy_firewall
  location                  = var.location
  resource_group_name       = module.resource_groups.shared["hub"].name
  region_short              = local.region_short
  tags                      = local.shared_services_tags
  firewall_private_ip       = module.firewall.private_ip
  spoke_vnet_address_space  = var.spoke_vnet_address_space
  on_premises_address_space = var.on_premises_address_space
}

module "vpn_gateway" {
  source = "./modules/vpn-gateway"

  enabled                         = var.deploy_vpn
  location                        = var.location
  resource_group_name             = module.resource_groups.shared["hub"].name
  region_short                    = local.region_short
  tags                            = local.shared_services_tags
  gateway_subnet_id               = module.network_hub.gateway_subnet_id
  firewall_serialisation_sentinel = module.firewall.id
}

module "peering" {
  source = "./modules/peering"

  enabled                   = local.deploy_peering
  deploy_vpn                = var.deploy_vpn
  hub_resource_group_name   = module.resource_groups.shared["hub"].name
  spoke_resource_group_name = module.resource_groups.spoke.name
  hub_vnet_name             = module.network_hub.vnet_name
  spoke_vnet_name           = module.network_spoke.vnet_name
  hub_vnet_id               = module.network_hub.vnet_id
  spoke_vnet_id             = module.network_spoke.vnet_id
  vpn_gateway_id            = module.vpn_gateway.id
}

module "monitoring" {
  source = "./modules/monitoring"

  location            = var.location
  resource_group_name = module.resource_groups.shared["monitor"].name
  region_short        = local.region_short
  tags                = local.shared_services_tags
  daily_cap_gb        = var.log_analytics_daily_cap_gb
}

module "backup" {
  source = "./modules/backup"

  location                   = var.location
  resource_group_name        = module.resource_groups.shared["backup"].name
  region_short               = local.region_short
  tags                       = local.shared_services_tags
  log_analytics_workspace_id = module.monitoring.workspace_id
}

module "policy_backup_auto" {
  source = "./modules/policy-backup-auto"

  location                 = var.location
  subscription_resource_id = data.azurerm_subscription.current.id
  default_vm_policy_id     = module.backup.default_vm_policy_id
}

module "migrate" {
  source = "./modules/migrate"

  location          = var.location
  region_short      = local.region_short
  resource_group_id = module.resource_groups.shared["migrate"].id
  tags              = local.shared_services_tags
}

module "keyvault" {
  source = "./modules/keyvault"

  location                   = var.location
  resource_group_name        = module.resource_groups.shared["security"].name
  region_short               = local.region_short
  tags                       = local.shared_services_tags
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  unique_suffix              = local.unique_suffix
  pep_subnet_id              = module.network_spoke.pep_subnet_id
  log_analytics_workspace_id = module.monitoring.workspace_id
}

module "automation" {
  source = "./modules/automation"

  location                   = var.location
  resource_group_name        = module.resource_groups.shared["monitor"].name
  region_short               = local.region_short
  tags                       = local.shared_services_tags
  log_analytics_workspace_id = module.monitoring.workspace_id
}
