#!/usr/bin/env bash
# ============================================================================
# SMB Ready Foundation (Terraform) — Automated Scenario Test Runner
# ============================================================================
# Parallel to scripts/test-scenarios.sh (Bicep variant).
# Runs: teardown (baseline) → firewall → vpn → full
# Each scenario: configure → deploy → validate → teardown → next
# On deploy success the scenario is always torn down (including the last)
# so the subscription is clean between scenarios. On deploy failure the
# script stops without teardown to preserve state for debugging.
# MG + MG policies persist across scenarios; only RGs + budget torn down via
# `azd down --force --purge` so Terraform state stays in sync with Azure.
# ============================================================================
set -euo pipefail

# Use local state for test runs: each azd env has its own terraform.tfstate
# inside .azure/<env>/, so terraform destroy fully destroys everything
# (including sub/tenant-scope resources) with no cross-run ambiguity.
export TF_BACKEND=local

PROJ_DIR="/workspaces/azure-smb-rf/infra/terraform/smb-ready-foundation"
LOG_FILE="/workspaces/azure-smb-rf/logs/test-scenarios-tf.log"
OWNER="jonathan@lordofthecloud.eu"
LOCATION="swedencentral"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || echo '')}"
HUB_CIDR="10.0.0.0/23"
SPOKE_CIDR="10.0.2.0/23"
ON_PREM_CIDR="192.168.0.0/16"
MG_ID="smb-rf"

# Scenarios to test (baseline already done)
SCENARIOS=("firewall" "vpn" "full")

# Region abbreviation
REGION_ABBR="swc"

# Resource groups that hold TF-managed resources per scenario
RGS=(
  "rg-hub-smb-${REGION_ABBR}"
  "rg-spoke-prod-${REGION_ABBR}"
  "rg-monitor-smb-${REGION_ABBR}"
  "rg-backup-smb-${REGION_ABBR}"
  "rg-migrate-smb-${REGION_ABBR}"
  "rg-security-smb-${REGION_ABBR}"
)

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $1" | tee -a "$LOG_FILE"; }
hr() { echo "============================================================" | tee -a "$LOG_FILE"; }

# ── Teardown function ──────────────────────────────────────────────────────
# Use `azd down` first so Terraform state is cleaned; fall back to raw RG
# deletes for anything it misses (e.g. failed partial applies).
teardown() {
  local scenario="$1"
  cd "$PROJ_DIR"

  log "TEARDOWN [$scenario]: Selecting azd env smb-rf-tf-${scenario}..."
  if azd env select "smb-rf-tf-${scenario}" 2>/dev/null; then
    log "TEARDOWN [$scenario]: Running azd down --force --purge..."
    set +e
    azd down --force --purge 2>&1 | tee -a "$LOG_FILE"
    local azd_exit=$?
    set -e
    log "TEARDOWN [$scenario]: azd down exit=$azd_exit"
  else
    log "TEARDOWN [$scenario]: env not found — skipping azd down (will use az group delete fallback)"
  fi

  # Safety net: delete any stragglers that slipped past terraform destroy
  log "TEARDOWN [$scenario]: Deleting any remaining resource groups..."
  for rg in "${RGS[@]}"; do
    az group delete --name "$rg" --yes --no-wait 2>/dev/null || true
  done

  log "TEARDOWN [$scenario]: Waiting for RG deletions..."
  for rg in "${RGS[@]}"; do
    az group wait --name "$rg" --deleted 2>/dev/null || true
  done

  # Delete budget (best effort — azd down normally handles it)
  az consumption budget delete --budget-name budget-smb-monthly 2>/dev/null || true

  # Local backend: wipe per-env state file so the next apply starts clean
  rm -f "$PROJ_DIR/.azure/smb-rf-tf-${scenario}/terraform.tfstate" \
        "$PROJ_DIR/.azure/smb-rf-tf-${scenario}/terraform.tfstate.backup" 2>/dev/null || true

  # Verify cleanup
  local remaining
  remaining=$(az group list --query "[?starts_with(name,'rg-') && (contains(name,'smb') || contains(name,'spoke'))].name" -o tsv 2>/dev/null | wc -l)
  if [[ "$remaining" -eq 0 ]]; then
    log "TEARDOWN [$scenario]: CLEAN — no smb/spoke RGs remain"
  else
    log "TEARDOWN [$scenario]: WARNING — $remaining RGs still exist"
    az group list --query "[?starts_with(name,'rg-') && (contains(name,'smb') || contains(name,'spoke'))].name" -o tsv 2>&1 | tee -a "$LOG_FILE"
  fi
}

# ── Configure azd env ──────────────────────────────────────────────────────
configure_env() {
  local scenario="$1"
  cd "$PROJ_DIR"

  # The root main.tf has an `import` block that adopts a pre-existing MG.
  # On a fresh subscription we must create it first, otherwise terraform plan
  # fails with "Cannot import non-existent remote object".
  if ! az account management-group show --name "$MG_ID" >/dev/null 2>&1; then
    log "CONFIGURE [$scenario]: Creating management group $MG_ID..."
    az account management-group create --name "$MG_ID" --display-name "SMB Ready Foundation" 2>&1 | tee -a "$LOG_FILE" || true
    # MG creation is eventually consistent — give ARM a few seconds
    sleep 10
  fi

  # Select or create env (prefix `tf-` to avoid collision with Bicep envs)
  azd env select "smb-rf-tf-${scenario}" 2>/dev/null || \
    azd env new "smb-rf-tf-${scenario}" \
      --location "$LOCATION" \
      --subscription "$SUBSCRIPTION_ID" \
      --no-prompt

  azd env set SCENARIO "$scenario"
  azd env set OWNER "$OWNER"
  azd env set AZURE_LOCATION "$LOCATION"
  [[ -n "$SUBSCRIPTION_ID" ]] && azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION_ID"
  azd env set ENVIRONMENT prod
  azd env set HUB_VNET_ADDRESS_SPACE "$HUB_CIDR"
  azd env set SPOKE_VNET_ADDRESS_SPACE "$SPOKE_CIDR"
  azd env set LOG_ANALYTICS_DAILY_CAP_GB "0.5"

  # vpn and full need ON_PREMISES_ADDRESS_SPACE
  if [[ "$scenario" == "vpn" || "$scenario" == "full" ]]; then
    azd env set ON_PREMISES_ADDRESS_SPACE "$ON_PREM_CIDR"
  fi

  log "CONFIGURE [$scenario]: azd env set complete"
  azd env get-values 2>&1 | tee -a "$LOG_FILE"
}

# ── Deploy ─────────────────────────────────────────────────────────────────
deploy() {
  local scenario="$1"
  local start end duration exit_code

  cd "$PROJ_DIR"
  start=$(date +%s)
  log "DEPLOY [$scenario]: Starting azd up (terraform)..."

  set +e
  azd up --no-prompt 2>&1 | tee -a "$LOG_FILE"
  exit_code=$?
  set -e

  end=$(date +%s)
  duration=$(( end - start ))

  if [[ $exit_code -eq 0 ]]; then
    log "DEPLOY [$scenario]: SUCCESS (${duration}s)"
  else
    log "DEPLOY [$scenario]: FAILED exit=$exit_code (${duration}s) — retrying once..."
    sleep 60
    start=$(date +%s)
    set +e
    azd up --no-prompt 2>&1 | tee -a "$LOG_FILE"
    exit_code=$?
    set -e
    end=$(date +%s)
    duration=$(( end - start ))
    if [[ $exit_code -eq 0 ]]; then
      log "DEPLOY [$scenario]: RETRY SUCCESS (${duration}s)"
    else
      log "DEPLOY [$scenario]: RETRY FAILED exit=$exit_code (${duration}s) — STOPPING"
      return 1
    fi
  fi
}

# ── Validate ───────────────────────────────────────────────────────────────
validate() {
  local scenario="$1"
  local failures=0

  log "VALIDATE [$scenario]: Starting..."

  # 1. Check 6 RGs
  local rg_count
  rg_count=$(az group list --query "[?starts_with(name,'rg-') && (contains(name,'smb') || contains(name,'spoke'))].name" -o tsv 2>/dev/null | wc -l)
  if [[ "$rg_count" -ge 6 ]]; then
    log "VALIDATE [$scenario]: ✓ $rg_count resource groups"
  else
    log "VALIDATE [$scenario]: ✗ Only $rg_count resource groups (expected 6)"
    ((failures++))
  fi

  # 2. MG initiative (policy set) assignment — consolidated from 33 separate assignments
  local policy_count
  policy_count=$(az policy assignment list --scope "/providers/Microsoft.Management/managementGroups/${MG_ID}" --query "length([?name=='smb-baseline'])" -o tsv 2>/dev/null)
  if [[ "$policy_count" == "1" ]]; then
    log "VALIDATE [$scenario]: ✓ smb-baseline initiative assigned"
  else
    log "VALIDATE [$scenario]: ✗ smb-baseline initiative missing (expected 1, got $policy_count)"
    ((failures++))
  fi

  # 3. Budget
  local budget
  budget=$(az consumption budget list --query "[?starts_with(name,'budget')].amount" -o tsv 2>/dev/null || echo "")
  if [[ -n "$budget" ]]; then
    log "VALIDATE [$scenario]: ✓ Budget \$${budget}"
  else
    log "VALIDATE [$scenario]: ✗ No budget found"
    ((failures++))
  fi

  # 4. NAT Gateway (baseline only — firewall/vpn/full use FW or GW transit)
  local nat_count
  nat_count=$(az network nat-gateway list -g "rg-spoke-prod-${REGION_ABBR}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "$scenario" == "baseline" ]]; then
    if [[ "$nat_count" -ge 1 ]]; then
      log "VALIDATE [$scenario]: ✓ NAT Gateway present"
    else
      log "VALIDATE [$scenario]: ✗ NAT Gateway missing (expected for baseline)"
      ((failures++))
    fi
  fi

  # 5. Firewall (firewall/full only)
  local fw_count
  fw_count=$(az network firewall list -g "rg-hub-smb-${REGION_ABBR}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "$scenario" == "firewall" || "$scenario" == "full" ]]; then
    if [[ "$fw_count" -ge 1 ]]; then
      log "VALIDATE [$scenario]: ✓ Azure Firewall present"
    else
      log "VALIDATE [$scenario]: ✗ Firewall missing"
      ((failures++))
    fi
  else
    if [[ "$fw_count" -eq 0 ]]; then
      log "VALIDATE [$scenario]: ✓ No Firewall (correct for $scenario)"
    else
      log "VALIDATE [$scenario]: ✗ Unexpected Firewall found"
      ((failures++))
    fi
  fi

  # 6. VPN Gateway (vpn/full only)
  local vpn_count
  vpn_count=$(az network vnet-gateway list -g "rg-hub-smb-${REGION_ABBR}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "$scenario" == "vpn" || "$scenario" == "full" ]]; then
    if [[ "$vpn_count" -ge 1 ]]; then
      log "VALIDATE [$scenario]: ✓ VPN Gateway present"
    else
      log "VALIDATE [$scenario]: ✗ VPN Gateway missing"
      ((failures++))
    fi
  else
    if [[ "$vpn_count" -eq 0 ]]; then
      log "VALIDATE [$scenario]: ✓ No VPN Gateway (correct for $scenario)"
    else
      log "VALIDATE [$scenario]: ✗ Unexpected VPN Gateway"
      ((failures++))
    fi
  fi

  # 7. VNet peering (firewall/vpn/full)
  local peering_count
  peering_count=$(az network vnet peering list -g "rg-hub-smb-${REGION_ABBR}" --vnet-name "vnet-hub-smb-${REGION_ABBR}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "$scenario" != "baseline" ]]; then
    if [[ "$peering_count" -ge 1 ]]; then
      log "VALIDATE [$scenario]: ✓ VNet peering established"
    else
      log "VALIDATE [$scenario]: ✗ VNet peering missing"
      ((failures++))
    fi
  else
    if [[ "$peering_count" -eq 0 ]]; then
      log "VALIDATE [$scenario]: ✓ No peering (correct for baseline)"
    fi
  fi

  # 8. Route tables (firewall/full only — deployed to hub RG by design)
  if [[ "$scenario" == "firewall" || "$scenario" == "full" ]]; then
    local rt_count
    rt_count=$(az network route-table list -g "rg-hub-smb-${REGION_ABBR}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$rt_count" -ge 1 ]]; then
      log "VALIDATE [$scenario]: ✓ Route tables present"
    else
      log "VALIDATE [$scenario]: ✗ Route tables missing"
      ((failures++))
    fi
  fi

  # 9. Terraform state sanity — state file exists and has resources
  cd "$PROJ_DIR"
  local tf_resources
  tf_resources=$(terraform state list 2>/dev/null | wc -l)
  if [[ "$tf_resources" -gt 0 ]]; then
    log "VALIDATE [$scenario]: ✓ Terraform state has $tf_resources resources"
  else
    log "VALIDATE [$scenario]: ✗ Terraform state empty or unreadable"
    ((failures++))
  fi

  # Summary
  if [[ $failures -eq 0 ]]; then
    log "VALIDATE [$scenario]: ALL CHECKS PASSED ✓"
  else
    log "VALIDATE [$scenario]: $failures CHECKS FAILED ✗"
  fi
  return $failures
}

# ============================================================================
# MAIN
# ============================================================================

mkdir -p "$(dirname "$LOG_FILE")"
echo "" > "$LOG_FILE"
hr
log "SMB Ready Foundation (Terraform) — Scenario Test Runner"
log "Scenarios: ${SCENARIOS[*]}"
hr

# First: tear down whatever is currently deployed (any prior scenario env)
log "Pre-flight: detecting existing TF deployments to tear down cleanly..."
cd "$PROJ_DIR"
EXISTING_ENVS=()
for s in baseline firewall vpn full; do
  if [[ -d "$PROJ_DIR/.azure/smb-rf-tf-${s}" ]]; then
    EXISTING_ENVS+=("$s")
  fi
done

if [[ ${#EXISTING_ENVS[@]} -eq 0 ]]; then
  log "Pre-flight: no prior TF envs found — running raw RG sweep only"
  teardown "baseline"
else
  for prior in "${EXISTING_ENVS[@]}"; do
    log "Pre-flight: tearing down prior env smb-rf-tf-${prior}"
    teardown "$prior"
  done
fi
hr

# Run each scenario
for scenario in "${SCENARIOS[@]}"; do
  hr
  log "═══ SCENARIO: $scenario ═══"
  hr

  configure_env "$scenario"

  if ! deploy "$scenario"; then
    log "FATAL: $scenario deploy failed after retry — stopping"
    exit 1
  fi

  if ! validate "$scenario"; then
    log "WARNING: $scenario validation had failures — continuing to teardown"
  fi

  # Teardown after every scenario (including the last) so each scenario
  # leaves a clean subscription for the next run.
  teardown "$scenario"

  hr
done

log "═══ ALL SCENARIOS COMPLETE ═══"
