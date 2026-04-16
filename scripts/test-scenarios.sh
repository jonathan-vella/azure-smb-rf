#!/usr/bin/env bash
# ============================================================================
# SMB Ready Foundation — Automated Scenario Test Runner
# ============================================================================
# Runs: teardown (baseline) → firewall → vpn → full
# Each scenario: configure → deploy → validate → teardown → log
# MG + MG policies persist across scenarios; only RGs + budget torn down.
# ============================================================================
set -euo pipefail

PROJ_DIR="/workspaces/azure-smb-rf/infra/bicep/smb-ready-foundation"
LOG_FILE="/workspaces/azure-smb-rf/logs/test-scenarios.log"
OWNER="jonathan@lordofthecloud.eu"
LOCATION="swedencentral"
HUB_CIDR="10.0.0.0/23"
SPOKE_CIDR="10.0.2.0/23"
ON_PREM_CIDR="192.168.0.0/16"
MG_ID="smb-rf"

# Scenarios to test (baseline already done)
SCENARIOS=("firewall" "vpn" "full")

# Region abbreviation
REGION_ABBR="swc"

# Resource groups to tear down between scenarios
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
teardown() {
  local scenario="$1"
  log "TEARDOWN [$scenario]: Deleting resource groups..."
  for rg in "${RGS[@]}"; do
    az group delete --name "$rg" --yes --no-wait 2>/dev/null || true
  done

  log "TEARDOWN [$scenario]: Waiting for RG deletions..."
  for rg in "${RGS[@]}"; do
    az group wait --name "$rg" --deleted 2>/dev/null || true
  done

  # Delete budget
  az consumption budget delete --budget-name budget-smb-monthly 2>/dev/null || true

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

  # Select or create env
  azd env select "smb-rf-${scenario}" 2>/dev/null || azd env new "smb-rf-${scenario}"

  azd env set SCENARIO "$scenario"
  azd env set OWNER "$OWNER"
  azd env set AZURE_LOCATION "$LOCATION"
  azd env set ENVIRONMENT prod
  azd env set HUB_VNET_ADDRESS_SPACE "$HUB_CIDR"
  azd env set SPOKE_VNET_ADDRESS_SPACE "$SPOKE_CIDR"
  azd env set LOG_ANALYTICS_DAILY_CAP_GB "0.5"
  azd env set MANAGEMENT_GROUP_ID "$MG_ID"

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
  log "DEPLOY [$scenario]: Starting azd up..."

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

  # 2. MG policies
  local policy_count
  policy_count=$(az policy assignment list --scope "/providers/Microsoft.Management/managementGroups/${MG_ID}" --query "length(@)" -o tsv 2>/dev/null)
  if [[ "$policy_count" -ge 30 ]]; then
    log "VALIDATE [$scenario]: ✓ $policy_count MG policies"
  else
    log "VALIDATE [$scenario]: ✗ Only $policy_count MG policies (expected ≥30)"
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

echo "" > "$LOG_FILE"
hr
log "SMB Ready Foundation — Scenario Test Runner"
log "Scenarios: ${SCENARIOS[*]}"
hr

# First: tear down baseline
log "Starting with baseline teardown..."
teardown "baseline"
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
    log "WARNING: $scenario validation had failures — continuing"
  fi

  # Teardown between scenarios (not after the last one — Phase E handles that)
  if [[ "$scenario" != "full" ]]; then
    teardown "$scenario"
  fi

  hr
done

log "═══ ALL SCENARIOS COMPLETE ═══"
log "Remaining: Phase E final cleanup (run manually)"
