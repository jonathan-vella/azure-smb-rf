# As-Built: Terraform port of smb-ready-foundation

Port of the Bicep IaC at `infra/bicep/smb-ready-foundation/` to Terraform at
`infra/terraform/smb-ready-foundation/`, preserving functional and structural
parity with the Bicep flavour (resources, tags, names, outputs, scenarios,
policies).

**This document describes what was actually built**, replacing the original
forward-looking plan. Deltas vs. the original plan are called out inline under
"Deviations from original plan".

Deploy tool: `azd up` with `infra.provider: terraform` (alpha — requires
`azd config set alpha.terraform on`). Bash-only hooks. Terraform-native guards
(`variable.validation`, `precondition`) layered on top of hook logic.

## Key decisions (as-built)

- **Single-root composition** — MG bootstrap is a child module inside the main
  root, not a separate root. Adoption of a pre-existing MG is handled with a
  root-level `import` block targeting
  `module.management_group.azurerm_management_group.smb_rf`.
  See ADR-0006 (`07-ab-adr-0006-terraform-single-root-composition.md`).
- **Raw `azurerm_*` throughout** — AVM-TF modules were evaluated and not used
  for this project. Every resource is a direct `azurerm_*` or `azapi_resource`
  call. Rationale in ADR-0005 (`07-ab-adr-0005-terraform-dual-track.md`).
  `azapi_resource` is used only for Azure Migrate
  (`Microsoft.Migrate/migrateProjects@2020-05-01`), where no azurerm coverage
  exists.
- **Scenarios via per-feature booleans** — `deploy_firewall` (bool),
  `deploy_vpn` (bool). No `scenario` input variable; a derived
  `local.scenario` is computed for human labeling and outputs.
- **Bash-only hooks** — PowerShell hooks were not needed for the target
  partner UX (devcontainer-first). Single hook implementation keeps drift risk
  low. The original plan called for dual PS+Bash; this was simplified.
- **Backend**: azurerm only. No runtime `TF_BACKEND=local` switch. State lives
  in `sttfstatesmb<suffix>` / `rg-tfstate-smb-swc` / `tfstate` container, key
  `smb-ready-foundation.tfstate`. Bootstrap via
  `scripts/bootstrap-tf-backend.sh`.
- **Single MG initiative + 1 sub-scoped DINE policy**. All 33 baseline
  policies are consolidated into one custom Policy Set Definition
  (`smb-baseline`) with one initiative assignment at MG scope. The DINE
  backup policy (`smb-backup-02`) stays sub-scoped because it needs a
  subscription-scoped managed identity with role assignments.
- **`ManagedBy = "Terraform"`** — tag value diverges from Bicep's `"Bicep"` by
  design so deployed resources carry accurate provenance. Globally-unique
  names (Key Vault) still collide across flavours on the same subscription;
  documented as mutually-exclusive per subscription in the module README.
- **Agent artifacts created** (alongside existing Bicep artifacts, not
  replacing): `04-implementation-plan-terraform.md`,
  `05-implementation-reference-terraform.md`, ADR-0005, ADR-0006,
  `07-resource-inventory-terraform.md`.
- **CI**: `.github/workflows/terraform-smb-ready-foundation.yml` runs fmt
  check, `init -backend=false`, validate, and tflint on PR. No e2e matrix job
  yet. `.tftest.hcl` coverage is a single `tests/scenarios.tftest.hcl` file,
  not per-module.

## Repository layout (as-built)

```text
infra/terraform/smb-ready-foundation/
  versions.tf               # terraform >= 1.9, azurerm ~> 4.0, azapi ~> 2.0, random ~> 3.6, null ~> 3.2
  providers.tf              # azurerm (features {}), azapi, data sources
  backend.tf                # backend "azurerm" {} — partial config via provider.conf.json
  variables.tf              # all inputs with validation blocks
  locals.tf                 # region map, unique_suffix, scenario derivation, rg_names, tag maps
  main.tf                   # root composition + import block for pre-existing MG
  outputs.tf                # scenario, rg names, vnet ids, kv name, law id, budget/defender summaries
  azure.yaml                # azd manifest: infra.provider=terraform, infra.path=., posix hooks only
  terraform.tfvars.example  # documented variable combinations
  terraform.auto.tfvars.json # written by pre-provision hook from azd env
  provider.conf.json        # written by pre-provision hook from backend.hcl (azd alpha.terraform requirement)
  main.tfvars.json          # empty {} placeholder (azd alpha.terraform requirement)
  hooks/
    _lib.sh                 # shared helpers (log, CIDR, scenario→booleans)
    pre-provision.sh        # 9 steps incl. backend bootstrap, provider.conf.json write, tf init
    post-provision.sh       # print scenario summary + outputs
    _lib.ps1                # retained but unused (cross-platform compat placeholder)
    pre-provision.ps1       # retained but unused
    post-provision.ps1      # retained but unused
  scripts/
    bootstrap-tf-backend.sh # idempotent SA + RG create; writes .azure/<env>/backend.hcl
    bootstrap-tf-backend.ps1
    remove-smb-ready-foundation.sh
    Remove-SmbReadyFoundation.ps1
  tests/
    scenarios.tftest.hcl    # 4 plan-mode runs: baseline, firewall, vpn, full
  modules/
    management-group/       # azurerm_management_group (no parent_management_group_id → tenant root)
    policy-assignments-mg/  # Initiative (33 policies) + 1 assignment
    resource-groups/        # 6 RGs: hub, spoke, monitor, backup, migrate, security
    defender/               # azurerm_security_center_subscription_pricing × N (tier=Free/Standard)
    budget/                 # azurerm_consumption_budget_subscription with 3 notifications
    network-hub/            # VNet + NSG + 4 subnets (+ shared PDZ) + diag settings on VNet/NSG
    network-spoke/          # VNet + NSG + 4 subnets + optional NAT gateway + diag settings
    firewall/               # PIP×2 + firewall policy + rule collection groups + firewall + diag setting (conditional)
    route-tables/           # route tables + UDRs + subnet associations (conditional on deploy_firewall)
    vpn-gateway/            # PIP + VPN gateway (conditional on deploy_vpn, serialised after firewall)
    peering/                # hub↔spoke peering + terraform_data VPN-ready relay
    monitoring/             # Log Analytics workspace (PerGB2018, 30-day retention, daily_quota_gb)
    backup/                 # Recovery Services Vault + DefaultVMPolicy + diag setting
    policy-backup-auto/     # sub-scope DINE policy + 2 role assignments (Backup Contrib, VM Contrib)
    migrate/                # azapi_resource Microsoft.Migrate/migrateProjects with schema_validation_enabled=false
    keyvault/               # KV (RBAC, purge protect, PNA=false) + PDZ + PE + diag setting
    automation/             # Automation Account (PNA=false) + LAW linked service + diag setting
```

## Resource vs. policy compliance map

The foundation is deployed **first-time-right compliant** — no audit drift on
`terraform apply`, no DeployIfNotExists remediation rewriting TF-managed state.

| Policy                                                                         | Effect            | Compliance mechanism in TF                                                                                                                                                                     |
| ------------------------------------------------------------------------------ | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `smb-tagging-01/02` (Environment, Owner required)                              | Deny              | `local.shared_services_tags` / `local.spoke_tags` applied to every taggable resource                                                                                                           |
| `smb-governance-01` (allowed locations)                                        | Deny              | All modules use `var.location` = `swedencentral`                                                                                                                                               |
| `smb-storage-01/02/03` (HTTPS, no public blob, TLS 1.2)                        | Deny              | No storage accounts deployed in this foundation                                                                                                                                                |
| `smb-kv-01..06` (soft delete, purge protect, RBAC, no public net, expirations) | Audit             | KV module: `soft_delete_retention_days=90`, `purge_protection_enabled=true`, `enable_rbac_authorization=true`, `public_network_access_enabled=false`, `network_acls { default_action="Deny" }` |
| `smb-kv-07` (resource logs)                                                    | Audit             | `azurerm_monitor_diagnostic_setting.kv` → LAW                                                                                                                                                  |
| `smb-monitoring-01` (diagnostic settings)                                      | AuditIfNotExists  | Diag settings on: KV, Automation Account, hub VNet, hub NSG, spoke VNet, spoke NSG, Firewall (conditional), Recovery Services Vault. All → LAW.                                                |
| `smb-backup-02` (auto-backup VMs tagged `Backup:true`)                         | DeployIfNotExists | Sub-scope assignment in `policy-backup-auto` module; **no VMs deployed by this foundation**, so no state drift possible                                                                        |
| `smb-network-01..05` (NSG on subnets, close mgmt ports, flow logs, etc.)       | Audit             | Hub/spoke NSGs attached to non-reserved subnets; default deny-all rule                                                                                                                         |
| `smb-compute-01..06` (allowed SKUs, no public IPs on NICs, etc.)               | Deny/Audit        | No VMs/NICs deployed by this foundation                                                                                                                                                        |

**This session's tightening**: added `log_analytics_workspace_id` variable to
`network-hub`, `network-spoke`, `firewall`, `backup` modules and wired diag
settings on hub VNet, hub NSG, spoke VNet, spoke NSG, Azure Firewall,
Recovery Services Vault. Previously only KV + Automation Account had diag
settings. This closes the `smb-monitoring-01` audit gap at apply time.

## Variables (as-built, `variables.tf`)

| Variable                        | Type         | Default                                           | Validation                          |
| ------------------------------- | ------------ | ------------------------------------------------- | ----------------------------------- |
| `subscription_id`               | string       | —                                                 | GUID format                         |
| `location`                      | string       | `"swedencentral"`                                 | `swedencentral\|germanywestcentral` |
| `environment`                   | string       | `"prod"`                                          | `dev\|staging\|prod`                |
| `owner`                         | string       | —                                                 | non-empty                           |
| `deploy_firewall`               | bool         | `false`                                           | —                                   |
| `deploy_vpn`                    | bool         | `false`                                           | —                                   |
| `management_group_name`         | string       | `"smb-rf"`                                        | —                                   |
| `management_group_display_name` | string       | `"SMB Ready Foundation"`                          | —                                   |
| `assignment_location`           | string       | `"swedencentral"`                                 | —                                   |
| `allowed_vm_skus`               | list(string) | 33 SKUs                                           | non-empty                           |
| `allowed_locations`             | list(string) | `["swedencentral","germanywestcentral","global"]` | non-empty                           |
| `hub_vnet_address_space`        | string       | `"10.0.0.0/23"`                                   | CIDR regex                          |
| `spoke_vnet_address_space`      | string       | `"10.0.2.0/23"`                                   | CIDR regex                          |
| `on_premises_address_space`     | string       | `""`                                              | CIDR regex or empty                 |
| `log_analytics_daily_cap_gb`    | number       | `0.5`                                             | `> 0`                               |
| `budget_amount`                 | number       | `100`                                             | `100 <= x <= 10000`                 |
| `budget_alert_email`            | string       | `""` (falls back to `owner`)                      | —                                   |
| `budget_start_date`             | string       | — (hook-injected)                                 | `YYYY-MM-01` regex                  |

azd → TF_VAR bridge: the pre-provision hook writes
`terraform.auto.tfvars.json` from azd env vars so partners only need
`azd env set SCENARIO / OWNER / …`.

## Management Group idempotency (as-built)

```hcl
# main.tf
module "management_group" {
  source = "./modules/management-group"
  name            = var.management_group_name
  display_name    = var.management_group_display_name
  subscription_id = var.subscription_id
}

import {
  to = module.management_group.azurerm_management_group.smb_rf
  id = "/providers/Microsoft.Management/managementGroups/${var.management_group_name}"
}
```

Root-level `import` adopts a pre-existing MG (created either by the
`scripts/test-scenarios-tf.sh` pre-flight via `az account management-group create`
or by a prior Bicep deployment). Falls back to create on first apply if the MG
doesn't exist. The MG is placed under the tenant root (no
`parent_management_group_id`).

## Policy assignments (as-built, `modules/policy-assignments-mg/main.tf`)

Consolidated into a single custom initiative. Two Azure Policy resources at
MG scope, one assignment at sub scope.

| Block                                                                          | Count | Approach                                                                                                                                 |
| ------------------------------------------------------------------------------ | ----- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `azurerm_management_group_policy_set_definition.smb_baseline`                  | 1     | Custom Policy Set (initiative) aggregating 33 built-in policy definitions                                                                |
| ↳ uniform `policy_definition_reference` blocks                                 | 22    | `dynamic` over `local.uniform_refs` map, no parameters                                                                                   |
| ↳ Key Vault audit references                                                   | 6     | `dynamic` over `local.kv_audit_refs` map with `effect = Audit` param                                                                     |
| ↳ parameterised references                                                     | 5     | Explicit blocks for compute-01 (VM SKUs), tagging-01/02 (tagName), governance-01 (allowedLocations), monitoring-01 (listOfResourceTypes) |
| `azurerm_management_group_policy_assignment.smb_baseline`                      | 1     | Single initiative assignment with 2 top-level params (`allowedLocations`, `allowedVmSkus`) sourced from variables                        |
| **Total MG-scoped assignments**                                                | **1** | Down from 33 discrete assignments                                                                                                        |
| `azurerm_subscription_policy_assignment.backup_auto` (in `policy-backup-auto`) | 1     | Sub-scope DINE with SystemAssigned identity + 2 role assignments (cannot live in the initiative because of scope)                        |

### Why an initiative?

- **Atomic lifecycle** — all 33 policies enable/disable/version together.
- **Faster destroy** — 2 MG objects instead of 34 to delete; avoids the
  partial-teardown leftover-policy problem observed with per-policy
  assignments.
- **Simpler compliance reporting** — one initiative compliance score in
  Azure Policy blade.
- **Versioning** — the initiative carries a `version` metadata field; bumping
  it triggers a single assignment refresh instead of 33 separate updates.

### Initiative parameters

The initiative exposes only the two parameters that legitimately vary per
landing zone:

- `allowedLocations` (Array) — wired to `var.allowed_locations`
- `allowedVmSkus` (Array) — wired to `var.allowed_vm_skus`

Everything else (tagNames, resource-type lists, Audit effect on KV policies)
is hard-coded at the reference level for determinism.

### Reference-id stability

Each `policy_definition_reference.reference_id` matches the previous
assignment name (`smb-compute-01`, `smb-tagging-02`, etc.) so compliance
reports, dashboards, and exemptions keyed to those identifiers continue to
work without remapping.

## Hooks (as-built, Bash-only)

`hooks/pre-provision.sh` steps:

1. Parameter validation (OWNER auto-detect, CIDR overlap)
2. Azure preflight (`az account show`, required RP registration)
3. Enable `azd config set alpha.terraform on` (idempotent)
4. Bootstrap backend (calls `scripts/bootstrap-tf-backend.sh` — creates
   `rg-tfstate-smb-<regionShort>`, SA `sttfstatesmb<suffix>`, container
   `tfstate`; writes `.azure/<env>/backend.hcl`)
5. Write `terraform.auto.tfvars.json` from azd env (incl.
   `budget_start_date = $(date -u +%Y-%m-01)` to avoid `timestamp()` drift)
6. Delete stale budget with the same name (Azure API cannot update
   `start_date` post-creation)
7. Clean faulted firewall / VPN Gateway public IPs from prior failed runs
8. **Write `provider.conf.json`** by awk-parsing `backend.hcl` — required by
   azd alpha.terraform to inject backend config into `terraform init`. Also
   writes empty `main.tfvars.json` placeholder.
9. `terraform init -reconfigure`

`hooks/post-provision.sh`:

- Parse `terraform output -json`, print scenario summary, budget, Defender
  pricings, next steps.

**No retry loop on apply failures** — original plan called for a 9-pattern
retry (mirroring Bicep); not implemented. Failed `azd provision` → operator
reruns.

## Scenario orchestration

`scripts/test-scenarios-tf.sh` (mirror of Bicep's `test-scenarios.sh`):

- Pre-flight: detect existing `.azure/smb-rf-tf-*` env dirs and tear each
  down.
- For each scenario in `(firewall vpn full)`:
  1. Pre-create MG (idempotent) via `az account management-group create`
  2. `azd env select/new "smb-rf-tf-${scenario}"`
  3. `azd env set` for SCENARIO, OWNER, AZURE_LOCATION,
     AZURE_SUBSCRIPTION_ID, ENVIRONMENT, HUB/SPOKE/ON-PREM CIDRs, LAW cap
  4. `azd up --no-prompt` (with one 60s-sleep retry)
  5. Validate (9 checks incl. `terraform state list | wc -l > 0`)
  6. `azd down --force --purge` + fallback `az group delete --no-wait`

## Destroy ordering fragility (known issue)

`azd down` → `terraform destroy` can abort mid-graph when subnet dependencies
(NSG/route-table associations, private endpoints) are not removed in the
right order. Observed failures:

- `Error: deleting Subnet … performing Delete: 404 Not Found` — VNet already
  deleted by a parallel destroy branch, subnet delete fails.
- `Error: deleting Rule Collection Group … 404 Not Found` — firewall policy
  already deleted.

These are **cosmetic** once the destroy has progressed far enough (Azure GCs
the subnets with the VNet), but Terraform exits non-zero, leaving orphaned
state entries. Recovery: `az group delete` any leftover RGs, drop the state
blob, re-run.

Not currently mitigated in TF config. Candidate mitigations (not implemented):

- `lifecycle { create_before_destroy = true }` on subnet/NSG associations
- Pre-destroy `terraform state rm` for problem resource types
- Explicit `depends_on` chains that force association deletes before VNet
  delete

## CI / validation (as-built)

- `.github/workflows/terraform-smb-ready-foundation.yml` — fmt check, init
  (`-backend=false`), validate, tflint on paths under
  `infra/terraform/smb-ready-foundation/**`
- `scripts/validate-terraform.mjs` (invoked via `npm run validate:terraform`)
  iterates every `infra/terraform/*/` root
- `scripts/diff-based-push-check.sh` runs fmt/validate/tflint on changed TF
  roots pre-push
- `scripts/validate-iac-security-baseline.mjs` covers TF paths
- `tests/scenarios.tftest.hcl` — 4 plan-mode runs (baseline, firewall, vpn,
  full) with mocked provider
- **No e2e apply matrix** — original plan called for 4-scenario OIDC
  federated apply/destroy. Local runner (`scripts/test-scenarios-tf.sh`)
  serves this purpose.

## Verification

1. `terraform fmt -check -recursive infra/terraform/` passes
2. `cd infra/terraform/smb-ready-foundation && terraform init -backend=false && terraform validate` passes
3. `tflint --init && tflint` passes
4. `npm run validate:terraform` passes
5. `npm run validate:iac-security-baseline` passes on TF paths
6. `terraform test -test-directory=tests` — 4 scenario plans succeed
7. `scripts/test-scenarios-tf.sh` — deploys firewall, vpn, full end-to-end
8. MG-scoped assignment count = **1** (`smb-baseline` initiative aggregating **33** policies). Verify via:
   - `az policy assignment list --scope /providers/Microsoft.Management/managementGroups/smb-rf --query "[?name=='smb-baseline']"`
   - `az policy set-definition show --name smb-baseline --management-group smb-rf` — `length(policyDefinitions)` = **33**
9. `az policy assignment list --query "length([?starts_with(name, 'smb-')])" -o tsv` (sub scope) = **1** (auto-backup DINE)
10. Deployed resource tags (`Environment`, `Owner`, `Project`, `ManagedBy=Terraform`) match
11. `azd down` + teardown script leaves no orphans (KV purged, no orphaned role assignments, no leftover PIPs)

## Deviations from original plan

| Original plan                                                    | As-built                                             | Reason                                                         |
| ---------------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------- |
| Two roots (`smb-ready-foundation/` + `smb-ready-foundation-mg/`) | Single root with MG as child module + `import` block | Simpler dependency graph; ADR-0006                             |
| AVM-TF for every module with a mature equivalent                 | Raw `azurerm_*` + `azapi` for Migrate                | AVM-TF maturity insufficient; ADR-0005                         |
| 30 MG-scoped + 3 sub-scoped policies                             | 1 MG initiative (33 policies) + 1 sub-scoped DINE    | Atomic lifecycle, faster destroy, simpler compliance reporting |
| Dual PowerShell + Bash hooks                                     | Bash only                                            | Devcontainer-first partner UX                                  |
| Dual state backend (azurerm/local switchable)                    | azurerm only                                         | Local backend adds surface area with no partner ask            |
| Per-module `.tftest.hcl`                                         | Single `tests/scenarios.tftest.hcl` with 4 runs      | Plan-mode scenario coverage catches same error class cheaper   |
| 9-pattern retry loop in post-provision                           | No retry loop                                        | Operator-driven rerun; state is idempotent                     |
| E2E OIDC matrix in CI                                            | Local `test-scenarios-tf.sh`                         | CI cost; manual runs suffice for the partner UX                |
| `policy-assignments.bicep` (legacy, unreferenced) port           | Not ported                                           | Confirmed unreferenced in Bicep main                           |

## Residual risks

1. **Shared-subscription naming collisions** — if Bicep and TF deployments
   ever target the same subscription simultaneously, globally-unique names
   (Key Vault) collide. Documented as mutually-exclusive per subscription.
2. **Destroy ordering** — see "Destroy ordering fragility" above.
3. **DeployIfNotExists drift from `smb-backup-02`** — the policy targets VMs,
   which this foundation does not deploy. When partner workloads add tagged
   VMs, backups will be created outside Terraform state by design (that's
   the policy's job). Partner workload IaC should be aware.
4. **azd alpha.terraform churn** — provider is alpha; field names and
   required files (`provider.conf.json`, `main.tfvars.json`) may change
   between azd versions. Pre-provision hook handles current requirements;
   revisit when azd promotes TF to beta/GA.
5. **azapi Migrate schema drift** — `schema_validation_enabled = false` was
   required because the embedded schema for
   `Microsoft.Migrate/migrateProjects@2020-05-01` lacks the `tags` field.
   When azapi ships an updated schema, remove the flag.

## Reference files

- `infra/bicep/smb-ready-foundation/main.bicep` — orchestration source of truth
- `infra/bicep/smb-ready-foundation/modules/*.bicep` — per-module parity target
- `agent-output/smb-ready-foundation/07-ab-adr-0005-terraform-dual-track.md`
- `agent-output/smb-ready-foundation/07-ab-adr-0006-terraform-single-root-composition.md`
- `agent-output/smb-ready-foundation/04-implementation-plan-terraform.md`
- `agent-output/smb-ready-foundation/05-implementation-reference-terraform.md`
- `agent-output/smb-ready-foundation/07-resource-inventory-terraform.md`
- `.github/instructions/iac-terraform-best-practices.instructions.md`
- `AGENTS.md` — repo conventions (naming, tags, provider pins)
