---
title: "ADR-0001: Cost-Optimized Landing Zone Architecture for On-Premises Workload Migrations"
status: "Proposed"
date: "2026-01-27"
artifact_version: "0.1"
authors: "Architecture Agent, Partner Operations Team"
tags:
  [
    "architecture",
    "decision",
    "waf",
    "cost-optimization",
    "smb",
    "landing-zone",
  ]
supersedes: ""
superseded_by: ""
---

# ADR-0001: Cost-Optimized Landing Zone Architecture for On-Premises Workload Migrations

## Status

**Proposed** - Pending approval before Bicep implementation.

## Context

A Microsoft partner and infrastructure hosting provider with 1000+ SMB customers requires a repeatable,
single-subscription Azure environment optimized for on-premises workload migrations. The business
context drives several critical architectural constraints:

**Business Forces:**

- **Scale**: 1000+ SMB customers requiring identical infrastructure deployments
- **Cost Sensitivity**: SMB customers have limited budgets; $500/month hard cap per subscription
- **Operational Efficiency**: No per-customer customization; post-deployment configuration expected
- **Migration Focus**: Azure Migrate assessment without Azure Site Recovery complexity

**Technical Forces:**

- **Repeatability**: Infrastructure must deploy identically across all customer subscriptions
- **Security Baseline**: Policy-enforced guardrails without manual intervention
- **EU Compliance**: GDPR data residency requirements (swedencentral region)
- **Hybrid Connectivity**: Optional VPN Gateway for on-premises access

**Explicit Trade-offs Accepted:**

- **No SLA/resilience requirements**: Cost priority over high availability
- **Single-zone deployment**: Zone redundancy explicitly not required
- **Rebuild-from-Bicep DR strategy**: RTO = deployment time (~15-30 minutes)

## Decision

Implement a **hub-spoke network architecture** with cost-optimized SKUs prioritizing the
**Cost Optimization** pillar of the Azure Well-Architected Framework, accepting reduced
scores in Reliability and Performance pillars.

### Core Architecture Decisions

| Component              | Decision                          | Rationale                                                  |
| ---------------------- | --------------------------------- | ---------------------------------------------------------- |
| **Network Topology**   | Hub-spoke with reserved subnets   | Future expansion for Firewall/VPN without redesign         |
| **Region**             | swedencentral (primary)           | EU GDPR compliance, sustainable operations, cost-effective |
| **Bastion**            | Developer SKU (free)              | Cost priority; single-connection sufficient for SMB        |
| **NAT Gateway**        | Standard (zonal)                  | Deterministic outbound; ~$32/month                         |
| **VPN Gateway**        | VpnGw1AZ (~$140/mo)               | Zone-redundant; BGP support; high availability             |
| **Azure Firewall**     | Optional Basic tier               | Deploy only when inspection required                       |
| **Zone Redundancy**    | Disabled (except VPN AZ SKUs)     | Explicit cost trade-off                                    |
| **Policy Enforcement** | 20 built-in policies (Deny/Audit) | Automated compliance without manual gates                  |

### WAF Pillar Alignment

| Pillar                        | Score | Trade-off                                                              |
| ----------------------------- | ----- | ---------------------------------------------------------------------- |
| 🔒 **Security**               | 8/10  | Strong - policy-enforced, no public IPs, Bastion-only access           |
| 🔄 **Reliability**            | 4/10  | Intentionally low - single-zone, no SLA, rebuild-from-Bicep DR         |
| ⚡ **Performance**            | 6/10  | Adequate - B/D/E VM series restriction may limit specialized workloads |
| 💰 **Cost Optimization**      | 9/10  | Primary pillar - free tiers, caps, budget alerts, minimal baseline     |
| 🔧 **Operational Excellence** | 7/10  | Good - Bicep IaC, Log Analytics, policy-driven automation              |

### Cost Breakdown

| Scenario                               | Monthly Cost | Budget Utilization |
| -------------------------------------- | ------------ | ------------------ |
| `baseline` (required services)         | ~$48         | 10%                |
| `vpn` (Baseline + VPN Gateway)         | ~$187        | 37%                |
| `firewall` (Baseline + Azure Firewall) | ~$336        | 67%                |
| `full` (Firewall + VPN)                | ~$476        | 95%                |

## Consequences

### Positive

- **POS-001**: Repeatable deployment across 1000+ customer subscriptions with zero per-customer customization
- **POS-002**: 90% budget headroom in baseline configuration for customer workload compute costs
- **POS-003**: Strong security posture via 20 Azure Policies with Deny effects preventing misconfigurations
- **POS-004**: Free Azure Bastion Developer eliminates ~$138/month compared to Basic SKU
- **POS-005**: Hub-spoke topology enables future Azure Firewall or VPN Gateway without architectural changes
- **POS-006**: Policy-as-code approach ensures consistent governance across all customer deployments
- **POS-007**: CAF-aligned naming and tagging enforced automatically via Azure Policy

### Negative

- **NEG-001**: 4/10 Reliability score means no zone redundancy; single-AZ failure affects workloads
- **NEG-002**: Bastion Developer allows only 1 concurrent connection; not suitable for team operations
- **NEG-003**: VM SKU restrictions (B/D/E series only) may block specialized workloads (GPU, HPC)
- **NEG-004**: No Azure Firewall by default means lateral movement between VMs is not inspected
- **NEG-005**: Rebuild-from-Bicep DR strategy requires ~15-30 minutes RTO; unacceptable for some workloads
- **NEG-006**: Log Analytics 500MB/day cap may truncate logs during high-activity periods

## Alternatives Considered

### Alternative 1: Zone-Redundant Architecture

- **ALT-001**: **Description**: Deploy all resources with zone-redundant SKUs (NAT Gateway StandardV2,
  App Service Plan P1v4+, zone-redundant storage)
- **ALT-002**: **Rejection Reason**: Increases baseline cost by $100-200/month; exceeds budget for many
  SMB customers. Requirements explicitly state "resilience is NOT a requirement."

### Alternative 2: Azure Virtual WAN Hub

- **ALT-003**: **Description**: Use Azure Virtual WAN instead of traditional hub-spoke VNet
- **ALT-004**: **Rejection Reason**: Minimum ~$250/month for Virtual WAN Hub alone; overkill for
  single-spoke SMB deployments. Designed for larger multi-region, multi-spoke scenarios.

### Alternative 3: Azure Bastion Basic/Standard

- **ALT-005**: **Description**: Deploy Bastion Basic ($138/mo) or Standard ($350/mo) for concurrent sessions
- **ALT-006**: **Rejection Reason**: Developer tier is free and sufficient for SMB single-admin access.
  Document upgrade path if concurrent sessions become a requirement.

### Alternative 4: No Azure Policy Enforcement

- **ALT-007**: **Description**: Rely on documentation and training instead of policy enforcement
- **ALT-008**: **Rejection Reason**: With 1000+ deployments, manual compliance is unsustainable.
  Policy-as-code ensures consistent governance without operational overhead.

### Alternative 5: ExpressRoute Instead of VPN Gateway

- **ALT-009**: **Description**: Use ExpressRoute for hybrid connectivity
- **ALT-010**: **Rejection Reason**: ExpressRoute circuits cost $50-500/month plus provider fees;
  excessive for SMB workloads. VPN Gateway VpnGw1AZ at ~$140/month is cost-appropriate.

## Implementation Notes

- **IMP-001**: Deploy policy assignments FIRST (subscription scope) before resource groups to ensure
  all resources are created compliant
- **IMP-002**: Generate `uniqueSuffix` from `uniqueString(resourceGroup().id)` once in main.bicep and
  pass to all modules requiring globally unique names
- **IMP-003**: Reserve AzureFirewallSubnet (/26) and GatewaySubnet (/27) in hub VNet even if optional
  services not deployed initially
- **IMP-004**: Configure Recovery Services Vault backup policies immediately after VM migrations
  complete; do not delay backup configuration
- **IMP-005**: Use policy cleanup script (`scripts/Remove-SmbLandingZonePolicies.ps1`) when
  decommissioning subscriptions to avoid orphaned policy assignments

### Success Metrics

| Metric                  | Target                              | Measurement                       |
| ----------------------- | ----------------------------------- | --------------------------------- |
| Deployment consistency  | 100% identical across subscriptions | Bicep lint + diff validation      |
| Policy compliance       | 100% resources compliant            | Azure Policy compliance dashboard |
| Monthly cost (baseline) | ≤$50/month                          | Cost Management budget alerts     |
| Deployment time         | ≤15 minutes                         | Deployment logs                   |

## References

- **REF-001**: [Azure Well-Architected Framework - Cost Optimization](https://learn.microsoft.com/azure/well-architected/cost-optimization/)
- **REF-002**: [Azure Landing Zone - Single Subscription](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-subscriptions)
- **REF-003**: [Azure Bastion SKU Comparison](https://learn.microsoft.com/azure/bastion/configuration-settings)
- **REF-004**: [NAT Gateway Pricing](https://azure.microsoft.com/pricing/details/azure-nat-gateway/)
- **REF-005**: [VPN Gateway SKU Comparison](https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpn-gateway-settings#gwsku)
- **REF-006**: [02-architecture-assessment.md](02-architecture-assessment.md) - Full WAF assessment
- **REF-007**: [03-des-cost-estimate.md](03-des-cost-estimate.md) - Detailed cost breakdown

---

_ADR generated following Agentic InfraOps standards. Decision rationale derived from WAF assessment
with explicit trade-off documentation for future architectural reviews._
