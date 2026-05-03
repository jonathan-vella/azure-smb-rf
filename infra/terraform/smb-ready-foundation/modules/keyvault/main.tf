// Key Vault — AVM-TF module (Azure/avm-res-keyvault-vault/azurerm).
// AVM handles: key vault + private endpoint + diagnostic settings.
// We keep the private DNS zone hand-rolled (AVM does not manage PDZ itself).

locals {
  # Abbreviate 'staging' to 'stg' so the 24-char Key Vault name budget isn't
  # blown by the environment segment alone.
  env_short = var.environment == "staging" ? "stg" : var.environment

  # Key Vault names are globally unique and capped at 24 characters. Including
  # the environment ensures dev/staging/prod each get a distinct vault (and
  # therefore distinct private endpoints in their own spoke subnets). substr
  # guards against the 24-char ceiling as defence-in-depth.
  kv_name  = substr("kv-${local.env_short}-${var.region_short}-${var.unique_suffix}", 0, 24)
  pep_name = "pep-kv-${local.env_short}-${var.region_short}"
  pdz_name = "privatelink.vaultcore.azure.net"
}

resource "azurerm_private_dns_zone" "kv" {
  name                = local.pdz_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Without these links, clients in the spoke (and on-prem via the hub)
# resolve `*.vaultcore.azure.net` to the public name and fail because
# public_network_access_enabled is false.
resource "azurerm_private_dns_zone_virtual_network_link" "kv_spoke" {
  name                  = "link-spoke"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = var.spoke_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_hub" {
  count                 = var.hub_vnet_id == null ? 0 : 1
  name                  = "link-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = var.hub_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

module "kv" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  name                = local.kv_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  tags                = var.tags

  sku_name                      = "standard"
  soft_delete_retention_days    = 90
  purge_protection_enabled      = true
  public_network_access_enabled = false

  # AVM defaults legacy_access_policies_enabled=false => RBAC authorisation
  # is enforced by the module.

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  private_endpoints = {
    vault = {
      name                            = local.pep_name
      subnet_resource_id              = var.pep_subnet_id
      subresource_name                = "vault"
      private_service_connection_name = "psc-${local.kv_name}"
      private_dns_zone_resource_ids   = [azurerm_private_dns_zone.kv.id]
      tags                            = var.tags
    }
  }

  diagnostic_settings = {
    law = {
      name                  = "kv-diag-law"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  }

  enable_telemetry = false
}
