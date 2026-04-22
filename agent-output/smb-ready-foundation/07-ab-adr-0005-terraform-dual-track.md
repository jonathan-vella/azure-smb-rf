---
title: "ADR-0005: Add Terraform Dual-Track Alongside Bicep"
status: "Implemented"
date: "2026-04-17"
artifact_version: "1.0"
authors: "Terraform Code Agent, Partner Operations Team"
tags: ["architecture", "decision", "terraform", "bicep", "iac", "dual-track"]
supersedes: ""
superseded_by: ""
---

# ADR-0005: Add Terraform Dual-Track Alongside Bicep

## Status

**Implemented** — Terraform variant delivered at `infra/terraform/smb-ready-foundation/`
alongside the canonical Bicep at `infra/bicep/smb-ready-foundation/`.

## Context

The SMB Ready Foundations was originally delivered in Bicep (ADR-0001, ADR-0002). Partner
adoption data showed that a subset of SMB operators standardise on Terraform across their
multi-cloud estate and are unwilling to add Bicep to their toolchain. Options considered:

1. **Bicep only** (status quo). Partners on Terraform cannot adopt without dual-tooling.
2. **Replace Bicep with Terraform.** Abandons existing partners already in production and
   discards the verified AVM-first Bicep code path.
3. **Publish a Terraform variant alongside Bicep.** Partners pick one per subscription.

## Decision

Ship a Terraform track **alongside** the Bicep track with functional parity. Neither
track is authoritative at the architecture level — both compile to the same resource
inventory, policies, tags, and WAF scoring from ADR-0001.

### Parity invariants

1. Same CAF naming conventions and region abbreviations (`swc`, `gwc`).
2. Same required tags: `Environment`, `Owner`, `Project`, `ManagedBy`
   (`ManagedBy = "Terraform"` in this track to preserve provenance).
3. Same 4-scenario matrix: baseline, firewall, vpn, full.
4. Same 33 MG-scoped policies + 1 sub-scope DINE (`smb-backup-02`).
5. Same cost envelopes (~$48 / ~$336 / ~$187 / ~$476 per month).
6. Same security baseline (TLS 1.2, HTTPS-only, RBAC on KV, PE in `snet-pep`,
   SystemAssigned managed identity on Automation).

### Intentional divergences

| Concern               | Decision                                                                |
| --------------------- | ----------------------------------------------------------------------- |
| Scope composition     | Single-root Terraform (ADR-0006) vs. split Bicep templates.             |
| AVM posture           | Raw `azurerm_*` / `azapi_resource` vs. Bicep AVM-first.                 |
| Unique suffix         | `substr(sha1(sub_id), 0, 13)` — matches Bicep's `uniqueString()` hash.  |
| `ManagedBy` tag value | `"Terraform"` vs. `"Bicep"` so deployed resources self-identify.        |
| Budget start date     | Injected by hook (avoids `utcNow()` drift on repeated applies).         |
| State backend         | Azure Storage Account (`rg-tfstate-smb-<region>`) bootstrapped by hook. |
| Policy count output   | Dynamic (`policy_assignment_count`) vs. Bicep's stale hard-coded `30`.  |

## Consequences

### Positive

- **Expanded addressable market.** Partners standardised on Terraform can adopt the SMB
  Ready Foundation without tool-chain churn.
- **Cross-validation.** Dual implementations surface Bicep defects (e.g., the stale
  `policyCount = 30` output when 33 policies exist; patched in the TF port, flagged
  upstream for the Bicep track).
- **Test coverage matrix.** Plan-mode `terraform test` scenarios run in CI without Azure
  auth, complementing the Bicep what-if coverage.

### Negative

- **Duplicated maintenance burden.** Policy additions, naming changes, and security
  baseline updates must be applied in both tracks. Mitigated by a shared
  `04-implementation-plan.md` as the authoritative source and this ADR-0005 documenting
  the parity invariants.
- **Mutual exclusion per subscription.** Both tracks generate the same globally-unique
  names (same `uniqueString` hash). Running both against the same subscription produces
  name collisions. Documented in the Terraform README as a hard operational constraint.
- **Alpha azd Terraform dependency.** The preprovision hook must flip
  `alpha.terraform on`. Tracked as a versioning risk until Microsoft promotes Terraform
  support to GA in `azd`.

### Neutral

- Two sets of hooks (`.sh` + `.ps1`) and two teardown scripts. Matches the dual-OS
  expectation already established in the Bicep track.

## Alternatives considered and rejected

### Option: Translate at build time (Bicep → Terraform via `az bicep decompile-params` or similar)

Rejected. Bicep and Terraform have structural differences (scope semantics, conditional
resources, module system) that produce low-quality generated code. Hand-authored
Terraform is maintainable; generated Terraform is not.

### Option: Terraform-only replacement

Rejected. Existing Bicep deployments in production would require migration effort that
has no partner-facing value. Dual-track preserves all prior investment.

### Option: Cross-IaC module shims (Terraform module wrapping Bicep `az deployment`)

Rejected. Breaks Terraform state tracking, drift detection, and plan previews. Defeats
the entire reason partners ask for Terraform in the first place.

## Implementation

- Phases 1–9 complete (see Terraform README phase table).
- Code: `infra/terraform/smb-ready-foundation/`.
- CI: `.github/workflows/terraform-smb-ready-foundation.yml`.
- Plan: [`04-implementation-plan-terraform.md`](./04-implementation-plan-terraform.md).
- Reference: [`05-implementation-reference-terraform.md`](./05-implementation-reference-terraform.md).
- Follow-on ADR for the single-root composition: [ADR-0006](./07-ab-adr-0006-terraform-single-root-composition.md).

## References

- [ADR-0001: Cost-Optimized SMB Ready Foundations Architecture](./03-des-adr-0001-cost-optimized-landing-zone-architecture.md)
- [ADR-0002: Bicep Infrastructure Implementation Architecture](./07-ab-adr-0002-bicep-infrastructure-implementation.md)
- [Terraform patterns skill](../../.github/skills/terraform-patterns/SKILL.md)
- [Terraform best-practices instruction](../../.github/instructions/iac-terraform-best-practices.instructions.md)
