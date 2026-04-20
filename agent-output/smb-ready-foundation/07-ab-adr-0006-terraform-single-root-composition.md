---
title: "ADR-0006: Terraform Single-Root Composition with Child Modules"
status: "Implemented"
date: "2026-04-17"
artifact_version: "1.1"
authors: "Terraform Code Agent"
tags:
  [
    "architecture",
    "decision",
    "terraform",
    "management-group",
    "scopes",
    "iac",
    "modules",
  ]
supersedes: ""
superseded_by: ""
---

# ADR-0006: Terraform Single-Root Composition with Child Modules

## Status

**Implemented** — `infra/terraform/smb-ready-foundation/` is a single Terraform root
that composes management-group, subscription, and resource-group scope resources in
one `apply` via 17 child modules under `modules/`.

## Context

Bicep's SMB Ready Foundation is delivered as two separate templates:

- `deploy-mg.bicep` (`targetScope = 'managementGroup'`) — MG creation + 33 policy
  assignments.
- `main.bicep` (`targetScope = 'subscription'`) — everything else.

This is a **forced** split: a Bicep template can only have one `targetScope`, and MG-scope
assignments are illegal from a subscription-scope template (and vice versa).

Terraform has no such restriction. A single root can declare `azurerm_management_group`,
`azurerm_management_group_policy_assignment`, `azurerm_subscription_policy_assignment`,
and `azurerm_resource_group` resources in the same file set. Providers route operations
to the correct scope automatically.

The question for the Terraform track: **keep the two-step split for symmetry with Bicep,
or collapse into a single root?**

## Decision

**Collapse into a single root, organise by child modules.** Management group, policy
assignments, and sub-scope resources all live in one Terraform root with one state
file. Within that root, each topical concern is a child module under `modules/`
(17 modules: `management-group`, `policy-assignments-mg`, `resource-groups`,
`network-hub`, `network-spoke`, `firewall`, `route-tables`, `vpn-gateway`, `peering`,
`monitoring`, `backup`, `policy-backup-auto`, `migrate`, `keyvault`, `automation`,
`budget`, `defender`).

### Structure

```text
infra/terraform/smb-ready-foundation/
├── main.tf                      # Module orchestration + root-level import block
├── outputs.tf                   # Wired to module outputs
├── variables.tf, locals.tf
├── versions.tf, providers.tf, backend.tf
└── modules/
    ├── management-group/        # MG + subscription association
    ├── policy-assignments-mg/   # 33 MG-scoped policy assignments
    ├── resource-groups/         # 5 shared + 1 spoke RG
    ├── network-hub/, network-spoke/
    ├── firewall/, route-tables/, vpn-gateway/, peering/
    ├── monitoring/, backup/, policy-backup-auto/
    ├── migrate/, keyvault/, automation/
    └── budget/, defender/
```

The root-level `import` block adopts a pre-existing management group into
`module.management_group.azurerm_management_group.smb_rf` (import blocks are only
valid in the root module, not in child modules).

### Dependency ordering

Terraform's resource graph orders operations automatically via references. Explicit
`depends_on` is used only for dependencies invisible to the graph:

1. Sub-scope resources that must wait for the MG subscription association declare
   `depends_on = [module.management_group.subscription_association_id]` via the
   module's output dependency graph.
2. `module.vpn_gateway` takes a `firewall_serialisation_sentinel` input wired to
   `module.firewall.id` (or empty string when disabled) to serialise subnet-touching
   operations on the hub VNet (prevents `Another operation is in progress on the
VNet` conflicts during parallel apply).
3. `module.peering` takes a `vpn_gateway_id` input driving a `terraform_data.vpn_ready`
   relay inside the module — carries the VPN gateway id only when
   `var.deploy_vpn = true`. This makes `allow_gateway_transit` /
   `use_remote_gateways` settings safe even though the gateway count is unknown at
   plan time for disabled scenarios.

## Consequences

### Positive

- **One `apply` = one provision.** No orchestration layer coordinating two templates,
  no hook-runs-template-A-then-template-B pattern. The azd pre-provision hook only
  bootstraps the backend and writes tfvars; `terraform apply` does the rest.
- **Single state file.** MG, policies, and sub-scope resources are reconciled together.
  A single `terraform destroy` tears the whole stack down (including the MG, via a
  `removed` block path or the teardown script's explicit MG delete).
- **Simpler idempotency.** The `import` block on `azurerm_management_group.smb_rf`
  covers the case where the MG already exists (e.g., created by a prior Bicep run),
  without requiring a separate "create-or-import" dance in a hook.
- **Fewer moving parts in CI.** Plan-mode `terraform test` exercises the whole graph;
  no need to mock two distinct template invocations.

### Negative

- **Larger blast radius.** A malformed policy assignment anywhere in the root blocks
  `apply` on the entire stack — whereas Bicep's split lets `deploy-mg.bicep` succeed
  while `main.bicep` fails. Mitigated by plan-mode tests and CI validation running on
  every PR.
- **State file contains MG resource.** Operators with separate MG and subscription
  responsibility boundaries cannot split admin access via state-file segregation. In
  practice, SMB partners have a single operator persona, so this is not a real concern.

### Neutral

- **Teardown path.** `terraform destroy` leaves the MG behind by default (the
  `lifecycle.ignore_changes = [subscription_ids]` prevents destroy from recomputing
  child subscriptions). The teardown script offers `--delete-mg` to handle MG removal
  explicitly after all child resources are gone.

## Alternatives considered and rejected

### Option: Mirror Bicep with two roots (`mg/` + `main/`)

Rejected. Requires two state files, two `terraform init` invocations, and hook
orchestration to run them in order. Adds operational complexity with zero partner-facing
benefit.

### Option: Use Terraform workspaces for scope split

Rejected. Workspaces are designed for environment segregation (dev/stage/prod) not scope
segregation. Abusing them here adds onboarding friction for TF-literate partners.

### Option: Flat root — all resources as topical `.tf` files in the root

Initially adopted, later reversed. A flat root kept the module count at zero but
produced a ~17-file root with cross-file implicit references. Child modules make the
dependency contract between concerns explicit (inputs/outputs), allow each concern to
be reasoned about in isolation, and keep the root `main.tf` as a readable composition
map. The import-block-only-in-root constraint is the sole wrinkle, handled by placing
the MG import in root `main.tf` with a module-addressed target.

## Implementation

- See `modules/management-group/` and `modules/policy-assignments-mg/` for the
  MG-scope content.
- See root `main.tf` for the module orchestration and the `import` block targeting
  `module.management_group.azurerm_management_group.smb_rf`.
- See `README.md` → "Child-module layout" callout.
- Teardown script: `scripts/remove-smb-ready-foundation.{sh,ps1}` with `--delete-mg`
  flag.

## References

- [ADR-0005: Add Terraform Dual-Track Alongside Bicep](./07-ab-adr-0005-terraform-dual-track.md)
- [Implementation plan (Terraform)](./04-implementation-plan-terraform.md)
- [Implementation reference (Terraform)](./05-implementation-reference-terraform.md)
- Terraform `import` block docs: <https://developer.hashicorp.com/terraform/language/import>
