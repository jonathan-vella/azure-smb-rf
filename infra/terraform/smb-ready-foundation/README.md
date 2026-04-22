# SMB Ready Foundations — Terraform port

Terraform variant of `infra/bicep/smb-ready-foundation/`, delivering the same
A repeatable, easy-to-deploy, and well-managed Azure platform for SMB customers
(MG + 33 policies + hub/spoke networking + optional firewall
/ VPN + monitoring, backup, migrate, Key Vault, automation) via
`azurerm ~> 4.0` + `azapi ~> 2.0`.

**All 10 phases complete.** Ready for `terraform test`, CI validation, and a
real `azd provision` run against an Azure subscription. Agent-track artifacts
are published under [`agent-output/smb-ready-foundation/`](../../../agent-output/smb-ready-foundation/).

> **Child-module layout.** Bicep splits the MG bootstrap into a separate
> `deploy-mg.bicep` because Bicep requires `targetScope = 'managementGroup'`
> vs. `'subscription'` as two discrete deployments. Terraform has no such
> restriction: one root composes resources at multiple scopes in a single
> `apply`. The root `main.tf` orchestrates 17 child modules under
> `modules/` (one per topical concern — MG, policies, RGs, networking,
> firewall, VPN, peering, monitoring, backup, migrate, KV, automation,
> budget, defender), each with its own `main.tf` / `variables.tf` /
> `outputs.tf`. The root-level `import` block adopts a pre-existing
> management group into `module.management_group.azurerm_management_group.smb_rf`.

## Status by phase

| Phase | Scope                                                                                                                                                                                                                                             | Status      |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| 1     | Root scaffolding (`versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `azure.yaml`, `.gitignore`, `terraform.tfvars.example`)                                                                                 | ✅ complete |
| 2     | Management group + subscription association + 33 MG-scoped policy assignments (`modules/management-group/`, `modules/policy-assignments-mg/`)                                                                                                     | ✅ complete |
| 3     | Child-module composition — root `main.tf` orchestrates 17 modules under `modules/`                                                                                                                                                                | ✅ complete |
| 4     | Resources under `modules/`: `resource-groups`, `network-hub`, `network-spoke`, `firewall`, `route-tables`, `vpn-gateway`, `peering`, `monitoring`, `backup`, `policy-backup-auto`, `migrate`, `keyvault`, `automation`, `budget`, `defender`      | ✅ complete |
| 5     | `terraform.auto.tfvars.json` bridge written by pre-provision hook (see `hooks/pre-provision.{sh,ps1}`)                                                                                                                                            | ✅ complete |
| 6     | Hooks — `hooks/pre-provision.{sh,ps1}`, `hooks/post-provision.{sh,ps1}`, shared helpers `hooks/_lib.{sh,ps1}`                                                                                                                                     | ✅ complete |
| 7     | State backend bootstrap — `scripts/bootstrap-tf-backend.{sh,ps1}`                                                                                                                                                                                 | ✅ complete |
| 8     | CI — `.github/workflows/terraform-smb-ready-foundation.yml` + `tests/scenarios.tftest.hcl` + `.tflint.hcl`                                                                                                                                        | ✅ complete |
| 9     | Teardown — `scripts/remove-smb-ready-foundation.sh`, `scripts/Remove-SmbReadyFoundation.ps1`                                                                                                                                                      | ✅ complete |
| 10    | Agent-track artifacts (`04-implementation-plan-terraform.md`, `05-implementation-reference-terraform.md`, `07-ab-adr-0005-terraform-dual-track.md`, `07-ab-adr-0006-terraform-child-module-composition.md`, `07-resource-inventory-terraform.md`) | ✅ complete |

## Quickstart

```bash
cd infra/terraform/smb-ready-foundation

# 1. Configure azd environment
azd env new smb-ready-foundation
azd env set OWNER you@example.com
azd env set AZURE_LOCATION swedencentral
azd env set SCENARIO baseline              # baseline | firewall | vpn | full
# For VPN scenarios also set:
# azd env set ON_PREMISES_ADDRESS_SPACE 192.168.0.0/16

# 2. Provision (pre-provision hook enables azd alpha.terraform, bootstraps
#    the state backend, writes terraform.auto.tfvars.json, and runs
#    terraform init -reconfigure).
azd provision

# 3. Teardown
./scripts/remove-smb-ready-foundation.sh            # prompts for confirmation
./scripts/remove-smb-ready-foundation.sh -y         # unattended
./scripts/remove-smb-ready-foundation.sh -y --delete-mg --delete-backend
```

## Validation

```bash
cd infra/terraform/smb-ready-foundation
terraform fmt -check -recursive       # ✅ passes
terraform init -backend=false         # ✅ passes
terraform validate                    # ✅ passes (3 cosmetic v5.0 deprecation warnings)
terraform test                        # ✅ passes — 6 scenario tests
```

Repo-wide:

```bash
npm run validate:terraform              # ✅ passes
npm run validate:iac-security-baseline  # ✅ passes — 44 files, 0 errors, 0 warnings
```

### Plan-mode test matrix

`tests/scenarios.tftest.hcl` runs the 4 feature-flag combinations plus
scenario-specific assertions (NAT vs firewall mutual exclusion, peering
gating, budget email fallback to owner, CAF naming). Uses `mock_provider` so
no Azure authentication is required.

## azd env → Terraform variable bridge

The pre-provision hook reads azd environment variables, validates them, and
writes `terraform.auto.tfvars.json` (auto-loaded by Terraform). This avoids
TF_VAR env propagation pitfalls and pins `budget_start_date` to the first of
the current month UTC so repeated applies do not drift the immutable start
date.

| azd env variable             | Terraform variable                | Default                |
| ---------------------------- | --------------------------------- | ---------------------- |
| `OWNER`                      | `owner`                           | auto-detected          |
| `AZURE_LOCATION`             | `location`                        | `swedencentral`        |
| `ENVIRONMENT`                | `environment`                     | `prod`                 |
| `HUB_VNET_ADDRESS_SPACE`     | `hub_vnet_address_space`          | `10.0.0.0/23`          |
| `SPOKE_VNET_ADDRESS_SPACE`   | `spoke_vnet_address_space`        | `10.0.2.0/23`          |
| `ON_PREMISES_ADDRESS_SPACE`  | `on_premises_address_space`       | `""` (required VPN)    |
| `LOG_ANALYTICS_DAILY_CAP_GB` | `log_analytics_daily_cap_gb`      | `0.5`                  |
| `BUDGET_AMOUNT`              | `budget_amount`                   | `100`                  |
| `BUDGET_ALERT_EMAIL`         | `budget_alert_email`              | falls back to owner    |
| `SCENARIO`                   | → `deploy_firewall`, `deploy_vpn` | `baseline`             |
| `DEPLOY_FIREWALL`            | `deploy_firewall`                 | scenario-derived       |
| `DEPLOY_VPN`                 | `deploy_vpn`                      | scenario-derived       |
| _(computed)_                 | `budget_start_date`               | first-of-month UTC     |
| _(computed)_                 | `subscription_id`                 | from `az account show` |

## AVM-TF decision

Phase 4 delivered all resources as raw `azurerm_*` / `azapi_resource`
resources instead of AVM-TF wrapper modules. Rationale:

1. **1:1 parity with Bicep.** Raw resources map directly to Bicep modules,
   simplifying review.
2. **No registry-init friction in CI.** Local references only.
3. **AVM-TF gap coverage.** Several resources (Azure Migrate, Defender
   pricings, consumption budget) have no AVM-TF equivalent anyway.

Moving select resources (KV, VNet, RSV, LAW, Automation Account) to AVM-TF
wrappers is a tracked follow-up; they carry no functional difference today.

## Security baseline

All resources enforce the repo security baseline:

- TLS 1.2 minimum (Key Vault, Storage)
- HTTPS-only on all services
- Public network access disabled for Key Vault + Automation Account
- Managed Identity for Automation Account and sub-scope policy
- RBAC auth on Key Vault (no access policies)
- Private endpoints for Key Vault (in `snet-pep`)
- NSG deny-all-inbound with explicit allow rules
- Soft delete enabled on Recovery Services Vault + Key Vault (90d retention,
  purge protection on KV)

## Note on MG policy count (30 vs. 33)

The Bicep source header and `output policyCount int = 30` in
`infra/bicep/smb-ready-foundation/modules/policy-assignments-mg.bicep` claim
"30 MG-scoped policies", but the file actually declares **33** policy
assignment resources. The Terraform port implements all 33 resources
faithfully and emits the actual count dynamically
(`output.policy_assignment_count`).

## Operational constraints

1. **Mutually exclusive deployments.** If Bicep and Terraform flavours target
   the same subscription simultaneously, globally-unique names (Key Vault,
   storage) collide. The `unique_suffix` in `locals.tf` intentionally matches
   Bicep's `uniqueString(subscription().subscriptionId)`. Treat the two
   flavours as alternatives per subscription, not as co-deployable.
2. **azd Terraform support is alpha.** The pre-provision hook runs
   `azd config set alpha.terraform on` (idempotent). Pin your local/CI
   `azd` version to a recent release with Terraform alpha support.
3. **Single shared state file.** MG, policy assignments, and all sub-scope
   resources share one state file (`smb-ready-foundation.tfstate`) in the
   backend bootstrapped under `rg-tfstate-smb-<region>`. All azd envs
   (`smb-rf-tf-firewall`, `smb-rf-tf-vpn`, `smb-rf-tf-full`) point at the
   same state so sub/tenant-scope resources (MG, Defender pricings, MG
   subscription association) persist across scenario teardowns — only
   RG-scoped resources cycle.
4. **Budget start date immutability.** Azure Consumption API cannot update a
   budget's `start_date` after creation. The pre-provision hook deletes any
   existing `budget-smb-monthly` before apply and pins the start date to the
   first of the current month UTC.
5. **Deprecated resources (non-blocking).** `azurerm_security_center_auto_provisioning`
   and `azurerm_recovery_services_vault.soft_delete_enabled` emit v5.0
   deprecation warnings. Behaviour is unchanged for azurerm 4.x.

## Repository layout

```text
infra/terraform/smb-ready-foundation/
├── azure.yaml                          # azd manifest (provider: terraform)
├── backend.tf                          # backend "azurerm" {} partial config
├── versions.tf, providers.tf           # Terraform + provider pins
├── variables.tf, locals.tf             # Input surface + derived values
├── main.tf                             # Module orchestration + root import block
├── outputs.tf                          # Wired to module outputs
├── modules/
│   ├── management-group/               # MG + subscription association
│   ├── policy-assignments-mg/          # 33 MG-scoped policy assignments
│   ├── resource-groups/                # 5 shared + 1 spoke RG
│   ├── network-hub/                    # Hub VNet, NSG, 4 subnets, shared PDZ
│   ├── network-spoke/                  # Spoke VNet, NSG, 4 subnets, optional NAT
│   ├── firewall/                       # Optional Azure Firewall
│   ├── route-tables/                   # Spoke UDRs → firewall
│   ├── vpn-gateway/                    # Optional S2S VPN gateway
│   ├── peering/                        # Hub-spoke peering (VPN-gated)
│   ├── monitoring/                     # Log Analytics workspace
│   ├── backup/                         # Recovery Services Vault + policy
│   ├── policy-backup-auto/             # Sub-scope DINE + role assignments
│   ├── migrate/                        # Azure Migrate project (azapi)
│   ├── keyvault/                       # KV + dedicated PDZ + PE + diag
│   ├── automation/                     # Automation Account + LAW link
│   ├── budget/                         # Consumption budget + 3 alerts
│   └── defender/                       # 4 Defender plans + auto-provisioning off
├── hooks/
│   ├── _lib.sh, _lib.ps1               # Shared helpers (CIDR, logging)
│   ├── pre-provision.sh, .ps1          # Validate, bootstrap backend, write tfvars
│   └── post-provision.sh, .ps1         # Outputs summary + next steps
├── scripts/
│   ├── bootstrap-tf-backend.sh, .ps1   # Idempotent backend provisioning
│   ├── remove-smb-ready-foundation.sh  # Teardown (bash)
│   └── Remove-SmbReadyFoundation.ps1   # Teardown (PowerShell)
└── tests/
    └── scenarios.tftest.hcl            # Plan-mode scenario matrix
```

## References

- Source of truth: `infra/bicep/smb-ready-foundation/`
- Terraform patterns: `.github/skills/terraform-patterns/SKILL.md`
- Style guide: `.github/instructions/iac-terraform-best-practices.instructions.md`
- CI workflow: `.github/workflows/terraform-smb-ready-foundation.yml`
