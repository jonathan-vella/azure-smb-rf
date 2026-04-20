// ============================================================================
// SMB Ready Foundation — Terraform Version & Provider Constraints
// ============================================================================
// Mirrors Bicep project at infra/bicep/smb-ready-foundation/.
// Keep provider pins in sync with .github/skills/terraform-patterns/SKILL.md
// and AGENTS.md (azurerm ~> 4.0).
// ============================================================================

terraform {
  # 1.12+ required: earlier versions fail `terraform validate` on the
  # AVM recovery-services-vault module due to lack of short-circuit
  # evaluation in variable validation conditions.
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    # azapi is required for Azure Migrate (no AVM-TF module exists for
    # Microsoft.Migrate/assessmentProjects). See Phase 4 row for migrate.bicep.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    # terraform_data (builtin) — used for module ordering relays where
    # conditional modules have unknown count at plan time (Phase 3f).
  }
}
