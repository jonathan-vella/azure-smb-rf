// ============================================================================
// Plan-mode Terraform tests for smb-ready-foundation
// ============================================================================
// Scenario matrix covers the 4 feature-flag combinations plus scenario-specific
// behaviour (NAT vs firewall, peering gating, budget email fallback).
// Providers are mocked so tests run without Azure auth.
// ============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "00000000-0000-0000-0000-000000000000"
      client_id       = "22222222-2222-2222-2222-222222222222"
      object_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
  mock_data "azurerm_subscription" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000000"
      subscription_id = "00000000-0000-0000-0000-000000000000"
      display_name    = "mock"
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      state           = "Enabled"
    }
  }

  # Override the MG resource so the `import` block doesn't try to call a
  # real provider during tests.
  override_resource {
    target = module.management_group.azurerm_management_group.smb_rf
    values = {
      id   = "/providers/Microsoft.Management/managementGroups/smb-rf"
      name = "smb-rf"
    }
  }
}
mock_provider "azapi" {}

variables {
  subscription_id           = "00000000-0000-0000-0000-000000000000"
  location                  = "swedencentral"
  environment               = "prod"
  owner                     = "test@example.com"
  hub_vnet_address_space    = "10.0.0.0/23"
  spoke_vnet_address_space  = "10.0.2.0/23"
  on_premises_address_space = ""
  budget_start_date         = "2026-01-01"
  budget_amount             = 100
  budget_alert_email        = ""
}

# --- baseline: no firewall, no VPN --------------------------------------------
run "baseline_scenario" {
  command = plan

  variables {
    deploy_firewall = false
    deploy_vpn      = false
  }

  assert {
    condition     = local.scenario == "baseline"
    error_message = "baseline scenario should resolve to 'baseline'"
  }

  assert {
    condition     = local.deploy_spoke_nat_gateway == true
    error_message = "baseline should deploy spoke NAT gateway"
  }

  assert {
    condition     = local.deploy_peering == false
    error_message = "baseline should not deploy hub-spoke peering"
  }
}

# --- firewall: firewall only --------------------------------------------------
run "firewall_scenario" {
  command = plan

  variables {
    deploy_firewall = true
    deploy_vpn      = false
  }

  assert {
    condition     = local.scenario == "firewall"
    error_message = "firewall-only should resolve scenario to 'firewall'"
  }

  assert {
    condition     = local.deploy_spoke_nat_gateway == false
    error_message = "NAT gateway must NOT deploy when firewall is on (mutually exclusive)"
  }

  assert {
    condition     = local.deploy_peering == true
    error_message = "firewall scenario must enable peering"
  }
}

# --- vpn: VPN only ------------------------------------------------------------
run "vpn_scenario" {
  command = plan

  variables {
    deploy_firewall           = false
    deploy_vpn                = true
    on_premises_address_space = "192.168.0.0/16"
  }

  assert {
    condition     = local.scenario == "vpn"
    error_message = "vpn-only should resolve scenario to 'vpn'"
  }

  assert {
    condition     = local.deploy_peering == true
    error_message = "vpn scenario must enable peering"
  }
}

# --- full: firewall + VPN -----------------------------------------------------
run "full_scenario" {
  command = plan

  variables {
    deploy_firewall           = true
    deploy_vpn                = true
    on_premises_address_space = "192.168.0.0/16"
  }

  assert {
    condition     = local.scenario == "full"
    error_message = "firewall+vpn should resolve scenario to 'full'"
  }

  assert {
    condition     = local.deploy_spoke_nat_gateway == false
    error_message = "NAT gateway must NOT deploy in full scenario"
  }
}

# --- defaults: budget email falls back to owner ------------------------------
run "budget_email_defaults_to_owner" {
  command = plan

  variables {
    deploy_firewall = false
    deploy_vpn      = false
  }

  assert {
    condition     = local.effective_budget_alert_email == "test@example.com"
    error_message = "budget_alert_email should default to owner when blank"
  }
}

# --- rg names follow CAF pattern ---------------------------------------------
run "rg_names_match_caf" {
  command = plan

  variables {
    deploy_firewall = false
    deploy_vpn      = false
  }

  assert {
    condition     = local.rg_names.hub == "rg-hub-smb-swc"
    error_message = "hub rg must use shared 'smb' environment + swc region short"
  }

  assert {
    condition     = local.rg_names.spoke == "rg-spoke-prod-swc"
    error_message = "spoke rg must use env-specific environment + swc region short"
  }
}
