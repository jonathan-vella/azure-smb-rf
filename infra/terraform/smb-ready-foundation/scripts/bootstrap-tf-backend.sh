#!/usr/bin/env bash
# =============================================================================
# Bootstrap the Terraform remote state backend for smb-ready-foundation.
# Idempotent: safe to re-run. Creates (if missing):
#   • Resource group            rg-tfstate-smb-<region_short>
#   • Storage account           sttfstatesmb<hash>       (globally unique)
#   • Blob container            tfstate
# Writes backend values to: <iac_path>/.azure/<env>/backend.hcl
#
# Can be invoked directly or from hooks/pre-provision.sh. Safe for CI.
# =============================================================================
set -euo pipefail

: "${AZURE_LOCATION:=swedencentral}"

# Resolve IaC path (repo-relative). Script lives in <iac_path>/scripts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- region short code -------------------------------------------------------
case "$AZURE_LOCATION" in
  swedencentral)      REGION_SHORT="swc" ;;
  germanywestcentral) REGION_SHORT="gwc" ;;
  *)                  REGION_SHORT="${AZURE_LOCATION:0:3}" ;;
esac

RG_NAME="rg-tfstate-smb-${REGION_SHORT}"
CONTAINER_NAME="tfstate"

# Storage account name: sttfstatesmb<12-char hash of subscription id>
SUB_ID="$(az account show --query id -o tsv)"
if [[ -z "$SUB_ID" ]]; then
  echo "ERROR: not authenticated. Run 'az login'." >&2
  exit 1
fi
HASH="$(printf '%s' "$SUB_ID" | sha1sum | cut -c1-12)"
SA_NAME="sttfstatesmb${HASH}"

AZD_ENV_NAME="${AZURE_ENV_NAME:-${AZD_ENV_NAME:-smb-ready-foundation}}"
BACKEND_DIR="${IAC_PATH}/.azure/${AZD_ENV_NAME}"
BACKEND_FILE="${BACKEND_DIR}/backend.hcl"

echo "==> Bootstrapping Terraform state backend"
echo "    RG:        $RG_NAME"
echo "    Storage:   $SA_NAME"
echo "    Container: $CONTAINER_NAME"
echo "    Backend:   $BACKEND_FILE"

# ---- resource group ----------------------------------------------------------
if ! az group show -n "$RG_NAME" >/dev/null 2>&1; then
  az group create -n "$RG_NAME" -l "$AZURE_LOCATION" \
    --tags Environment=smb Owner=platform Project=smb-ready-foundation ManagedBy=Terraform \
    >/dev/null
  echo "    + resource group created"
else
  echo "    . resource group exists"
fi

# ---- storage account ---------------------------------------------------------
if ! az storage account show -n "$SA_NAME" -g "$RG_NAME" >/dev/null 2>&1; then
  az storage account create \
    -n "$SA_NAME" -g "$RG_NAME" -l "$AZURE_LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --allow-shared-key-access true \
    --tags Environment=smb Owner=platform Project=smb-ready-foundation ManagedBy=Terraform Purpose=tfstate \
    >/dev/null
  echo "    + storage account created"
else
  echo "    . storage account exists"
fi

# ---- blob container ----------------------------------------------------------
SA_KEY="$(az storage account keys list -n "$SA_NAME" -g "$RG_NAME" --query '[0].value' -o tsv)"
if ! az storage container show \
      --name "$CONTAINER_NAME" \
      --account-name "$SA_NAME" \
      --account-key "$SA_KEY" >/dev/null 2>&1; then
  az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$SA_NAME" \
    --account-key "$SA_KEY" \
    >/dev/null
  echo "    + container created"
else
  echo "    . container exists"
fi

# ---- write backend.hcl -------------------------------------------------------
mkdir -p "$BACKEND_DIR"
cat > "$BACKEND_FILE" <<HCL
resource_group_name  = "${RG_NAME}"
storage_account_name = "${SA_NAME}"
container_name       = "${CONTAINER_NAME}"
key                  = "smb-ready-foundation.tfstate"
HCL
echo "    + wrote $BACKEND_FILE"

echo "==> Done. Run: terraform init -backend-config=$BACKEND_FILE"
