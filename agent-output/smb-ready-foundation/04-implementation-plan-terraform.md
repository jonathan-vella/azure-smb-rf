---
title: "Step 4: Implementation Plan - SMB Ready Foundations (Terraform)"
status: "Implemented"
date: "2026-04-17"
artifact_version: "1.0"
authors: "Terraform Code Agent, Partner Operations Team"
tags:
  ["implementation-plan", "terraform", "iac", "azure", "smb-ready-foundation"]
supersedes: ""
superseded_by: ""
companion: "04-implementation-plan.md"
---

# Step 4: Implementation Plan — SMB Ready Foundations (Terraform track)

> This plan is the **Terraform track** for the SMB Ready Foundations. It is a delta
> document — the authoritative Azure design, policies, scenario matrix, WAF analysis,
> and cost estimate live in [`04-implementation-plan.md`](./04-implementation-plan.md).
> Only items that diverge from the Bicep plan are captured here.

## Scope

- Deliver a Terraform Infrastructure as Code variant of the SMB Ready Foundations that
  is functionally equivalent to the Bicep track (`infra/bicep/smb-ready-foundation/`).
- Preserve all CAF naming, required tags, scenario matrix (baseline / firewall / vpn /
  full), governance (33 MG policies + 1 sub-scope policy), and security baseline.
- Ship alongside the Bicep track (dual-track), not replace it.

## Out of scope

- Any change to the SMB Ready Foundations architecture, WAF pillar scoring, cost envelope,
  or policy inventory. Those decisions remain governed by `04-implementation-plan.md`.
- Parallel Bicep/Terraform deployment into the same subscription — see ADR-0005 for the
  mutual-exclusion rationale.

## Architectural delta vs. Bicep

| Area                      | Bicep                                         | Terraform                                                                         |
| ------------------------- | --------------------------------------------- | --------------------------------------------------------------------------------- |
| Deployment scopes         | Two templates: `deploy-mg.bicep` (management  | Single root composes MG + subscription scopes (see ADR-0006).                     |
|                           | group) + `main.bicep` (subscription)          |                                                                                   |
| Scope split orchestration | `preprovision` hook runs `deploy-mg.bicep`,   | Single `azd provision` → `terraform apply`. MG + policies +                       |
|                           | then `azd provision` runs `main.bicep`        | sub-scope resources in one graph.                                                 |
| Module system             | `modules/*.bicep`                             | Root-level topical `.tf` files (no child `modules/` dir).                         |
| AVM posture               | AVM-first mandatory                           | Raw `azurerm_*` / `azapi_resource` (see "AVM-TF decision" below).                 |
| Unique suffix             | `uniqueString(subscription().subscriptionId)` | `substr(sha1(data.azurerm_subscription.current.subscription_id), 0, 13)`          |
| Budget start date         | `utcNow('yyyy-MM-01')` at param default       | Injected by pre-provision hook (`budget_start_date`) pinned to first-of-month UTC |
| `ManagedBy` tag           | `"Bicep"`                                     | `"Terraform"` (intentional provenance divergence)                                 |

## AVM-TF decision (single pass)

Phase 4 evaluated the AVM-TF registry for each Bicep-AVM module used in the Bicep track:

- **Used AVM-TF?** No — all resources are raw `azurerm_*` / `azapi_resource`.
- **Rationale**:
  1. 1:1 parity with Bicep source simplifies review.
  2. No registry-init friction in CI (local references only).
  3. Several required resources have no AVM-TF equivalent (Azure Migrate project,
     Defender for Cloud pricing, Consumption budget, sub-scope policy assignment).
- **Follow-up**: Moving KV, VNet, RSV, LAW, Automation to AVM-TF wrappers is tracked as
  a future refactor; no functional difference today. See ADR-0005 and README.

## Provider + version pins

| Component | Pin      | Rationale                                                            |
| --------- | -------- | -------------------------------------------------------------------- |
| terraform | `>= 1.9` | Required for `import` block + `mock_provider` / `override_resource`. |
| azurerm   | `~> 4.0` | 4.x is current LTS-equivalent; `~>` allows 4.x minor upgrades.       |
| azapi     | `~> 2.0` | Needed for `Microsoft.Migrate/migrateProjects` (no azurerm support). |
| random    | `~> 3.6` | Available for future SKU suffixing; not currently used.              |
| null      | `~> 3.2` | Required by `terraform_data` relay pattern (see peering).            |

## File layout

```text
infra/terraform/smb-ready-foundation/
├── azure.yaml                          # azd manifest (provider: terraform)
├── backend.tf                          # backend "azurerm" {} partial config
├── versions.tf, providers.tf           # Terraform + provider pins
├── variables.tf, locals.tf             # Input surface + derived values
├── main.tf                             # Module orchestration + root import block
├── outputs.tf                          # Wired to module outputs
├── modules/                            # 17 child modules (one per concern)
│   ├── management-group/               # MG + subscription association
│   ├── policy-assignments-mg/          # 33 MG-scoped policy assignments
│   ├── resource-groups/                # 5 shared + 1 spoke RG
│   ├── network-hub/                    # Hub VNet, NSG, 4 subnets, shared PDZ
│   ├── network-spoke/                  # Spoke VNet, NSG, 4 subnets, optional NAT
│   ├── firewall/, route-tables/        # Optional firewall + spoke UDRs
│   ├── vpn-gateway/, peering/          # Optional VPN + hub-spoke peering (VPN-gated)
│   ├── monitoring/, backup/            # LAW + RSV
│   ├── policy-backup-auto/             # Sub-scope DINE + role assignments
│   ├── migrate/, keyvault/, automation/
│   └── budget/, defender/
├── hooks/                              # pre/post-provision (bash + PowerShell)
├── scripts/                            # bootstrap-tf-backend + remove
└── tests/
    └── scenarios.tftest.hcl            # Plan-mode scenario matrix
```

## Deployment flow

```text
azd provision
  ├─ hooks/pre-provision.{sh,ps1}
  │    1. Validate OWNER, CIDRs (hub/spoke/on-prem overlap)
  │    2. Azure preflight (auth, required RP registration)
  │    3. azd config set alpha.terraform on
  │    4. scripts/bootstrap-tf-backend.{sh,ps1} (RG + SA + container + backend.hcl)
  │    5. Write terraform.auto.tfvars.json (incl. budget_start_date)
  │    6. Delete stale budget-smb-monthly (start_date immutable)
  │    7. Clean faulted firewall / VPN gateway from prior failed runs
  │    8. terraform init -reconfigure -backend-config=<backend.hcl>
  ├─ terraform apply
  │    - MG + subscription association (with `import` block for idempotency)
  │    - 33 MG-scoped policy assignments
  │    - 6 resource groups
  │    - Budget (sub scope), Defender pricings (sub scope)
  │    - Hub/spoke VNets, NSGs, subnets, shared private DNS zone
  │    - Conditional: NAT gateway (when firewall=false) OR firewall + route tables
  │    - Conditional: VPN gateway (serialised after firewall via depends_on)
  │    - Conditional: hub-spoke peering (when firewall OR vpn)
  │    - LAW, RSV + DefaultVMPolicy, policy-backup-auto (DINE + 2 role assignments)
  │    - Migrate project (azapi), Key Vault + PE + diag, Automation Account + LAW link
  └─ hooks/post-provision.{sh,ps1}
       - Terraform outputs summary
       - Next-steps guidance
```

## Operational constraints

1. **Mutual exclusion with Bicep.** The `unique_suffix` intentionally collides with
   Bicep's `uniqueString()`; both flavours cannot target the same subscription
   simultaneously. Choose one per subscription. See ADR-0005.
2. **azd Terraform is alpha.** The pre-provision hook runs `azd config set alpha.terraform on`
   idempotently. Pin `azd` version in CI once GA lands.
3. **Single state file.** MG, policy assignments, sub-scope resources all live in
   `smb-ready-foundation.tfstate` stored in the bootstrapped backend
   (`rg-tfstate-smb-<region>`, `sttfstatesmb<hash>`, container `tfstate`).
4. **Budget start date immutability.** Azure Consumption API cannot update a budget's
   `start_date` after creation. The pre-provision hook deletes any existing
   `budget-smb-monthly` before apply and pins the start date to the first of the
   current month UTC.
5. **Dual-OS hooks.** Both bash (`.sh`) and PowerShell (`.ps1`) variants are provided,
   wired via `azure.yaml` `posix:` / `windows:` entries.

## Testing strategy

Plan-mode Terraform tests in `tests/scenarios.tftest.hcl` use `mock_provider` +
`mock_data` + `override_resource` (required for the MG `import` block). Six passing
assertions cover:

1. `baseline_scenario` — no FW, no VPN, NAT on, peering off
2. `firewall_scenario` — FW on, NAT off (mutual exclusion), peering on
3. `vpn_scenario` — VPN on, peering on, on-prem CIDR required
4. `full_scenario` — FW + VPN, NAT off
5. `budget_email_defaults_to_owner` — fallback when `budget_alert_email` blank
6. `rg_names_match_caf` — hub/spoke naming uses CAF + `smb` vs. env environment split

CI (`.github/workflows/terraform-smb-ready-foundation.yml`) runs:

- `terraform fmt -check -recursive`
- `terraform init -backend=false`
- `terraform validate`
- `tflint` (with `.tflint.hcl`)
- `terraform test`

No live Azure authentication is required for CI.

## Governance compliance

All 33 MG-scoped policies from `04-implementation-plan.md` are reimplemented in
`modules/policy-assignments-mg/main.tf` with equivalent parameters:

- 22 policies use a uniform `{ effect: Deny }` pattern (assembled in a `uniform_policy_assignments` local)
- 6 Key Vault policies use `{ effect: Audit }`
- 5 policies require custom parameter arrays (allowed SKUs, allowed locations,
  required tag values, diagnostic destinations) — declared explicitly

All policy assignments use `enforce = true` (Terraform equivalent of Bicep's
`enforcementMode: 'Default'`). The sub-scope DINE policy (`smb-backup-02`) has a
SystemAssigned identity + Backup Contributor + Virtual Machine Contributor role
assignments mirroring `policy-backup-auto.bicep`.

## References

- Bicep plan: [`04-implementation-plan.md`](./04-implementation-plan.md)
- Bicep code reference: [`05-implementation-reference.md`](./05-implementation-reference.md)
- Terraform code reference: [`05-implementation-reference-terraform.md`](./05-implementation-reference-terraform.md)
- Dual-track ADR: [`07-ab-adr-0005-terraform-dual-track.md`](./07-ab-adr-0005-terraform-dual-track.md)
- Scope composition ADR: [`07-ab-adr-0006-terraform-single-root-composition.md`](./07-ab-adr-0006-terraform-single-root-composition.md)
- Resource inventory: [`07-resource-inventory-terraform.md`](./07-resource-inventory-terraform.md)
