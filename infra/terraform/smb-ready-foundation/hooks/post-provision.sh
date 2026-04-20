#!/usr/bin/env bash
# =============================================================================
# SMB Ready Foundation — Terraform post-provision hook
# =============================================================================
# Runs after `azd provision` (whether Terraform apply succeeded or failed).
# Prints deployment summary + next-steps guidance. Non-blocking on failure so
# partners can inspect the terraform output above.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./_lib.sh
. "$SCRIPT_DIR/_lib.sh"

SCENARIO="${SCENARIO:-baseline}"
AZURE_LOCATION="${AZURE_LOCATION:-swedencentral}"
eval "$(resolve_scenario_flags "$SCENARIO")"

printf '\n========================================\n'
printf '  SMB Ready Foundation (Terraform) — Post-Provision\n'
printf '  Scenario: %s\n' "$SCENARIO"
printf '========================================\n\n'

# ---- Verify core resources ---------------------------------------------------
log_step 1 'Checking deployment result'

REGION_SHORT='swc'
[[ "$AZURE_LOCATION" == 'germanywestcentral' ]] && REGION_SHORT='gwc'
HUB_RG="rg-hub-smb-$REGION_SHORT"

if ! az group exists --name "$HUB_RG" 2>/dev/null | grep -q true; then
  log_substep "Hub resource group $HUB_RG not found — provision may have failed"
  printf '\n  To retry: azd provision\n\n'
  exit 0  # don't block; user inspects terraform output.
fi
log_substep 'Core resource groups present'

# ---- Terraform outputs -------------------------------------------------------
log_step 2 'Retrieving Terraform outputs'
if cd "$IAC_DIR" 2>/dev/null; then
  if terraform output -json >/tmp/smbrf-tf-outputs.json 2>/dev/null; then
    SCENARIO_OUT="$(jq -r '.deployment_scenario.value // "?"' /tmp/smbrf-tf-outputs.json)"
    POLICY_COUNT="$(jq -r '.policy_assignment_count.value // "?"' /tmp/smbrf-tf-outputs.json)"
    KV_NAME="$(jq -r '.key_vault_name.value // "?"' /tmp/smbrf-tf-outputs.json)"
    LAW_ID="$(jq -r '.log_analytics_workspace_id.value // "?"' /tmp/smbrf-tf-outputs.json)"
    log_substep "scenario:    $SCENARIO_OUT"
    log_substep "policies:    $POLICY_COUNT"
    log_substep "key vault:   $KV_NAME"
    log_substep "law:         ${LAW_ID##*/}"
  else
    log_substep '(outputs unavailable — state may not be initialized)'
  fi
fi

# ---- Summary -----------------------------------------------------------------
log_step 3 'Deployment summary'
case "$SCENARIO" in
  baseline) COST='~$48/mo'  ;;
  firewall) COST='~$336/mo' ;;
  vpn)      COST='~$187/mo' ;;
  full)     COST='~$476/mo' ;;
  *)        COST='(unknown)' ;;
esac

FEATURES=''
[[ "$DEPLOY_FIREWALL" == 'true' ]] && FEATURES+='Azure Firewall, '
[[ "$DEPLOY_VPN"      == 'true' ]] && FEATURES+='VPN Gateway, '
[[ "$DEPLOY_FIREWALL" != 'true' ]] && FEATURES+='NAT Gateway, '
FEATURES+='Log Analytics, Recovery Vault, Key Vault, Automation Account'

printf '\n  Scenario:   %s (%s)\n'  "$SCENARIO" "$COST"
printf '  Region:     %s\n'        "$AZURE_LOCATION"
printf '  Features:   %s\n\n'      "$FEATURES"

# ---- Next steps --------------------------------------------------------------
log_step 4 'Next steps'
printf '  1. Review deployed resources in the Azure Portal\n'
printf '  2. Configure Azure Migrate to discover on-premises servers\n'
if [[ "$DEPLOY_VPN" == 'true' ]]; then
  printf '  3. Configure VPN local network gateway with on-premises details\n'
  printf '  4. Establish site-to-site VPN connection\n'
fi
printf '\n  Teardown:   ./scripts/remove-smb-ready-foundation.sh\n'
printf '  Redeploy:   azd provision\n\n'
