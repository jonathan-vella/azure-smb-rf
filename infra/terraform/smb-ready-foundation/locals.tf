// ============================================================================
// Locals
// ============================================================================
// Mirrors the variables block in main.bicep. Any change here must be reviewed
// against the Bicep source for structural parity (resource names, tag keys).
// ============================================================================

locals {
  # Region short codes — match Bicep `regionAbbreviations` exactly.
  region_abbreviations = {
    swedencentral      = "swc"
    germanywestcentral = "gwc"
  }
  region_short = local.region_abbreviations[var.location]

  # ------------------------------------------------------------------
  # Deterministic unique suffix
  # ------------------------------------------------------------------
  # Bicep used `uniqueString(subscription().subscriptionId)` which hashes the
  # subscription id and returns a 13-character string. We reproduce that with
  # substr(sha1(), 0, 13) so globally-unique names (Key Vault, storage) match
  # the Bicep flavour when both target the same subscription.
  #
  # OPERATIONAL CONSTRAINT: If Bicep and TF deployments target the SAME
  # subscription simultaneously, globally-unique names collide. Treat the two
  # IaC flavours as mutually exclusive per subscription. See README.md.
  unique_suffix = substr(sha1(data.azurerm_subscription.current.subscription_id), 0, 13)

  # ------------------------------------------------------------------
  # Scenario-derived flags (read by modules and printed in outputs)
  # ------------------------------------------------------------------
  deploy_peering           = var.deploy_firewall || var.deploy_vpn
  deploy_spoke_nat_gateway = !var.deploy_firewall

  scenario = (
    var.deploy_firewall && var.deploy_vpn ? "full" :
    var.deploy_firewall ? "firewall" :
    var.deploy_vpn ? "vpn" :
    "baseline"
  )

  # ------------------------------------------------------------------
  # Tagging — must match Bicep main.bicep tag maps exactly.
  # Note: ManagedBy = "Terraform" (diverges from Bicep's "Bicep" by design so
  # deployed resources carry accurate provenance).
  # ------------------------------------------------------------------
  shared_services_tags = {
    Environment = "smb"
    Owner       = var.owner
    Project     = "smb-ready-foundation"
    ManagedBy   = "Terraform"
  }

  spoke_tags = {
    Environment = var.environment
    Owner       = var.owner
    Project     = "smb-ready-foundation"
    ManagedBy   = "Terraform"
  }

  # ------------------------------------------------------------------
  # Resource group names — match Bicep `rgNames` map exactly.
  # Shared services always use `smb`; spoke uses the environment.
  # ------------------------------------------------------------------
  rg_names = {
    hub      = "rg-hub-smb-${local.region_short}"
    spoke    = "rg-spoke-${var.environment}-${local.region_short}"
    monitor  = "rg-monitor-smb-${local.region_short}"
    backup   = "rg-backup-smb-${local.region_short}"
    migrate  = "rg-migrate-smb-${local.region_short}"
    security = "rg-security-smb-${local.region_short}"
  }

  # Used by the budget_alert_email default (Bicep assigns owner as default).
  effective_budget_alert_email = length(var.budget_alert_email) > 0 ? var.budget_alert_email : var.owner
}
