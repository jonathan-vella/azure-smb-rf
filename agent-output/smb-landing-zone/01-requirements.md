# SMB Landing Zone - Requirements

> **Agentic InfraOps** - Azure infrastructure engineered by agents. Verified. Well-Architected. Deployable.
>
> Artifact v0.1 | 2026-01-27

## Project Overview

**Project Name**: smb-landing-zone  
**Description**: Repeatable, single-subscription Azure environment optimized for VMware-to-Azure migrations for SMB customers.  
**Business Context**: Microsoft partner and VMware hosting provider with 1000+ SMB customers. Each customer has a handful of VMs. Building a repeatable, single-subscription Azure environment for VMware-to-Azure migrations.  
**Stakeholders**: Partner operations team, SMB customers  
**Target Deployment Date**: TBD

### Core Principles

| Principle         | Description                                                           |
| ----------------- | --------------------------------------------------------------------- |
| Highly repeatable | No per-customer customization; post-deployment configuration expected |
| Cost-optimized    | Cheap is essential; resilience is NOT a requirement                   |
| Secure by default | Policy-enforced guardrails                                            |
| CAF-aligned       | Naming and tagging per Cloud Adoption Framework                       |

## Functional Requirements

### Resource Groups (CAF Naming)

| Purpose          | Name Pattern            | Description                                           |
| ---------------- | ----------------------- | ----------------------------------------------------- |
| Hub networking   | rg-hub-{region}-001     | Hub VNet, Bastion, Firewall, VPN Gateway, Private DNS |
| Spoke networking | rg-spoke-{region}-001   | Spoke VNet, NAT Gateway, workload subnets             |
| Azure Migrate    | rg-migrate-{region}-001 | Azure Migrate project for VMware assessment           |
| Monitoring       | rg-monitor-{region}-001 | Log Analytics Workspace                               |
| Backup           | rg-backup-{region}-001  | Recovery Services Vault                               |

### Network Architecture

#### Hub VNet (Always Created)

| Configuration       | Value                         | Notes                                            |
| ------------------- | ----------------------------- | ------------------------------------------------ |
| Address space       | Deploy-time parameter         | Example: 10.0.0.0/16                             |
| AzureFirewallSubnet | /26 minimum                   | Pre-provisioned even if Firewall not deployed    |
| GatewaySubnet       | /27 minimum                   | Pre-provisioned even if VPN Gateway not deployed |
| AzureBastionSubnet  | /26 minimum                   | Required for Bastion Developer                   |
| Baseline NSG        | Applied to applicable subnets | Default deny inbound                             |

#### Spoke VNet (Always Created)

| Configuration    | Value                 | Notes                              |
| ---------------- | --------------------- | ---------------------------------- |
| Address space    | Deploy-time parameter | Example: 10.1.0.0/16               |
| Workload subnets | At least one          | With baseline NSG attached         |
| NAT Gateway      | Always deployed       | For outbound internet connectivity |

#### VNet Peering

| Condition               | Action                   |
| ----------------------- | ------------------------ |
| Azure Firewall deployed | Enable hub-spoke peering |
| VPN Gateway deployed    | Enable hub-spoke peering |
| Neither deployed        | No peering configured    |

### Required Services (Always Deployed)

| Service                 | Resource Group   | SKU/Tier  | Configuration                              |
| ----------------------- | ---------------- | --------- | ------------------------------------------ |
| Azure Migrate Project   | rg-migrate       | N/A       | VMware assessment only (no ASR)            |
| Log Analytics Workspace | rg-monitor       | Per-GB    | 500 MB/day cap, 30-day retention           |
| Recovery Services Vault | rg-backup        | Standard  | For post-migration VM backups              |
| NAT Gateway             | rg-spoke         | Standard  | Attached to spoke workload subnets         |
| Azure Private DNS Zone  | rg-hub           | N/A       | Enable auto-registration for spoke VNet    |
| Azure Bastion           | rg-hub           | Developer | Secure VM access without public IPs        |
| Baseline NSGs           | rg-hub, rg-spoke | N/A       | Default deny inbound, allow Azure services |
| Cost Management Budget  | subscription     | N/A       | $500/month, forecast + anomaly alerts      |
| Defender for Cloud      | subscription     | Free tier | CSPM basics only                           |

### Optional Services (Prompted at Deploy)

User can select any combination: both, one, or none.

| Service           | Resource Group | SKU Options                            | Default | Notes                            |
| ----------------- | -------------- | -------------------------------------- | ------- | -------------------------------- |
| Azure Firewall    | rg-hub         | Basic                                  | Basic   | If deployed, enable VNet peering |
| Azure VPN Gateway | rg-hub         | Basic (~$27/mo) or VpnGw1AZ (~$140/mo) | Basic   | If deployed, enable VNet peering |

> **VPN Gateway SKU Guidance**:
>
> - **Basic** (~$27/mo): 100 Mbps, max 10 S2S tunnels, no BGP, no zone-redundancy. Best for simple SMB connectivity.
> - **VpnGw1AZ** (~$140/mo): 650 Mbps, max 30 tunnels, BGP support, zone-redundant. Best for production/growth.

### Deploy-Time Parameters

| #   | Parameter                    | Type    | Example Value                       |
| --- | ---------------------------- | ------- | ----------------------------------- |
| 1   | Region selection             | choice  | swedencentral or germanywestcentral |
| 2   | Hub VNet address space       | CIDR    | 10.0.0.0/16                         |
| 3   | Spoke VNet address space     | CIDR    | 10.1.0.0/16                         |
| 4   | Deploy Azure Firewall Basic? | boolean | yes/no                              |
| 5   | Deploy Azure VPN Gateway?    | boolean | yes/no                              |

## Non-Functional Requirements (NFRs)

### Performance

| Metric              | Requirement           | Notes                            |
| ------------------- | --------------------- | -------------------------------- |
| VM Performance      | Standard B/D/E series | Policy-enforced SKU restrictions |
| Network throughput  | NAT Gateway standard  | Supports up to 50 Gbps           |
| Bastion connections | Developer SKU limits  | Sufficient for SMB workloads     |

### Availability & Resilience

> **Important**: These are explicitly N/A to satisfy architect agent pre-checks and reflect cost-priority design.

| Metric              | Value | Justification                                    |
| ------------------- | ----- | ------------------------------------------------ |
| **SLA**             | N/A   | Cost priority; resilience not required for SMB   |
| **RTO**             | N/A   | No DR requirement; rebuild from Bicep if needed  |
| **RPO**             | N/A   | VM backups handle data protection post-migration |
| **Zone Redundancy** | No    | Cost savings; single-zone deployment acceptable  |

### Scalability

| Dimension       | Approach                                   |
| --------------- | ------------------------------------------ |
| Per-customer    | Single subscription per customer           |
| VNet sizing     | Configurable address spaces at deploy time |
| Workload growth | Add subnets to spoke VNet post-deployment  |

## Compliance & Security Requirements

### Policy Deployment Strategy

| Aspect            | Decision                                                 |
| ----------------- | -------------------------------------------------------- |
| Deployment method | **Bicep** - `Microsoft.Authorization/policyAssignments`  |
| Policy type       | Built-in definitions only (no custom policies)           |
| Assignment scope  | Subscription level                                       |
| Naming convention | `smb-lz-{category}-{number}` (e.g., `smb-lz-compute-01`) |
| Metadata tags     | `Project: smb-landing-zone`, `ManagedBy: Bicep`          |
| Cleanup script    | `scripts/Remove-SmbLandingZonePolicies.ps1`              |

### Mandatory Tags

| Tag         | Description               | Enforcement         |
| ----------- | ------------------------- | ------------------- |
| Environment | dev, staging, prod        | Azure Policy - Deny |
| Owner       | Customer/team responsible | Azure Policy - Deny |

### Azure Policy (20 Policies with Built-in IDs)

#### Compute Guardrails

| #   | Policy                                                   | Built-in ID                            | Effect |
| --- | -------------------------------------------------------- | -------------------------------------- | ------ |
| 1   | Allowed VM SKUs (B, D, E series only)                    | `cccc23c7-8427-4f53-ad12-b6a63eb452b3` | Deny   |
| 2   | Network interfaces should not have public IPs            | `83a86a26-fd1f-447c-b59d-e51f44264114` | Deny   |
| 3   | Audit VMs that do not use managed disks                  | `06a78e20-9358-41c9-923c-fb736d382a4d` | Audit  |
| 4   | Virtual machines should be migrated to new ARM resources | `1d84d5fb-01f6-4d12-ba4f-4a26081d403d` | Audit  |

#### Network Guardrails

| #   | Policy                                         | Built-in ID                            | Effect           |
| --- | ---------------------------------------------- | -------------------------------------- | ---------------- |
| 5   | Subnets should be associated with NSG          | `e71308d3-144b-4262-b144-efdc3cc90517` | AuditIfNotExists |
| 6   | Management ports should be closed on VMs       | `22730e10-96f6-4aac-ad84-9383d35b5917` | AuditIfNotExists |
| 7   | All network ports should be restricted on NSGs | `9daedab3-fb2d-461e-b861-71790eead4f6` | AuditIfNotExists |
| 8   | IP forwarding on your VM should be disabled    | `88c0b9da-ce96-4b03-9635-f29a937e2900` | Deny             |

#### Storage Guardrails

| #   | Policy                                                | Built-in ID                            | Effect |
| --- | ----------------------------------------------------- | -------------------------------------- | ------ |
| 9   | Secure transfer to storage accounts should be enabled | `404c3081-a854-4457-ae30-26a93ef643f9` | Deny   |
| 10  | Storage account public access should be disallowed    | `4fa4b6c0-31ca-4c0d-b10d-24b96f62a751` | Deny   |
| 11  | Storage accounts should have minimum TLS 1.2          | `fe83a0eb-a853-422d-aac2-1bffd182c5d0` | Deny   |
| 12  | Storage accounts should restrict network access       | `34c877ad-507e-4c82-993e-3452a6e0ad3c` | Audit  |
| 13  | Storage accounts should be migrated to ARM            | `37e0d2fe-28a5-43d6-a273-67d37d1f5606` | Audit  |

#### Identity & Access

| #   | Policy                                                | Built-in ID                            | Effect |
| --- | ----------------------------------------------------- | -------------------------------------- | ------ |
| 14  | Azure SQL should have Azure AD-only auth enabled      | `abda6d70-9778-44e7-84a8-06f9e9f5b64b` | Audit  |
| 15  | Public network access on Azure SQL should be disabled | `1b8ca024-1d5c-4dec-8995-b1a932b41780` | Audit  |

#### Monitoring & Compliance

| #   | Policy                                                | Built-in ID                            | Effect           |
| --- | ----------------------------------------------------- | -------------------------------------- | ---------------- |
| 16  | Require a tag on resources: Environment               | `871b6d14-10aa-478d-b590-94f262ecfa99` | Deny             |
| 17  | Require a tag on resources: Owner                     | `871b6d14-10aa-478d-b590-94f262ecfa99` | Deny             |
| 18  | Allowed locations                                     | `e56962a6-4747-49cd-b67b-bf8b01975c4c` | Deny             |
| 19  | Azure Backup should be enabled for VMs                | `013e242c-8828-4970-87b3-ab247555486d` | AuditIfNotExists |
| 20  | Audit diagnostic settings for selected resource types | `7f89b1eb-583c-429a-8828-af049802c1d9` | AuditIfNotExists |

#### Policy Parameters

```json
{
  "allowedLocations": ["swedencentral", "germanywestcentral", "global"],
  "allowedVmSkus": [
    "Standard_B*",
    "Standard_D*v5",
    "Standard_D*s_v5",
    "Standard_D*v6",
    "Standard_D*s_v6",
    "Standard_E*v5",
    "Standard_E*s_v5",
    "Standard_E*v6",
    "Standard_E*s_v6"
  ]
}
```

> **Note**: v5 series is the current mainstream generation; v6 is the latest (2024+).
> B-series provides burstable, cost-effective compute for SMB workloads.

### Security Defaults

| Setting           | Value                                      |
| ----------------- | ------------------------------------------ |
| Public IPs on VMs | Denied via policy                          |
| Bastion access    | Developer SKU for secure RDP/SSH           |
| NSG baseline      | Default deny inbound, allow Azure services |
| Storage security  | HTTPS only, TLS 1.2, no public blob access |

## Budget

| Category         | Monthly Estimate | Notes                                                 |
| ---------------- | ---------------- | ----------------------------------------------------- |
| **Total Budget** | $500/month       | Hard cap with alerts                                  |
| Compute (VMs)    | Variable         | Customer workloads post-migration                     |
| Networking       | ~$50-150         | NAT Gateway, Bastion Developer, optional Firewall/VPN |
| Storage          | Variable         | Managed disks for VMs                                 |
| Monitoring       | ~$10-30          | Log Analytics with 500 MB/day cap                     |
| Backup           | Variable         | Recovery Services Vault consumption                   |

### Cost Management Configuration

| Setting           | Value                    |
| ----------------- | ------------------------ |
| Budget amount     | $500/month               |
| Forecast alert    | 80% threshold            |
| Anomaly detection | Enabled                  |
| Notifications     | Email to Owner tag value |

## Operational Requirements

### Monitoring Strategy

| Component               | Configuration                     |
| ----------------------- | --------------------------------- |
| Log Analytics Workspace | 500 MB/day cap, 30-day retention  |
| Defender for Cloud      | Free tier (CSPM basics)           |
| Cost Management         | Budget alerts + anomaly detection |

### Backup Strategy

| Component               | Configuration             |
| ----------------------- | ------------------------- |
| Recovery Services Vault | Standard tier             |
| VM backup policy        | Configure post-migration  |
| Retention               | Per customer requirements |

### Access Management

| Requirement      | Implementation                          |
| ---------------- | --------------------------------------- |
| Secure VM access | Azure Bastion Developer (no public IPs) |
| RBAC             | Configure post-deployment per customer  |
| Emergency access | Via Bastion only                        |

## Regional Preferences

| Priority  | Region             | Justification                     |
| --------- | ------------------ | --------------------------------- |
| Primary   | swedencentral      | EU GDPR-compliant, cost-effective |
| Alternate | germanywestcentral | EU GDPR-compliant backup option   |

### Location Constraints

- All resources must deploy to `swedencentral` or `germanywestcentral`
- `global` allowed for Azure Policy and other non-regional resources
- Enforced via Azure Policy (Allowed locations)

### Out of Scope

The following items are explicitly excluded from this landing zone:

| Item                       | Reason                                                  |
| -------------------------- | ------------------------------------------------------- |
| Key Vault                  | Not required in baseline; add post-deployment if needed |
| Azure Site Recovery        | Just Migrate project for assessment                     |
| Zone redundancy            | Resilience not required; cost priority                  |
| Custom DNS servers         | Use Azure Private DNS instead                           |
| SLA/RTO/RPO targets        | Cost priority over resilience                           |
| Multi-region deployment    | Single region only                                      |
| ExpressRoute               | VPN Gateway optional for hybrid connectivity            |
| Per-customer customization | Post-deployment configuration expected                  |

## Summary for Architecture Assessment

This requirements document defines a **cost-optimized, repeatable SMB landing zone** for VMware-to-Azure migrations with the following characteristics:

- **5 Resource Groups**: Hub, Spoke, Migrate, Monitor, Backup
- **Hub-Spoke Network**: Configurable address spaces, pre-provisioned subnets, NAT Gateway for outbound
- **9 Required Services**: Migrate, Log Analytics, Recovery Services, NAT Gateway, Private DNS, Bastion Developer, NSGs, Cost Budget, Defender Free
- **2 Optional Services**: Azure Firewall Basic, VPN Gateway
- **20 Azure Policies**: Compute, Network, Storage, Identity, and Monitoring guardrails
- **$500/month budget**: With forecast and anomaly alerts

**Ready for handoff to `@architect` agent** for WAF assessment and cost estimation.

---

_Generated by requirements agent | Agentic InfraOps SMB_
