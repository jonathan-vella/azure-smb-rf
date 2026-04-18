// Hub networking — VNet via AVM-TF
// (Azure/avm-res-network-virtualnetwork/azurerm) + hand-rolled NSG,
// Private DNS Zone, PDZ VNet link and NSG diagnostics (AVM covers VNet diag +
// subnets + NSG/RT associations via subnet args).

locals {
  hub_prefix          = tonumber(split("/", var.address_space)[1])
  vnet_name           = "vnet-hub-smb-${var.region_short}"
  nsg_name            = "nsg-hub-smb-${var.region_short}"
  shared_pdz_name     = "privatelink.azure.com"
  afw_subnet_cidr     = cidrsubnet(var.address_space, 26 - local.hub_prefix, 0)
  afwmgmt_subnet_cidr = cidrsubnet(var.address_space, 26 - local.hub_prefix, 1)
  mgmt_subnet_cidr    = cidrsubnet(var.address_space, 26 - local.hub_prefix, 2)
  gw_subnet_cidr      = cidrsubnet(var.address_space, 27 - local.hub_prefix, 6)
}

resource "azurerm_network_security_group" "hub" {
  name                = local.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Default deny all inbound traffic"
  }
}

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  name          = local.vnet_name
  location      = var.location
  parent_id     = var.resource_group_id
  tags          = var.tags
  address_space = [var.address_space]

  subnets = {
    afw = {
      name             = "AzureFirewallSubnet"
      address_prefixes = [local.afw_subnet_cidr]
    }
    afw_mgmt = {
      name             = "AzureFirewallManagementSubnet"
      address_prefixes = [local.afwmgmt_subnet_cidr]
    }
    gateway = {
      name             = "GatewaySubnet"
      address_prefixes = [local.gw_subnet_cidr]
    }
    management = {
      name             = "snet-management"
      address_prefixes = [local.mgmt_subnet_cidr]
      network_security_group = {
        id = azurerm_network_security_group.hub.id
      }
    }
  }

  diagnostic_settings = {
    law = {
      name                  = "vnet-diag-law"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = []
      metric_categories     = ["AllMetrics"]
    }
  }

  enable_telemetry = false
}

resource "azurerm_private_dns_zone" "shared" {
  name                = local.shared_pdz_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_hub" {
  name                  = "link-${local.vnet_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.shared.name
  virtual_network_id    = module.vnet.resource_id
  registration_enabled  = true
  tags                  = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  name                       = "nsg-diag-law"
  target_resource_id         = azurerm_network_security_group.hub.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}

