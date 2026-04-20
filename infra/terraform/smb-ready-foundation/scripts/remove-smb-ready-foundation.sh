#!/usr/bin/env bash
# =============================================================================
# SMB Ready Foundation — Terraform teardown
# =============================================================================
# Runs `terraform destroy` for the smb-ready-foundation stack, then optionally
# deletes the management group (Terraform keeps it because of the import block).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

AUTO_APPROVE=false
DELETE_MG=false
DELETE_BACKEND=false
for arg in "$@"; do
  case "$arg" in
    -y|--yes)            AUTO_APPROVE=true ;;
    --delete-mg)         DELETE_MG=true ;;
    --delete-backend)    DELETE_BACKEND=true ;;
    -h|--help)
      cat <<USAGE
Usage: $(basename "$0") [-y] [--delete-mg] [--delete-backend]

  -y, --yes            Skip confirmation prompt.
  --delete-mg          Also delete the smb-rf management group after destroy.
  --delete-backend     Also delete the tfstate storage account + RG.
USAGE
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

printf '\n========================================\n'
printf '  SMB Ready Foundation — Teardown\n'
printf '========================================\n\n'

SUB_ID="$(az account show --query id -o tsv 2>/dev/null || true)"
[[ -z "$SUB_ID" ]] && { printf 'ERROR: not authenticated\n' >&2; exit 1; }
SUB_NAME="$(az account show --query name -o tsv)"
printf '  Subscription: %s (%s)\n\n' "$SUB_NAME" "$SUB_ID"

if [[ "$AUTO_APPROVE" != 'true' ]]; then
  printf '  This will DESTROY all SMB Ready Foundation resources managed by Terraform.\n'
  printf '  Type the subscription id to confirm: '
  read -r confirm
  if [[ "$confirm" != "$SUB_ID" ]]; then
    printf '  Aborted.\n'; exit 1
  fi
fi

cd "$IAC_DIR"

# Pre-destroy: drop stale budget so terraform can re-delete cleanly.
az consumption budget delete --budget-name 'budget-smb-monthly' >/dev/null 2>&1 || true

printf '\n==> terraform destroy\n'
if [[ "$AUTO_APPROVE" == 'true' ]]; then
  terraform destroy -auto-approve -input=false
else
  terraform destroy -input=false
fi

if [[ "$DELETE_MG" == 'true' ]]; then
  printf '\n==> Deleting management group smb-rf\n'
  az account management-group delete --name smb-rf 2>/dev/null || \
    printf '    (MG delete failed — ensure no child subscriptions remain)\n'
fi

if [[ "$DELETE_BACKEND" == 'true' ]]; then
  REGION_SHORT='swc'
  [[ "${AZURE_LOCATION:-swedencentral}" == 'germanywestcentral' ]] && REGION_SHORT='gwc'
  BACKEND_RG="rg-tfstate-smb-$REGION_SHORT"
  printf '\n==> Deleting state backend RG %s\n' "$BACKEND_RG"
  az group delete --name "$BACKEND_RG" --yes --no-wait 2>/dev/null || true
fi

printf '\n==> Teardown complete.\n\n'
