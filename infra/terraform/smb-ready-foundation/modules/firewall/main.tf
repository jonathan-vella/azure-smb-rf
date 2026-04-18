// Azure Firewall Basic (conditional via var.enabled).

locals {
  fw_name         = "fw-hub-smb-${var.region_short}"
  fw_policy_name  = "fwpol-hub-smb-${var.region_short}"
  fw_pip_data     = "pip-fw-smb-${var.region_short}"
  fw_pip_mgmt     = "pip-fw-mgmt-smb-${var.region_short}"
  has_on_premises = length(var.on_premises_address_space) > 0
  fw_zones        = ["1", "2", "3"]
}

resource "azurerm_public_ip" "data" {
  count = var.enabled ? 1 : 0

  name                = local.fw_pip_data
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  zones               = local.fw_zones
}

resource "azurerm_public_ip" "mgmt" {
  count = var.enabled ? 1 : 0

  name                = local.fw_pip_mgmt
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  zones               = local.fw_zones
}

resource "azurerm_firewall_policy" "hub" {
  count = var.enabled ? 1 : 0

  name                     = local.fw_policy_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  tags                     = var.tags
  sku                      = "Basic"
  threat_intelligence_mode = "Alert"
}

resource "azurerm_firewall_policy_rule_collection_group" "network" {
  count = var.enabled ? 1 : 0

  name               = "NetworkRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.hub[0].id
  priority           = 200

  network_rule_collection {
    name     = "AllowInfrastructure"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "AllowDNS"
      description           = "Allow DNS queries to Azure DNS"
      protocols             = ["UDP", "TCP"]
      source_addresses      = [var.spoke_vnet_address_space]
      destination_addresses = ["168.63.129.16"]
      destination_ports     = ["53"]
    }

    rule {
      name                  = "AllowNTP"
      description           = "Allow NTP for time synchronization"
      protocols             = ["UDP"]
      source_addresses      = [var.spoke_vnet_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }

    rule {
      name                  = "AllowICMP"
      description           = "Allow all ICMP traffic for diagnostics"
      protocols             = ["ICMP"]
      source_addresses      = [var.spoke_vnet_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    }

    rule {
      name                  = "AllowOutboundHTTP"
      description           = "Allow outbound HTTP traffic"
      protocols             = ["TCP"]
      source_addresses      = [var.spoke_vnet_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["80"]
    }

    rule {
      name                  = "AllowOutboundHTTPS"
      description           = "Allow outbound HTTPS traffic"
      protocols             = ["TCP"]
      source_addresses      = [var.spoke_vnet_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["443"]
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "on_premises" {
  count = var.enabled && local.has_on_premises ? 1 : 0

  name               = "OnPremisesRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.hub[0].id
  priority           = 300

  network_rule_collection {
    name     = "AllowOnPremisesTraffic"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "AllowAzureToOnPrem"
      description           = "Allow Azure spoke resources to reach on-premises"
      protocols             = ["Any"]
      source_addresses      = [var.spoke_vnet_address_space]
      destination_addresses = [var.on_premises_address_space]
      destination_ports     = ["*"]
    }

    rule {
      name                  = "AllowOnPremToAzure"
      description           = "Allow on-premises to reach Azure spoke resources"
      protocols             = ["Any"]
      source_addresses      = [var.on_premises_address_space]
      destination_addresses = [var.spoke_vnet_address_space]
      destination_ports     = ["*"]
    }
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.network]
}

module "fw" {
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "0.4.0"

  count = var.enabled ? 1 : 0

  name                = local.fw_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  firewall_sku_name  = "AZFW_VNet"
  firewall_sku_tier  = "Basic"
  firewall_zones     = local.fw_zones
  firewall_policy_id = azurerm_firewall_policy.hub[0].id

  firewall_ip_configuration = [
    {
      name                 = "ipconfig"
      subnet_id            = var.afw_subnet_id
      public_ip_address_id = azurerm_public_ip.data[0].id
    }
  ]

  firewall_management_ip_configuration = {
    name                 = "mgmtipconfig"
    subnet_id            = var.afw_mgmt_subnet_id
    public_ip_address_id = azurerm_public_ip.mgmt[0].id
  }

  diagnostic_settings = {
    law = {
      name                  = "afw-diag-law"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  }

  enable_telemetry = false

  depends_on = [
    azurerm_firewall_policy_rule_collection_group.network,
    azurerm_firewall_policy_rule_collection_group.on_premises,
  ]
}

