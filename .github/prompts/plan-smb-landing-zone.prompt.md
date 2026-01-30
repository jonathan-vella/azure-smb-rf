---
description: "SMB Landing Zone - Azure Migrate Ready - Repeatable single-subscription environment"
agent: "Requirements"
model: "Claude Opus 4.5"
tools:
  - edit/createFile
  - edit/editFiles
---

# SMB Landing Zone - Azure Migrate Ready

Capture requirements for a repeatable, single-subscription Azure environment optimized for
on-premises workload migrations for SMB customers.

## Context

Microsoft partner and infrastructure hosting provider with 1000+ SMB customers. Each customer has a handful of
VMs. Building a repeatable, single-subscription Azure environment for on-premises to Azure migrations.

## Core Principles

- **Highly repeatable**: No per-customer customization; post-deployment configuration expected
- **Cost-optimized**: Cheap is essential; resilience is NOT a requirement
- **Secure by default**: Policy-enforced guardrails
- **CAF-aligned**: Naming and tagging per Cloud Adoption Framework
- **Regions**: swedencentral (primary), germanywestcentral (alternate)

## Mandatory Tags

| Tag         | Description               |
| ----------- | ------------------------- |
| Environment | dev, staging, prod        |
| Owner       | Customer/team responsible |

## Resource Groups (CAF naming)

| Purpose          | Name Pattern            |
| ---------------- | ----------------------- |
| Hub networking   | rg-hub-{region}-001     |
| Spoke networking | rg-spoke-{region}-001   |
| Azure Migrate    | rg-migrate-{region}-001 |
| Monitoring       | rg-monitor-{region}-001 |
| Backup           | rg-backup-{region}-001  |

## Network Architecture

### Hub VNet (always created)

- **Deploy-time prompt**: Address space (e.g., 10.0.0.0/16)
- **Pre-provisioned subnets** (always create, even if services not deployed):
  - AzureFirewallSubnet (/26 minimum)
  - GatewaySubnet (/27 minimum)
  - AzureBastionSubnet (/26 minimum)
- **Baseline NSG**: Applied to applicable subnets

### Spoke VNet (always created)

- **Deploy-time prompt**: Address space (e.g., 10.1.0.0/16)
- **Subnets**: Workload subnet(s) with baseline NSG
- **NAT Gateway**: Always deployed for outbound internet

### VNet Peering

- Only configure if hub services (Firewall or VPN Gateway) are deployed

## Required Services (always deployed)

| Service                 | Resource Group   | Configuration                              |
| ----------------------- | ---------------- | ------------------------------------------ |
| Azure Migrate Project   | rg-migrate       | Server assessment only (no ASR)            |
| Log Analytics Workspace | rg-monitor       | 500 MB/day cap, 30-day retention           |
| Recovery Services Vault | rg-backup        | For post-migration VM backups              |
| NAT Gateway             | rg-spoke         | Attached to spoke workload subnets         |
| Azure Private DNS Zone  | rg-hub           | Enable auto-registration for spoke VNet    |
| Azure Bastion Developer | rg-hub           | For secure VM access (no public IPs)       |
| Baseline NSGs           | rg-hub, rg-spoke | Default deny inbound, allow Azure services |
| Cost Management Budget  | subscription     | $500/month, forecast alert + anomaly alert |
| Defender for Cloud      | subscription     | Free tier only (CSPM basics)               |

## Optional Services (prompted at deploy)

User can select any combination: both, one, or none.

| Service           | Resource Group | SKU Options                            | Notes                            |
| ----------------- | -------------- | -------------------------------------- | -------------------------------- |
| Azure Firewall    | rg-hub         | Basic                                  | If deployed, enable VNet peering |
| Azure VPN Gateway | rg-hub         | Basic (~$27/mo) or VpnGw1AZ (~$140/mo) | If deployed, enable VNet peering |

> **VPN Gateway SKU Guidance**:
>
> - **Basic** (~$27/mo): 100 Mbps, max 10 S2S tunnels, no BGP, no zone-redundancy. Best for simple SMB connectivity.
> - **VpnGw1AZ** (~$140/mo): 650 Mbps, max 30 tunnels, BGP support, zone-redundant. Best for production/growth.

## Availability & Resilience (Explicit N/A)

> **Important**: These are explicitly N/A to satisfy architect agent pre-checks.

| Metric              | Value | Justification                                    |
| ------------------- | ----- | ------------------------------------------------ |
| **SLA**             | N/A   | Cost priority; resilience not required for SMB   |
| **RTO**             | N/A   | No DR requirement; rebuild from Bicep if needed  |
| **RPO**             | N/A   | VM backups handle data protection post-migration |
| **Zone Redundancy** | No    | Cost savings; single-zone deployment acceptable  |

## Azure Policy (20 policies with Built-in IDs)

### Compute Guardrails

| #   | Policy                                                   | Built-in ID                            | Effect |
| --- | -------------------------------------------------------- | -------------------------------------- | ------ |
| 1   | Allowed VM SKUs (B, D, E series only)                    | `cccc23c7-8427-4f53-ad12-b6a63eb452b3` | Deny   |
| 2   | Network interfaces should not have public IPs            | `83a86a26-fd1f-447c-b59d-e51f44264114` | Deny   |
| 3   | Audit VMs that do not use managed disks                  | `06a78e20-9358-41c9-923c-fb736d382a4d` | Audit  |
| 4   | Virtual machines should be migrated to new ARM resources | `1d84d5fb-01f6-4d12-ba4f-4a26081d403d` | Audit  |

> **Note**: M/N/L-series denial is achieved via Policy #1 by specifying allowed SKU list.

### Network Guardrails

| #   | Policy                                         | Built-in ID                            | Effect           |
| --- | ---------------------------------------------- | -------------------------------------- | ---------------- |
| 5   | Subnets should be associated with NSG          | `e71308d3-144b-4262-b144-efdc3cc90517` | AuditIfNotExists |
| 6   | Management ports should be closed on VMs       | `22730e10-96f6-4aac-ad84-9383d35b5917` | AuditIfNotExists |
| 7   | All network ports should be restricted on NSGs | `9daedab3-fb2d-461e-b861-71790eead4f6` | AuditIfNotExists |
| 8   | IP forwarding on your VM should be disabled    | `88c0b9da-ce96-4b03-9635-f29a937e2900` | Deny             |

### Storage Guardrails

| #   | Policy                                                | Built-in ID                            | Effect |
| --- | ----------------------------------------------------- | -------------------------------------- | ------ |
| 9   | Secure transfer to storage accounts should be enabled | `404c3081-a854-4457-ae30-26a93ef643f9` | Deny   |
| 10  | Storage account public access should be disallowed    | `4fa4b6c0-31ca-4c0d-b10d-24b96f62a751` | Deny   |
| 11  | Storage accounts should have minimum TLS 1.2          | `fe83a0eb-a853-422d-aac2-1bffd182c5d0` | Deny   |
| 12  | Storage accounts should restrict network access       | `34c877ad-507e-4c82-993e-3452a6e0ad3c` | Audit  |
| 13  | Storage accounts should be migrated to ARM            | `37e0d2fe-28a5-43d6-a273-67d37d1f5606` | Audit  |

### Identity & Access

| #   | Policy                                                | Built-in ID                            | Effect |
| --- | ----------------------------------------------------- | -------------------------------------- | ------ |
| 14  | Azure SQL should have Azure AD-only auth enabled      | `abda6d70-9778-44e7-84a8-06f9e9f5b64b` | Audit  |
| 15  | Public network access on Azure SQL should be disabled | `1b8ca024-1d5c-4dec-8995-b1a932b41780` | Audit  |

### Monitoring & Compliance

| #   | Policy                                                | Built-in ID                            | Effect           |
| --- | ----------------------------------------------------- | -------------------------------------- | ---------------- |
| 16  | Require a tag on resources: Environment               | `871b6d14-10aa-478d-b590-94f262ecfa99` | Deny             |
| 17  | Require a tag on resources: Owner                     | `871b6d14-10aa-478d-b590-94f262ecfa99` | Deny             |
| 18  | Allowed locations                                     | `e56962a6-4747-49cd-b67b-bf8b01975c4c` | Deny             |
| 19  | Azure Backup should be enabled for VMs                | `013e242c-8828-4970-87b3-ab247555486d` | AuditIfNotExists |
| 20  | Audit diagnostic settings for selected resource types | `7f89b1eb-583c-429a-8828-af049802c1d9` | AuditIfNotExists |

### Policy Parameters

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

## Deploy-Time Prompts Summary

1. Region selection (swedencentral or germanywestcentral)
2. Hub VNet address space
3. Spoke VNet address space
4. Deploy Azure Firewall Basic? (yes/no)
5. Deploy Azure VPN Gateway? (yes/no)

## Out of Scope

- Key Vault (not required in baseline)
- Azure Site Recovery (just Migrate project)
- Zone redundancy (resilience not required)
- Custom DNS servers (use Azure Private DNS)
- SLA/RTO/RPO targets (cost priority over resilience)
- Multi-region deployment (single region only)
- ExpressRoute (VPN Gateway optional for hybrid)

## Output Expectations

Generate `agent-output/smb-landing-zone/01-requirements.md` following the structure above.

The requirements document should be ready for handoff to the `@architect` agent for WAF assessment and cost estimation.

## Next Steps

After requirements are captured and approved:

1. User invokes `@architect` for architecture assessment with cost estimates
2. Architecture agent validates requirements and produces WAF assessment
3. Workflow continues: bicep-plan → bicep-code → deploy

---
