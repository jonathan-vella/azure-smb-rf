---
title: "ADR-0002: Bicep Infrastructure Implementation Architecture"
status: "Implemented"
date: "2026-01-28"
artifact_version: "0.1"
authors: "Bicep Code Agent, Partner Operations Team"
tags:
  [
    "architecture",
    "decision",
    "bicep",
    "implementation",
    "infrastructure-as-code",
    "azure",
  ]
supersedes: ""
superseded_by: ""
---

# ADR-0002: Bicep Infrastructure Implementation Architecture

## Status

**Implemented** - Bicep templates deployed to `infra/bicep/smb-landing-zone/`.

## Context

Following the approval of ADR-0001 (Cost-Optimized Landing Zone Architecture), the implementation
phase required decisions about how to structure, organize, and deploy the Azure infrastructure
using Bicep templates. These decisions impact maintainability, reusability, and operational
efficiency across 1000+ SMB customer deployments.

**Implementation Forces:**

- **Subscription-Scope Deployment**: Policies and budgets require subscription-level targeting
- **Cross-Resource Group Dependencies**: Hub and spoke resources span multiple resource groups
- **Conditional Resources**: Azure Firewall and VPN Gateway are optional per-customer
- **Policy Enforcement**: 20 Azure Policies must deploy before any resources
- **Unique Naming**: Globally unique resources (Key Vault, Storage) need deterministic suffixes

**Operational Forces:**

- **Partner Workflow**: Single PowerShell script for deployment with what-if preview
- **Rollback Strategy**: Policy cleanup required before redeployment
- **Parameterization**: Minimal required inputs (owner only), sensible defaults
- **Validation**: Build-time linting and format checks

**Technical Constraints:**

- **Bicep API Versions**: Use 2024-01-01 or later for networking resources
- **Azure Migrate API Limitation**: Tags not supported on migrateProjects resource type
- **Conditional Module Outputs**: Null-safety required for optional module references

## Decision

Implement a **modular Bicep architecture** with subscription-scope orchestration, phased
deployment order, and conditional resource patterns for optional services.

### Module Structure Decision

| Decision Area           | Choice                               | Rationale                                              |
| ----------------------- | ------------------------------------ | ------------------------------------------------------ |
| **Orchestration Scope** | Subscription-level `main.bicep`      | Policies, budgets, and RG creation require sub scope   |
| **Module Granularity**  | 12 feature-focused modules           | Balance between reusability and deployment complexity  |
| **Resource Grouping**   | One module per resource category     | Networking, monitoring, backup, etc. as cohesive units |
| **Cross-RG Pattern**    | Nested module with `scope:` override | Hub-spoke peering spans two resource groups            |
| **Conditional Pattern** | `= if (condition)` syntax            | Clean optional deployment without wrapper modules      |

### Deployment Phasing

```
Phase 1: Subscription Scope (parallel)
├── policy-assignments.bicep (20 policies)
└── budget.bicep (cost management)

Phase 2: Foundation (serial)
└── resource-groups.bicep (5 RGs)

Phase 3: Core Networking (parallel)
├── networking-hub.bicep (VNet, Bastion, DNS)
└── networking-spoke.bicep (VNet, NAT, NSG)

Phase 4: Supporting Services (parallel)
├── monitoring.bicep (Log Analytics)
├── backup.bicep (Recovery Vault)
└── migrate.bicep (Azure Migrate)

Phase 5: Optional Services (conditional, parallel)
├── firewall.bicep (if scenario == 'firewall' || 'enterprise')
└── vpn-gateway.bicep (if scenario == 'vpn' || 'enterprise')

Phase 6: Connectivity (conditional)
└── networking-peering.bicep (if scenario != 'baseline')
```

### Naming Strategy

| Resource Type    | Pattern                          | Example               | Notes                            |
| ---------------- | -------------------------------- | --------------------- | -------------------------------- |
| Resource Groups  | `rg-{workload}-{env}-{region}`   | `rg-hub-slz-swc`      | Shared services use `slz` as env |
| Virtual Networks | `vnet-{workload}-{env}-{region}` | `vnet-spoke-prod-swc` | Spoke uses environment parameter |
| Subnets          | `snet-{purpose}`                 | `snet-workload`       |                                  |
| NSGs             | `nsg-{workload}-{env}-{region}`  | `nsg-hub-slz-swc`     | Shared services use `slz`        |
| Public IPs       | `pip-{purpose}-{env}-{region}`   | `pip-nat-prod-swc`    |                                  |
| Log Analytics    | `log-{project}-{env}-{region}`   | `log-smblz-slz-swc`   | Shared services use `slz`        |
| Recovery Vault   | `rsv-{project}-{env}-{region}`   | `rsv-smblz-slz-swc`   | Shared services use `slz`        |

### Unique Suffix Strategy

```bicep
// Generated once at subscription level, passed to all modules
var uniqueSuffix = uniqueString(subscription().subscriptionId)

// Region abbreviation mapping
var regionAbbreviations = {
  swedencentral: 'swc'
  germanywestcentral: 'gwc'
}
```

### Policy Assignment Design

| Category   | Count | Effect Mix         | Assignment Prefix            |
| ---------- | ----- | ------------------ | ---------------------------- |
| Compute    | 4     | 2 Deny, 2 Audit    | `smb-lz-compute-*`           |
| Network    | 4     | 1 Deny, 3 Audit    | `smb-lz-network-*`           |
| Storage    | 5     | 3 Deny, 2 Audit    | `smb-lz-storage-*`           |
| Identity   | 2     | 2 Audit            | `smb-lz-identity-*`          |
| Tagging    | 2     | 2 Deny             | `smb-lz-tagging-*`           |
| Governance | 1     | 1 Deny             | `smb-lz-governance-*`        |
| Operations | 2     | 2 AuditIfNotExists | `smb-lz-backup/monitoring-*` |

## Consequences

### Positive

- **POS-001**: Single `deploy.ps1` script provides complete deployment workflow with what-if preview
- **POS-002**: Modular structure allows independent module updates without full redeployment
- **POS-003**: Conditional resources (Firewall, VPN) add ~$0 when not deployed
- **POS-004**: Policy-first deployment prevents non-compliant resources from creation
- **POS-005**: `Remove-SmbLandingZonePolicies.ps1` enables clean rollback for redeployment
- **POS-006**: Region abbreviation mapping ensures consistent 3-character codes across resources
- **POS-007**: Subscription-scope uniqueSuffix guarantees globally unique names per customer
- **POS-008**: Cross-RG peering pattern enables future multi-spoke expansion

### Negative

- **NEG-001**: Subscription-scope deployment requires Owner/Contributor at subscription level
- **NEG-002**: Azure Migrate API limitation prevents tag application (interface consistency param kept)
- **NEG-003**: Conditional module outputs require `#disable-next-line BCP318` suppressions
- **NEG-004**: VPN Gateway deployment takes 30+ minutes, extending total deployment time
- **NEG-005**: Policy cleanup script must run before redeployment to avoid assignment conflicts

## Alternatives Considered

### Alternative 1: Resource Group-Scope Deployment

- **ALT-001**: **Description**: Deploy main.bicep at resource group level instead of subscription
- **ALT-001**: **Rejection Reason**: Policies and budgets require subscription scope; would need separate deployment

### Alternative 2: Monolithic Single-File Template

- **ALT-002**: **Description**: All resources in one large main.bicep file
- **ALT-002**: **Rejection Reason**: Reduces maintainability; harder to test individual components

### Alternative 3: Azure Verified Modules (AVM) Direct Usage

- **ALT-003**: **Description**: Use published AVM modules from Bicep registry
- **ALT-003**: **Rejection Reason**: AVM modules include features beyond requirements; custom modules provide tighter cost control

### Alternative 4: Terraform Instead of Bicep

- **ALT-004**: **Description**: Implement infrastructure using Terraform HCL
- **ALT-004**: **Rejection Reason**: Bicep is Azure-native, simpler toolchain, better IDE support

## Implementation Notes

- **IMP-001**: Run `bicep build main.bicep` before deployment to catch compile errors
- **IMP-002**: Always use `-WhatIf` flag on first deployment to preview changes
- **IMP-003**: VPN Gateway deployment is slow (~30 min); consider parallel terminal for monitoring
- **IMP-004**: If policies already exist, run cleanup script first: `./scripts/Remove-SmbLandingZonePolicies.ps1`
- **IMP-005**: Budget alerts require valid email; use owner parameter for notification target
- **IMP-006**: Bastion Developer SKU requires no public IP but limits to single connection

### Deployment Command

```powershell
# Preview deployment
./deploy.ps1 -Scenario baseline -Owner "partner-ops@contoso.com" -WhatIf

# Execute deployment by scenario
./deploy.ps1 -Scenario baseline -Owner "partner-ops@contoso.com"    # NAT Gateway only (~$48/mo)
./deploy.ps1 -Scenario firewall -Owner "partner-ops@contoso.com"   # Firewall + UDR (~$336/mo)
./deploy.ps1 -Scenario vpn -Owner "partner-ops@contoso.com"        # VPN Gateway (~$187/mo)
./deploy.ps1 -Scenario enterprise -Owner "partner-ops@contoso.com" # Firewall + VPN (~$476/mo)
```

## References

- **REF-001**: [ADR-0001: Cost-Optimized Landing Zone Architecture](03-des-adr-0001-cost-optimized-landing-zone-architecture.md)
- **REF-002**: [Implementation Plan](04-implementation-plan.md)
- **REF-003**: [Implementation Reference](05-implementation-reference.md)
- **REF-004**: [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- **REF-005**: [Azure Policy Built-in Definitions](https://learn.microsoft.com/azure/governance/policy/samples/built-in-policies)
- **REF-006**: [Cloud Adoption Framework Naming Conventions](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)

---

_ADR generated after Bicep implementation completion. Reflects actual implementation decisions._
