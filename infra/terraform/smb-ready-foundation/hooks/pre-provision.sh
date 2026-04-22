#!/usr/bin/env bash
# =============================================================================
# SMB Ready Foundations — Terraform pre-provision hook
# =============================================================================
# Runs before `azd provision`. Jobs:
#   1. Parameter validation (owner, CIDRs)
#   2. Azure preflight (auth, required RPs)
#   3. Enable azd alpha.terraform (idempotent)
#   4. Bootstrap the state backend (calls scripts/bootstrap-tf-backend.sh)
#   5. Write terraform.auto.tfvars.json from azd env (incl. budget_start_date
#      pinned to first-of-month UTC to avoid azurerm time drift)
#   6. Delete any stale budget with the same name (Azure API limitation —
#      cannot update start_date post-creation)
#   7. Clean faulted firewall / VPN Gateway from prior failed runs
#   8. terraform init -reconfigure with the bootstrapped backend
#   9b. Import pre-existing Defender pricings (subscription singletons that
#       cannot be deleted — only tier-switched — so they must be imported
#       after a local-state wipe to avoid "already exists" errors)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./_lib.sh
. "$SCRIPT_DIR/_lib.sh"

# ---- env resolution ----------------------------------------------------------
SCENARIO="${SCENARIO:-baseline}"
OWNER="${OWNER:-}"
AZURE_LOCATION="${AZURE_LOCATION:-swedencentral}"
ENVIRONMENT_NAME="${ENVIRONMENT:-prod}"   # TF variable is `environment`
HUB_CIDR="${HUB_VNET_ADDRESS_SPACE:-10.0.0.0/23}"
SPOKE_CIDR="${SPOKE_VNET_ADDRESS_SPACE:-10.0.2.0/23}"
ON_PREM_CIDR="${ON_PREMISES_ADDRESS_SPACE:-}"
LAW_CAP="${LOG_ANALYTICS_DAILY_CAP_GB:-0.5}"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-100}"
BUDGET_ALERT_EMAIL="${BUDGET_ALERT_EMAIL:-}"

eval "$(resolve_scenario_flags "$SCENARIO")"

printf '\n========================================\n'
printf '  SMB Ready Foundations (Terraform) — Pre-Provision\n'
printf '  Scenario: %s\n' "$SCENARIO"
printf '========================================\n\n'

# ---- 1. Parameter validation -------------------------------------------------
log_step 1 'Validating parameters'
if [[ -z "$OWNER" ]]; then
  OWNER="$(az ad signed-in-user show --query mail -o tsv 2>/dev/null || true)"
  [[ -z "$OWNER" ]] && OWNER="$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)"
  if [[ -z "$OWNER" ]]; then
    log_error "OWNER not set and could not auto-detect. Run: azd env set OWNER your@email.com"
    exit 1
  fi
  log_substep "Auto-detected owner: $OWNER"
fi

if [[ "$DEPLOY_VPN" == "true" && -z "$ON_PREM_CIDR" ]]; then
  log_error "ON_PREMISES_ADDRESS_SPACE required for VPN scenarios. Run: azd env set ON_PREMISES_ADDRESS_SPACE 192.168.0.0/16"
  exit 1
fi

# ---- 2. CIDR validation ------------------------------------------------------
log_step 2 'Validating CIDR address spaces'
is_valid_cidr "$HUB_CIDR"   || { log_error "Invalid hub CIDR: $HUB_CIDR"; exit 1; }
is_valid_cidr "$SPOKE_CIDR" || { log_error "Invalid spoke CIDR: $SPOKE_CIDR"; exit 1; }
if cidr_overlaps "$HUB_CIDR" "$SPOKE_CIDR"; then
  log_error "Hub ($HUB_CIDR) and spoke ($SPOKE_CIDR) overlap"; exit 1
fi
if [[ -n "$ON_PREM_CIDR" ]]; then
  is_valid_cidr "$ON_PREM_CIDR" || { log_error "Invalid on-prem CIDR: $ON_PREM_CIDR"; exit 1; }
  cidr_overlaps "$HUB_CIDR"   "$ON_PREM_CIDR" && { log_error "Hub and on-prem overlap"; exit 1; }
  cidr_overlaps "$SPOKE_CIDR" "$ON_PREM_CIDR" && { log_error "Spoke and on-prem overlap"; exit 1; }
fi
log_substep 'All CIDRs valid and non-overlapping'

# ---- 3. Azure preflight ------------------------------------------------------
log_step 3 'Azure preflight'
SUB_ID="$(az account show --query id -o tsv 2>/dev/null || true)"
[[ -z "$SUB_ID" ]] && { log_error 'Not authenticated. Run: az login'; exit 1; }
log_substep "Subscription: $SUB_ID"

for rp in Microsoft.Compute Microsoft.Network Microsoft.Storage Microsoft.KeyVault \
          Microsoft.OperationalInsights Microsoft.RecoveryServices Microsoft.Automation \
          Microsoft.Insights Microsoft.Authorization Microsoft.Management \
          Microsoft.PolicyInsights Microsoft.Migrate Microsoft.Security Microsoft.Consumption; do
  state="$(az provider show -n "$rp" --query registrationState -o tsv 2>/dev/null || echo NotRegistered)"
  if [[ "$state" != "Registered" ]]; then
    log_substep "Registering $rp (state: $state)..."
    az provider register -n "$rp" --wait >/dev/null || true
  fi
done

# ---- 4. Enable azd alpha.terraform ------------------------------------------
log_step 4 'Enabling azd alpha.terraform feature'
azd config set alpha.terraform on >/dev/null

# ---- 4b. Select backend type (azurerm | local) -------------------------------
# TF_BACKEND=local is intended for short-lived test/CI runs so that
# `terraform destroy` / `azd down` fully destroys everything in state
# (including sub/tenant-scope resources) without the cross-run ambiguity
# of a shared Azure Storage state blob. Local state lives inside
# .azure/<env>/ and is therefore isolated per azd env.
TF_BACKEND="${TF_BACKEND:-azurerm}"
log_substep "Backend: $TF_BACKEND"

if [[ "$TF_BACKEND" == "local" ]]; then
  # Terraform's native override mechanism: *_override.tf files merge on top
  # of their non-override counterparts and can replace the backend block.
  cat > "$IAC_DIR/backend_override.tf" <<'HCL'
# AUTO-GENERATED by pre-provision.sh (TF_BACKEND=local). Do not commit.
terraform {
  backend "local" {}
}
HCL
  log_substep 'Wrote backend_override.tf (local backend)'
else
  # Make sure a stale override from a prior local run does not leak into
  # an azurerm run.
  rm -f "$IAC_DIR/backend_override.tf"
fi

# ---- 5. Bootstrap state backend (azurerm only) ------------------------------
if [[ "$TF_BACKEND" == "local" ]]; then
  log_step 5 'Skipping remote backend bootstrap (TF_BACKEND=local)'
  # Ensure the per-env directory exists for the local state file.
  mkdir -p "$IAC_DIR/.azure/${AZURE_ENV_NAME:-smb-ready-foundation}"
else
  log_step 5 'Bootstrapping Terraform state backend'
  AZURE_LOCATION="$AZURE_LOCATION" AZURE_ENV_NAME="${AZURE_ENV_NAME:-smb-ready-foundation}" \
    bash "$IAC_DIR/scripts/bootstrap-tf-backend.sh"
fi

# ---- 6. Write auto.tfvars.json ----------------------------------------------
log_step 6 'Writing terraform.auto.tfvars.json'
BUDGET_START_DATE="$(date -u +%Y-%m-01)"

# Build allowed_vm_skus JSON array from azd env if set (comma-separated).
if [[ -n "${ALLOWED_VM_SKUS:-}" ]]; then
  ALLOWED_VM_SKUS_JSON="$(printf '%s' "$ALLOWED_VM_SKUS" | awk -v RS=, 'BEGIN{printf "["} NR>1{printf ","} {gsub(/[[:space:]]/,""); printf "\"%s\"", $0} END{printf "]"}')"
else
  ALLOWED_VM_SKUS_JSON='null'  # Terraform uses the variable default.
fi

cat > "$IAC_DIR/terraform.auto.tfvars.json" <<JSON
{
  "subscription_id": "$SUB_ID",
  "location": "$AZURE_LOCATION",
  "environment": "$ENVIRONMENT_NAME",
  "owner": "$OWNER",
  "hub_vnet_address_space": "$HUB_CIDR",
  "spoke_vnet_address_space": "$SPOKE_CIDR",
  "on_premises_address_space": "$ON_PREM_CIDR",
  "log_analytics_daily_cap_gb": $LAW_CAP,
  "budget_amount": $BUDGET_AMOUNT,
  "budget_alert_email": "$BUDGET_ALERT_EMAIL",
  "budget_start_date": "$BUDGET_START_DATE",
  "deploy_firewall": $DEPLOY_FIREWALL,
  "deploy_vpn": $DEPLOY_VPN
}
JSON
log_substep "budget_start_date=$BUDGET_START_DATE, deploy_firewall=$DEPLOY_FIREWALL, deploy_vpn=$DEPLOY_VPN"

# azd alpha.terraform requires a main.tfvars.json template. Our values already
# live in terraform.auto.tfvars.json (auto-loaded by TF), so we write an empty
# object here solely to satisfy azd's template check.
if [[ ! -f "$IAC_DIR/main.tfvars.json" ]]; then
  printf '{}\n' > "$IAC_DIR/main.tfvars.json"
  log_substep 'Wrote empty main.tfvars.json (azd template placeholder)'
fi

# ---- 7. Delete stale budget --------------------------------------------------
log_step 7 'Cleaning stale resources'
if az consumption budget show --budget-name 'budget-smb-monthly' >/dev/null 2>&1; then
  log_substep 'Deleting existing budget-smb-monthly (start_date is immutable)'
  az consumption budget delete --budget-name 'budget-smb-monthly' >/dev/null 2>&1 || true
else
  log_substep 'No stale budget'
fi

REGION_SHORT='swc'
[[ "$AZURE_LOCATION" == 'germanywestcentral' ]] && REGION_SHORT='gwc'
HUB_RG="rg-hub-smb-$REGION_SHORT"

if az group exists --name "$HUB_RG" 2>/dev/null | grep -q true; then
  FW_STATE="$(az network firewall show -g "$HUB_RG" -n "fw-hub-smb-$REGION_SHORT" --query provisioningState -o tsv 2>/dev/null || true)"
  if [[ "$FW_STATE" == 'Failed' ]]; then
    log_substep 'Deleting faulted firewall'
    az network firewall delete -g "$HUB_RG" -n "fw-hub-smb-$REGION_SHORT" >/dev/null 2>&1 || true
    az network firewall policy delete -g "$HUB_RG" -n "fwpol-hub-smb-$REGION_SHORT" >/dev/null 2>&1 || true
  fi
  VPN_STATE="$(az network vnet-gateway show -g "$HUB_RG" -n "vpng-hub-smb-$REGION_SHORT" --query provisioningState -o tsv 2>/dev/null || true)"
  if [[ "$VPN_STATE" == 'Failed' ]]; then
    log_substep 'Deleting faulted VPN gateway'
    az network vnet-gateway delete -g "$HUB_RG" -n "vpng-hub-smb-$REGION_SHORT" --no-wait >/dev/null 2>&1 || true
  fi
fi

# ---- 8. Write provider.conf.json for azd alpha.terraform ---------------------
# azd's terraform provider generates its own backend config from this template
# (separate path from our backend.hcl). Values must match bootstrap-tf-backend.
if [[ "$TF_BACKEND" == "local" ]]; then
  log_step 8 'Writing provider.conf.json (local backend)'
  LOCAL_STATE_PATH="$IAC_DIR/.azure/${AZURE_ENV_NAME:-smb-ready-foundation}/terraform.tfstate"
  cat > "$IAC_DIR/provider.conf.json" <<JSON
{
  "path": "$LOCAL_STATE_PATH"
}
JSON
  log_substep "provider.conf.json written (local path=$LOCAL_STATE_PATH)"
else
  log_step 8 'Writing provider.conf.json (azd backend template)'
  BACKEND_FILE="$IAC_DIR/.azure/${AZURE_ENV_NAME:-smb-ready-foundation}/backend.hcl"
  # Extract values from backend.hcl (source of truth)
  BACKEND_RG="$(awk -F'=' '/resource_group_name/ {gsub(/[" ]/,"",$2); print $2}' "$BACKEND_FILE")"
  BACKEND_SA="$(awk -F'=' '/storage_account_name/ {gsub(/[" ]/,"",$2); print $2}' "$BACKEND_FILE")"
  BACKEND_CT="$(awk -F'=' '/container_name/ {gsub(/[" ]/,"",$2); print $2}' "$BACKEND_FILE")"
  BACKEND_KEY="$(awk -F'=' '/^key/ {gsub(/[" ]/,"",$2); print $2}' "$BACKEND_FILE")"

  cat > "$IAC_DIR/provider.conf.json" <<JSON
{
  "resource_group_name": "$BACKEND_RG",
  "storage_account_name": "$BACKEND_SA",
  "container_name": "$BACKEND_CT",
  "key": "$BACKEND_KEY"
}
JSON
  log_substep "provider.conf.json written (sa=$BACKEND_SA, key=$BACKEND_KEY)"
fi

# ---- 9. terraform init with backend config ---------------------------------
log_step 9 'terraform init -reconfigure'
(
  cd "$IAC_DIR"
  if [[ "$TF_BACKEND" == "local" ]]; then
    terraform init -reconfigure \
      -backend-config="path=$IAC_DIR/.azure/${AZURE_ENV_NAME:-smb-ready-foundation}/terraform.tfstate" \
      -input=false >/dev/null
  else
    terraform init -reconfigure -backend-config="$BACKEND_FILE" -input=false >/dev/null
  fi
)
log_substep 'Ready for azd provision'

# ---- 9b. Import pre-existing Defender pricings (subscription singletons) ----
# /subscriptions/<id>/providers/Microsoft.Security/pricings/{plan} is a
# subscription-scoped singleton — it cannot be deleted, only tier-switched
# (Free<->Standard). When local state is wiped between test runs the resource
# still exists in Azure, so `terraform apply` fails with "already exists".
# Import each plan into state (if not already tracked) to heal the drift.
log_step '9b' 'Importing pre-existing Defender pricings (if present in Azure)'
(
  cd "$IAC_DIR"
  SUB_ID="$(az account show --query id -o tsv)"
  for plan in VirtualMachines StorageAccounts KeyVaults Arm; do
    tf_addr="module.defender.azurerm_security_center_subscription_pricing.free[\"${plan}\"]"
    az_id="/subscriptions/${SUB_ID}/providers/Microsoft.Security/pricings/${plan}"
    # Already tracked? Skip.
    if terraform state show "$tf_addr" >/dev/null 2>&1; then
      log_substep "$plan already in state"
      continue
    fi
    # Exists in Azure? Import.
    if az security pricing show --name "$plan" --query name -o tsv >/dev/null 2>&1; then
      if terraform import -input=false "$tf_addr" "$az_id" >/dev/null 2>&1; then
        log_substep "$plan imported"
      else
        log_substep "$plan import failed (will let apply handle)"
      fi
    else
      log_substep "$plan not in Azure — apply will create"
    fi
  done
)

printf '\n==> Pre-provision complete.\n\n'
