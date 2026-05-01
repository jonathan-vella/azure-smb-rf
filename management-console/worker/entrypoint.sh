#!/usr/bin/env bash
# Container Apps Job entrypoint — runs ONE deployment then exits.
#
# Required env (from API job-execution payload):
#   CUSTOMER_ID, SUBSCRIPTION_ID, ENV_NAME,
#   SCENARIO (baseline|firewall|vpn|full), DEPLOYMENT_ID,
#   PARAMETERS_JSON (JSON object), API_BASE_URL
# Required env (from job definition):
#   AZURE_CLIENT_ID, AZURE_TENANT_ID
set -euo pipefail

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

report_status() {
  local status="$1" reason="${2:-}"
  local token
  # Use the API app's resource ID (api://<API_CLIENT_ID>) as the audience, which
  # matches the API_AUDIENCE configured on the API container app.
  token="$(az account get-access-token --resource "api://${API_CLIENT_ID:-}" --query accessToken -o tsv 2>/dev/null || true)"
  [[ -z "$token" ]] && return 0
  curl -fsS -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"status\":\"$status\",\"failureReason\":\"$reason\"}" \
    "$API_BASE_URL/deployments/$CUSTOMER_ID/$DEPLOYMENT_ID/status" || true
}

# Background log streamer: reads lines from a FIFO and POSTs each to the API
# /logs endpoint, which appends them to a per-deployment blob. The SPA polls
# that blob with a cursor for live console output. Lines are also mirrored
# to fd 3 so container stdout (and Log Analytics) keeps a copy.
stream_logs() {
  local token="" exp=0 now body
  while IFS= read -r line; do
    printf '%s\n' "$line" >&3
    now=$(date +%s)
    if (( now >= exp - 60 )); then
      token="$(az account get-access-token --resource "api://${API_CLIENT_ID:-}" --query accessToken -o tsv 2>/dev/null || true)"
      exp=$((now + 3000))  # ~50 min
    fi
    [[ -z "$token" || -z "${API_BASE_URL:-}" ]] && continue
    body="$(jq -nc --arg l "$line" '{lines:[$l]}')"
    curl -fsS -m 5 -X POST \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$API_BASE_URL/deployments/$CUSTOMER_ID/$DEPLOYMENT_ID/logs" >/dev/null 2>&1 || true
  done
}

LOG_PIPE=""
LOG_PID=""
start_streaming() {
  exec 3>&1 4>&2
  LOG_PIPE="$(mktemp -u /tmp/logpipe.XXXXXX)"
  mkfifo "$LOG_PIPE"
  stream_logs <"$LOG_PIPE" &
  LOG_PID=$!
  exec >"$LOG_PIPE" 2>&1
}
stop_streaming() {
  [[ -z "$LOG_PID" ]] && return 0
  exec >&3 2>&4
  wait "$LOG_PID" 2>/dev/null || true
  [[ -n "$LOG_PIPE" ]] && rm -f "$LOG_PIPE"
  LOG_PID=""
}

# Heartbeat: long ARM operations (VPN gateway, firewall) keep azd silent for
# 20-30 minutes. Print a line every 60s while a long command runs so the SPA
# log stream and container stdout never appear stalled. Started/stopped
# around the azd up call.
HEARTBEAT_PID=""
start_heartbeat() {
  local label="${1:-azd}"
  local started
  started=$(date +%s)
  (
    while true; do
      sleep 60
      local now elapsed mins
      now=$(date +%s)
      elapsed=$((now - started))
      mins=$((elapsed / 60))
      printf '[heartbeat] %s still running (elapsed %dm)\n' "$label" "$mins"
    done
  ) &
  HEARTBEAT_PID=$!
}
stop_heartbeat() {
  [[ -z "$HEARTBEAT_PID" ]] && return 0
  kill "$HEARTBEAT_PID" 2>/dev/null || true
  wait "$HEARTBEAT_PID" 2>/dev/null || true
  HEARTBEAT_PID=""
}

fail() { log "FAIL: $*"; report_status "Failed" "$*"; stop_heartbeat; stop_streaming; exit 1; }
trap 'fail "unexpected error on line $LINENO"' ERR

# 1. Login as the UAMI (federated to the job container) — needed first so we
#    can mint API tokens for the log streamer.
log "Logging in as managed identity client_id=$AZURE_CLIENT_ID"
az login --identity --client-id "$AZURE_CLIENT_ID" >/dev/null
azd auth login --managed-identity --client-id "$AZURE_CLIENT_ID" >/dev/null

# Begin streaming all subsequent stdout/stderr to the API log endpoint.
start_streaming
log "Log stream attached to deployment $DEPLOYMENT_ID"

# 2. Upgrade az CLI and azd to latest. Cheap (~10s) and avoids rebuilding the
#    image every time a new release ships. Set SKIP_TOOL_UPGRADE=1 to disable.
if [[ "${SKIP_TOOL_UPGRADE:-}" != "1" ]]; then
  log "Upgrading az CLI and azd"
  tdnf -y --refresh update azure-cli >/dev/null 2>&1 || log "az upgrade skipped (tdnf failed)"
  az bicep upgrade >/dev/null 2>&1 || true
  curl -fsSL https://aka.ms/install-azd.sh | bash >/dev/null 2>&1 || log "azd upgrade skipped"
  log "Tool versions: az=$(az version --output json 2>/dev/null | jq -r '."azure-cli" // empty' 2>/dev/null) azd=$(azd version --output json 2>/dev/null | jq -r '.azd.version' 2>/dev/null)"
fi

# 3. Select the customer subscription (visible thanks to Lighthouse delegation).
az account set --subscription "$SUBSCRIPTION_ID"
log "Active subscription: $(az account show --query id -o tsv)"

# 4. Clone the repo at the pinned ref (default to main; override via REPO_REF).
REPO_URL="${REPO_URL:-https://github.com/jonathan-vella/azure-smb-rf.git}"
REPO_REF="${REPO_REF:-main}"
log "Cloning $REPO_URL @ $REPO_REF"
git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" /work/repo
cd "/work/repo/infra/bicep/smb-ready-foundation"

# 5. Apply parameters as azd env vars.
azd env new "${CUSTOMER_ID}-${ENV_NAME}" --subscription "$SUBSCRIPTION_ID" --location "${AZURE_LOCATION:-swedencentral}" || true
azd env select "${CUSTOMER_ID}-${ENV_NAME}"
azd env set SCENARIO "$SCENARIO"
azd env set ENVIRONMENT "$ENV_NAME"
# Foundation (MG + 30 MG-scope policies) is provisioned out-of-band by the
# customer admin; the worker UAMI has no rights at parent-MG / tenant-root
# scope, so tell the bicep pre-provision hook to skip those steps.
azd env set SKIP_MG_DEPLOY true

# Splat PARAMETERS_JSON keys into azd env. Fail loud if the payload is empty
# or malformed — silently skipping leaves required parameters (e.g. OWNER)
# unset and produces a confusing 'missing required inputs' error from azd up.
if [[ -z "${PARAMETERS_JSON:-}" || "$PARAMETERS_JSON" == "null" ]]; then
  fail "PARAMETERS_JSON is empty — API did not forward deployment parameters."
fi
if ! echo "$PARAMETERS_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
  fail "PARAMETERS_JSON is not a JSON object: $PARAMETERS_JSON"
fi
keys_set=()
while IFS=$'\t' read -r k v; do
  [[ -z "$k" ]] && continue
  azd env set "$k" "$v"
  keys_set+=("$k")
done < <(echo "$PARAMETERS_JSON" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
log "Applied ${#keys_set[@]} parameter(s) to azd env: ${keys_set[*]}"

# Forward the pre-created policy MI (created by the customer admin during
# onboarding via management-console/infra/onboarding/policy-mi.bicep). When
# unset, the foundation falls back to SystemAssigned for the smb-backup-02
# DINE policy and the partner UAMI will be unable to grant Backup/VM
# Contributor to it via Lighthouse (the role assignments target a customer-
# tenant principal not in the partner authorizations list).
if [[ -n "${POLICY_MI_RESOURCE_ID:-}" ]]; then
  azd env set POLICY_MI_RESOURCE_ID "$POLICY_MI_RESOURCE_ID"
  log "Wired pre-created policy MI: $POLICY_MI_RESOURCE_ID"
fi

# Generate main.bicepparam on the fly and remove the legacy
# main.parameters.json. The committed parameters file uses ${VAR}
# substitution, but azd >= 1.24 JSON-parses the file before substituting,
# so the unquoted "value": ${BUDGET_AMOUNT} (int) produces
# 'invalid character $ looking for beginning of value'. A bicepparam file
# uses readEnvironmentVariable() which is evaluated by Bicep itself, after
# azd has populated the env from azd env vars.
rm -f main.parameters.json
cat > main.bicepparam <<'BICEPPARAM'
using 'main.bicep'

param scenario = readEnvironmentVariable('SCENARIO', 'baseline')
param owner = readEnvironmentVariable('OWNER', '')
param location = readEnvironmentVariable('AZURE_LOCATION', 'swedencentral')
param environment = readEnvironmentVariable('ENVIRONMENT', 'prod')
param hubVnetAddressSpace = readEnvironmentVariable('HUB_VNET_ADDRESS_SPACE', '10.0.0.0/23')
param spokeVnetAddressSpace = readEnvironmentVariable('SPOKE_VNET_ADDRESS_SPACE', '10.0.2.0/23')
param onPremisesAddressSpace = readEnvironmentVariable('ON_PREMISES_ADDRESS_SPACE', '')
param logAnalyticsDailyCapGb = readEnvironmentVariable('LOG_ANALYTICS_DAILY_CAP_GB', '0.5')
param budgetAmount = int(readEnvironmentVariable('BUDGET_AMOUNT', '500'))
param policyMiResourceId = readEnvironmentVariable('POLICY_MI_RESOURCE_ID', '')
BICEPPARAM
log "Wrote main.bicepparam"

# 6. Run the deployment.
log "Starting azd up"
report_status "Running" ""
start_heartbeat "azd up"
azd up --no-prompt
stop_heartbeat
log "azd up succeeded"
report_status "Succeeded" ""
stop_streaming
