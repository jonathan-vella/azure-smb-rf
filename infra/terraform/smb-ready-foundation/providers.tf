// ============================================================================
// Provider configuration
// ============================================================================

provider "azurerm" {
  features {
    key_vault {
      # Match Bicep module keyvault.bicep — retains soft-deleted vaults so
      // purge_protection_enabled behaviour is deterministic across flavours.
      purge_soft_delete_on_destroy          = false
      purge_soft_deleted_keys_on_destroy    = false
      purge_soft_deleted_secrets_on_destroy = false
      recover_soft_deleted_key_vaults       = true
    }

    resource_group {
      # Fail fast rather than silently orphan resources in an RG destroy.
      prevent_deletion_if_contains_resources = true
    }

    log_analytics_workspace {
      # Mirror Bicep default so re-deploys after azd down can reuse names.
      permanently_delete_on_destroy = true
    }
  }

  # azurerm 4.x requires subscription_id to be set explicitly. azd auto-exports
  # ARM_SUBSCRIPTION_ID; the preprovision hook also exports TF_VAR_subscription_id
  # as a defence-in-depth bridge for non-azd workflows.
  subscription_id = var.subscription_id
}

provider "azapi" {
  # Inherits auth from azurerm/ARM_* env vars set by azd.
}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}
