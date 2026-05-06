// ============================================================================
// SMB Ready Foundations — Root composition
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
# modules). Gated by var.adopt_existing_management_group: when true, Terraform
# adopts a pre-existing MG; when false (default), the resource is created
# normally.
import {
  for_each = var.adopt_existing_management_group ? toset(["smb_rf"]) : toset([])
  to       = module.management_group.azurerm_management_group.smb_rf
  id       = "/providers/Microsoft.Management/managementGroups/${var.management_group_name}"
}

# When adopting an existing MG, its policy set definition was almost certainly
# created by a previous deploy too. Import it on the same flag.
import {
  for_each = var.adopt_existing_management_group ? toset(["smb-baseline"]) : toset([])
  to       = module.policy_assignments_mg.azurerm_management_group_policy_set_definition.smb_baseline
  id       = "/providers/Microsoft.Management/managementGroups/${var.management_group_name}/providers/Microsoft.Authorization/policySetDefinitions/smb-baseline"
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

# Defender pricing resources always pre-exist on every Azure subscription
# (the Free/Standard tier setting is a singleton per plan), so import them
# unconditionally to bring them under Terraform management without conflict.
import {
  for_each = toset(["VirtualMachines", "StorageAccounts", "KeyVaults", "Arm"])
  to       = module.defender.azurerm_security_center_subscription_pricing.free[each.key]
  id       = "/subscriptions/${var.subscription_id}/providers/Microsoft.Security/pricings/${each.key}"
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

  enabled                       = var.deploy_firewall
  location                      = var.location
  resource_group_name           = module.resource_groups.shared["hub"].name
  region_short                  = local.region_short
  tags                          = local.shared_services_tags
  firewall_private_ip           = module.firewall.private_ip
  spoke_vnet_address_space      = var.spoke_vnet_address_space
  on_premises_address_space     = var.on_premises_address_space
  route_hybrid_through_firewall = var.route_hybrid_through_firewall
  hub_vnet_id                   = module.network_hub.vnet_id
  hub_vnet_name                 = module.network_hub.vnet_name
  gateway_subnet_address_prefix = module.network_hub.gateway_subnet_address_prefix
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
  on_premises_address_space       = var.on_premises_address_space
  on_premises_gateway_public_ip   = var.on_premises_gateway_public_ip
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

# Adopt subscription-scoped resources that were created by a prior partial
# apply (and whose state was subsequently lost, e.g. backend re-bootstrap).
# Gated by var.adopt_existing_subscription_resources so fresh-subscription
# deploys don't try to import non-existent IDs. Pre-provision hooks detect
# the policy assignment via `az policy assignment show` and set the flag.
import {
  for_each = var.adopt_existing_subscription_resources ? toset(["smb-backup-02"]) : toset([])
  to       = module.policy_backup_auto.azurerm_subscription_policy_assignment.backup_auto
  id       = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/policyAssignments/smb-backup-02"
}

# AVM diagnostic setting on the Automation Account. The Azure resource ID for
# diagnostic settings uses the `<target>|<name>` form. Same flag — when the
# AA already exists, its `aa-diag-law` setting was created with it.
import {
  for_each = var.adopt_existing_subscription_resources ? toset(["law"]) : toset([])
  to       = module.automation.module.aa.azurerm_monitor_diagnostic_setting.this["law"]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.rg_names.monitor}/providers/Microsoft.Automation/automationAccounts/aa-smbrf-smb-${local.region_short}|aa-diag-law"
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
  environment                = var.environment
  tags                       = local.shared_services_tags
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  unique_suffix              = local.unique_suffix
  pep_subnet_id              = module.network_spoke.pep_subnet_id
  spoke_vnet_id              = module.network_spoke.vnet_id
  hub_vnet_id                = module.network_hub.vnet_id
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
