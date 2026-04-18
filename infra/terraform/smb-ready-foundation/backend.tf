// ============================================================================
// Backend configuration (partial)
// ============================================================================
// Values are supplied at init time via `-backend-config=...` by the
// preprovision hook:
//   * TF_BACKEND=azurerm (default) — hook writes backend.hcl with SA/container/key
//   * TF_BACKEND=local             — hook passes `-backend-config=path=terraform.tfstate`
//
// State key for this root: smb-ready-foundation.tfstate (shared across azd envs —
//   MG + sub-scope resources persist; teardown only removes RGs)
// State key for MG root:   smb-ready-foundation-mg.tfstate (see sibling directory)
// ============================================================================

terraform {
  backend "azurerm" {}
}
