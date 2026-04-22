<!-- markdownlint-disable MD013 -->

# Azure SMB Ready Foundations — Partner Quick Reference

> **Version**: v0.10.0 | **Deployment**: `azd up` | **Cleanup**: `Remove-SmbReadyFoundation.ps1`

SMB Ready Foundations gives Microsoft Partners a repeatable, easy-to-deploy,
and well-managed Azure platform for SMB customers.

## Prerequisites

| Requirement               | Minimum                           |
| ------------------------- | --------------------------------- |
| Azure subscription        | Owner role                        |
| Azure CLI                 | 2.60+                             |
| Azure Developer CLI (azd) | 1.9+                              |
| PowerShell                | 7.4+                              |
| Management group          | Create `smb-rf` under tenant root |

## Quick Deploy

```bash
cd infra/bicep/smb-ready-foundation

# One-time: create management group
az account management-group create --name smb-rf --display-name "SMB Ready Foundations"
az account management-group subscription add --name smb-rf \
  --subscription $(az account show --query id -o tsv)

# Configure
azd env new customer-prod
azd env set SCENARIO baseline          # baseline | firewall | vpn | full
azd env set OWNER "partner@contoso.com"
azd env set AZURE_LOCATION swedencentral
azd env set ENVIRONMENT prod
azd env set HUB_VNET_ADDRESS_SPACE "10.0.0.0/23"
azd env set SPOKE_VNET_ADDRESS_SPACE "10.0.2.0/23"
azd env set LOG_ANALYTICS_DAILY_CAP_GB "0.5"
azd env set MANAGEMENT_GROUP_ID smb-rf

# For vpn or full scenarios only:
azd env set ON_PREMISES_ADDRESS_SPACE "192.168.0.0/16"

# Deploy
azd up
```

## Scenarios

| Scenario     | Cost/month | NAT GW | Firewall | VPN GW | Peering |
| ------------ | ---------- | ------ | -------- | ------ | ------- |
| **baseline** | ~$48       | ✅     | —        | —      | —       |
| **firewall** | ~$336      | —      | ✅       | —      | ✅      |
| **vpn**      | ~$187      | ✅     | —        | ✅     | ✅      |
| **full**     | ~$476      | —      | ✅       | ✅     | ✅      |

## What Gets Deployed (All Scenarios)

| Resource Group        | Key Resources                                 |
| --------------------- | --------------------------------------------- |
| `rg-hub-smb-swc`      | Hub VNet, NSG, Private DNS, Bastion Developer |
| `rg-spoke-prod-swc`   | Spoke VNet, NSG, NAT GW or Route Table        |
| `rg-monitor-smb-swc`  | Log Analytics (500MB cap), Automation Account |
| `rg-backup-smb-swc`   | Recovery Services Vault                       |
| `rg-security-smb-swc` | Key Vault + Private Endpoint                  |
| `rg-migrate-smb-swc`  | Azure Migrate Project                         |

Plus: 33 MG-scoped policies, monthly budget ($500), Defender for Cloud (free CSPM).

## Verification

```bash
# 6 resource groups
az group list --query "[?starts_with(name,'rg-')].{name:name,state:properties.provisioningState}" -o table

# 33 policies
az policy assignment list \
  --scope "/providers/Microsoft.Management/managementGroups/smb-rf" \
  --query "length(@)"

# Budget
az consumption budget list --query "[?name=='budget-smb-monthly'].amount" -o tsv
```

## Cleanup

```bash
cd infra/bicep/smb-ready-foundation

# Preview (dry run)
pwsh scripts/Remove-SmbReadyFoundation.ps1 -WhatIf

# Remove RGs + policies (keep MG)
pwsh scripts/Remove-SmbReadyFoundation.ps1 -Force

# Remove everything including MG
pwsh scripts/Remove-SmbReadyFoundation.ps1 -Force -RemoveManagementGroup
```

## Useful Links

| Resource                | Link                                                                 |
| ----------------------- | -------------------------------------------------------------------- |
| Full documentation      | [User Guide](site/src/content/docs/getting-started/quick-start.mdx)  |
| Configuration reference | [Parameters](site/src/content/docs/deploying/configuration.mdx)      |
| Policy catalog          | [33 Policies](site/src/content/docs/reference/policies.mdx)          |
| Troubleshooting         | [Common Issues](site/src/content/docs/operating/troubleshooting.mdx) |
| Source repository       | [GitHub](https://github.com/jonathan-vella/azure-smb-rf)             |

# Partner Quick Reference Card

> **Azure SMB Ready Foundations v0.10.0** | Single-page deployment guide for Microsoft Partners standardizing Azure delivery for SMB customers

---

## 📋 Prerequisites Checklist

| Requirement          | Details                                                                                                                 |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| ☐ Docker Desktop     | Or Podman, Colima, Rancher Desktop                                                                                      |
| ☐ VS Code            | With [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension |
| ☐ GitHub Copilot     | Active subscription required                                                                                            |
| ☐ Azure Subscription | Owner role required                                                                                                     |
| ☐ Global Admin       | Required for Phase 0 (management group permissions, one-time)                                                           |

---

## 🚀 Deploy in 5 Minutes

```bash
# 1. Clone repository
git clone https://github.com/jonathan-vella/azure-smb-rf.git
cd azure-smb-rf

# 2. Open in VS Code → F1 → "Dev Containers: Reopen in Container"

# 3. Authenticate (in Dev Container terminal)
az login
az account set --subscription "<your-subscription-id>"

# 4. Phase 0: Management Group Permissions (one-time, requires Global Admin)
cd scripts
./Setup-ManagementGroupPermissions.ps1

# 5. Phase 1+2: Configure and deploy (MG policies + infra in one step)
cd ../infra/bicep/smb-ready-foundation
azd env new smb-rf-baseline
azd env set SCENARIO baseline       # or: firewall, vpn, full
azd env set OWNER "partner-ops@contoso.com"
# For vpn/full: azd env set ON_PREMISES_ADDRESS_SPACE "192.168.0.0/16"
azd up                              # Deploys MG policies + subscription infra
```

---

## 💰 Scenario Comparison

| Scenario     | Use Case                        | Deploy Time | Monthly Cost |
| ------------ | ------------------------------- | ----------- | ------------ |
| **baseline** | Testing, cloud-only workloads   | ~4 min      | ~$48         |
| **firewall** | Egress filtering, compliance    | ~15 min     | ~$336        |
| **vpn**      | Hybrid connectivity, migrations | ~25 min     | ~$187        |
| **full**     | Enterprise: filtering + hybrid  | ~45 min     | ~$476        |

---

## 📦 What Gets Deployed

### All Scenarios Include

- Hub + Spoke VNet topology
- NAT Gateway (outbound internet)
- Azure Bastion Developer (portal-based VM access — no infrastructure deployed)
- Private DNS Zones (auto-registration + Key Vault PE)
- Log Analytics (500 MB/day cap)
- Recovery Services Vault (VM backup)
- Azure Migrate Project
- Azure Key Vault (RBAC, private endpoint, purge protection)
- Azure Automation Account (patch management)
- Microsoft Defender for Cloud (Free tier)
- 33 Azure Policy guardrails (30 at MG scope, 3 at subscription scope)
- Monthly budget alert ($500)

### Scenario-Specific

| Resource            | baseline | firewall | vpn | full |
| ------------------- | :------: | :------: | :-: | :--: |
| Azure Firewall      |    ❌    |    ✅    | ❌  |  ✅  |
| VPN Gateway         |    ❌    |    ❌    | ✅  |  ✅  |
| Hub-Spoke Peering   |    ❌    |    ✅    | ✅  |  ✅  |
| User-Defined Routes |    ❌    |    ✅    | ❌  |  ✅  |

---

## 🧹 Cleanup

Remove all resources when done testing:

```powershell
cd infra/bicep/smb-ready-foundation/scripts
./Remove-SmbReadyFoundation.ps1 -Location swedencentral -Force
# Optionally remove management group:
./Remove-SmbReadyFoundation.ps1 -Location swedencentral -Force -RemoveManagementGroup
```

> ⏱️ Cleanup takes 10-15 minutes

---

## 🆘 Support

| Issue                 | Solution                                                               |
| --------------------- | ---------------------------------------------------------------------- |
| Container won't start | Check Docker running, increase memory to 4GB+                          |
| Azure auth fails      | Try `az login --use-device-code`                                       |
| Deployment fails      | Check subscription has Owner role                                      |
| Need help             | [Open an issue](https://github.com/jonathan-vella/azure-smb-rf/issues) |

---

## 🔗 Quick Links

- [Full Documentation](../README.md)
- [Architecture Diagrams](images/)
- [Deployment Artifacts](../agent-output/smb-ready-foundation/)
- [Bicep Templates](../infra/bicep/smb-ready-foundation/)

---

<div align="center">

**Version 0.3.0** | [GitHub](https://github.com/jonathan-vella/azure-smb-rf) |
MIT License

</div>
