// Spoke networking — VNet via AVM-TF
// (Azure/avm-res-network-virtualnetwork/azurerm) + hand-rolled NSG,
// NAT gateway, NAT PIP and NSG diagnostics.
// AVM handles: VNet + subnets + per-subnet NSG/NAT associations + VNet diag.

locals {
  spoke_prefix         = tonumber(split("/", var.address_space)[1])
  vnet_name            = "vnet-spoke-${var.environment}-${var.region_short}"
  nsg_name             = "nsg-spoke-${var.environment}-${var.region_short}"
  nat_name             = "nat-spoke-${var.environment}-${var.region_short}"
  nat_pip_name         = "pip-nat-${var.environment}-${var.region_short}"
  workload_subnet_cidr = cidrsubnet(var.address_space, 25 - local.spoke_prefix, 0)
  data_subnet_cidr     = cidrsubnet(var.address_space, 25 - local.spoke_prefix, 1)
  app_subnet_cidr      = cidrsubnet(var.address_space, 25 - local.spoke_prefix, 2)
  pep_subnet_cidr      = cidrsubnet(var.address_space, 26 - local.spoke_prefix, 6)
}

resource "azurerm_network_security_group" "spoke" {
  name                = local.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow inbound traffic within VNet"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
    description                = "Allow Azure Load Balancer health probes"
  }

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

resource "azurerm_public_ip" "nat" {
  count = var.deploy_nat_gateway ? 1 : 0

  name                = local.nat_pip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "spoke" {
  count = var.deploy_nat_gateway ? 1 : 0

  name                    = local.nat_name
  location                = var.location
  resource_group_name     = var.resource_group_name
  tags                    = var.tags
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
}

resource "azurerm_nat_gateway_public_ip_association" "spoke" {
  count = var.deploy_nat_gateway ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.spoke[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

locals {
  nat_subnet_cfg = var.deploy_nat_gateway ? {
    id = azurerm_nat_gateway.spoke[0].id
  } : null

  workload_nsg = {
    id = azurerm_network_security_group.spoke.id
  }

  workload_route_table = var.route_table_id != null ? {
    id = var.route_table_id
  } : null
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
    workload = {
      name                   = "snet-workload"
      address_prefixes       = [local.workload_subnet_cidr]
      network_security_group = local.workload_nsg
      nat_gateway            = local.nat_subnet_cfg
      route_table            = local.workload_route_table
    }
    data = {
      name                   = "snet-data"
      address_prefixes       = [local.data_subnet_cidr]
      network_security_group = local.workload_nsg
      nat_gateway            = local.nat_subnet_cfg
      route_table            = local.workload_route_table
    }
    app = {
      name                   = "snet-app"
      address_prefixes       = [local.app_subnet_cidr]
      network_security_group = local.workload_nsg
      nat_gateway            = local.nat_subnet_cfg
      route_table            = local.workload_route_table
    }
    pep = {
      name                              = "snet-pep"
      address_prefixes                  = [local.pep_subnet_cidr]
      network_security_group            = local.workload_nsg
      private_endpoint_network_policies = "Disabled"
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

locals {
  workload_subnet_ids = {
    workload = module.vnet.subnets["workload"].resource_id
    data     = module.vnet.subnets["data"].resource_id
    app      = module.vnet.subnets["app"].resource_id
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  name                       = "nsg-diag-law"
  target_resource_id         = azurerm_network_security_group.spoke.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}

