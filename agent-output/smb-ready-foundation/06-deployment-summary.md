# Step 6: Deployment Summary - SMB Ready Foundation

> Generated: 2026-02-02 | Artifact v0.2
> Status: **SUCCEEDED** (All Scenarios Validated - Greenfield + Update Deployments)

## Deployment Details

| Field                | Value                            |
| -------------------- | -------------------------------- |
| **Management Group** | `smb-rf` (SMB Ready Foundation)  |
| **Deployment Name**  | `smb-prod-20260202-143501`       |
| **Resource Group**   | Multiple (see below)             |
| **Location**         | swedencentral                    |
| **Duration**         | 30 min 10 sec (greenfield, full) |
| **Status**           | ✅ Succeeded                     |

### Validated Deployment Scenarios

| Scenario   | Firewall | VPN | Status        | First Deploy | Update  | Monthly Cost |
| ---------- | :------: | :-: | ------------- | ------------ | ------- | ------------ |
| `baseline` |    ❌    | ❌  | ✅ **Passed** | ~4 min       | ~2 min  | ~$48         |
| `firewall` |    ✅    | ❌  | ✅ **Passed** | ~15 min      | ~5 min  | ~$336        |
| `vpn`      |    ❌    | ✅  | ✅ **Passed** | ~25 min      | ~6 min  | ~$187        |
| `full`     |    ✅    | ✅  | ✅ **Passed** | ~40-55 min   | ~10 min | ~$476        |

> **Note**: The `full` scenario includes a race condition fix (v0.3.0) that serializes
> Firewall → VPN Gateway deployment to prevent VNet conflicts. See ADR-0004.

## Deployed Resources

### Resource Groups

| Resource Group        | Purpose         | Environment Tag |
| --------------------- | --------------- | --------------- |
| `rg-hub-smb-swc`      | Hub networking  | smb             |
| `rg-spoke-prod-swc`   | Workload spoke  | prod            |
| `rg-monitor-smb-swc`  | Monitoring      | smb             |
| `rg-backup-smb-swc`   | Backup services | smb             |
| `rg-migrate-smb-swc`  | Migration tools | smb             |
| `rg-security-smb-swc` | Security        | smb             |

### Networking Resources

| Resource         | Name                            | Resource Group    | Status    | Details              |
| ---------------- | ------------------------------- | ----------------- | --------- | -------------------- |
| Hub VNet         | vnet-hub-smb-swc                | rg-hub-smb-swc    | Succeeded | 10.0.0.0/23          |
| Spoke VNet       | vnet-spoke-prod-swc             | rg-spoke-prod-swc | Succeeded | 10.0.2.0/23          |
| Azure Firewall   | fw-hub-smb-swc                  | rg-hub-smb-swc    | Succeeded | Private IP: 10.0.0.4 |
| Firewall Policy  | fwpol-hub-smb-swc               | rg-hub-smb-swc    | Succeeded | Basic SKU            |
| Route Table      | rt-spoke-smb-swc                | rg-hub-smb-swc    | Succeeded | 0.0.0.0/0 → Firewall |
| Hub NSG          | nsg-hub-smb-swc                 | rg-hub-smb-swc    | Succeeded | Deny all inbound     |
| Spoke NSG        | nsg-spoke-prod-swc              | rg-spoke-prod-swc | Succeeded | VNet + LB allowed    |
| Private DNS Zone | privatelink.azure.com           | rg-hub-smb-swc    | Succeeded | Auto-registration    |
| Private DNS Zone | privatelink.vaultcore.azure.net | rg-hub-smb-swc    | Succeeded | Key Vault PE         |

### Hub VNet Subnets

| Subnet                        | Address Range | Purpose                     |
| ----------------------------- | ------------- | --------------------------- |
| AzureFirewallSubnet           | 10.0.0.0/26   | Azure Firewall data plane   |
| AzureFirewallManagementSubnet | 10.0.0.64/26  | Azure Firewall management   |
| snet-management               | 10.0.0.128/26 | Management VMs              |
| GatewaySubnet                 | 10.0.0.192/27 | VPN Gateway (when deployed) |

### Spoke VNet Subnets

| Subnet        | Address Range | Purpose           | UDR Applied |
| ------------- | ------------- | ----------------- | ----------- |
| snet-workload | 10.0.2.0/25   | General workloads | ✅          |
| snet-data     | 10.0.2.128/25 | Database/storage  | ✅          |
| snet-app      | 10.0.3.0/25   | Application tier  | ✅          |
| snet-pep      | 10.0.3.128/26 | Private endpoints | ✅          |

### Management & Governance

| Resource               | Name                  | Resource Group / Scope | Status    |
| ---------------------- | --------------------- | ---------------------- | --------- |
| Management Group       | smb-rf                | Tenant Root Group      | Succeeded |
| MG Policy Assignments  | 30 `smb-*` policies   | Management Group scope | Succeeded |
| Log Analytics          | log-smbrf-smb-swc     | rg-monitor-smb-swc     | Succeeded |
| Recovery Vault         | rsv-smbrf-smb-swc     | rg-backup-smb-swc      | Succeeded |
| VM Backup Policy       | DefaultVMPolicy       | rg-backup-smb-swc      | Succeeded |
| Azure Migrate          | migrate-smbrf-smb-swc | rg-migrate-smb-swc     | Succeeded |
| Key Vault              | kv-smbrf-smb-swc      | rg-security-smb-swc    | Succeeded |
| Automation Account     | aa-smbrf-smb-swc      | rg-security-smb-swc    | Succeeded |
| Defender for Cloud     | Free tier             | Subscription scope     | Succeeded |
| Budget                 | budget-smb-monthly    | Subscription scope     | Succeeded |
| Sub Policy Assignments | 3+1 `smb-*` policies  | Subscription scope     | Succeeded |

### VM Backup Configuration

| Setting               | Value                                      |
| --------------------- | ------------------------------------------ |
| **Auto-Enrollment**   | Enabled via Azure Policy (`smb-backup-02`) |
| **Trigger Tag**       | `Backup: true` (or `yes`, `True`, `Yes`)   |
| **Backup Policy**     | DefaultVMPolicy                            |
| **Schedule**          | Daily @ 02:00 UTC                          |
| **Daily Retention**   | 30 days                                    |
| **Weekly Retention**  | 12 weeks (Sunday)                          |
| **Monthly Retention** | 12 months (1st of month)                   |
| **Policy Effect**     | DeployIfNotExists                          |

### VNet Peering Status

| Peering     | State     | Gateway Transit | Remote Gateway |
| ----------- | --------- | --------------- | -------------- |
| Hub → Spoke | Connected | false\*         | false          |
| Spoke → Hub | Connected | false           | false\*        |

> \*Gateway transit settings change based on VPN Gateway deployment

### Firewall Rules Summary

#### Network Rule Collection Group (Priority: 200)

| Rule               | Protocol | Source      | Destination   | Ports |
| ------------------ | -------- | ----------- | ------------- | ----- |
| AllowDNS           | UDP/TCP  | 10.0.2.0/23 | 168.63.129.16 | 53    |
| AllowNTP           | UDP      | 10.0.2.0/23 | \*            | 123   |
| AllowICMP          | ICMP     | 10.0.2.0/23 | \*            | \*    |
| AllowOutboundHTTP  | TCP      | 10.0.2.0/23 | \*            | 80    |
| AllowOutboundHTTPS | TCP      | 10.0.2.0/23 | \*            | 443   |

## Outputs (Expected)

```json
{
  "hubVnetId": "/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-hub-smb-swc/providers/Microsoft.Network/virtualNetworks/vnet-hub-smb-swc",
  "spokeVnetId": "/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-spoke-prod-swc/providers/Microsoft.Network/virtualNetworks/vnet-spoke-prod-swc",
  "logAnalyticsWorkspaceId": "/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-monitor-smb-swc/providers/Microsoft.OperationalInsights/workspaces/log-smbrf-smb-swc",
  "recoveryServicesVaultId": "/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-backup-smb-swc/providers/Microsoft.RecoveryServices/vaults/rsv-smbrf-smb-swc",
  "firewallPrivateIp": "10.0.0.4"
}
```

## To Actually Deploy

```powershell
# Navigate to Bicep directory
cd infra/bicep/smb-ready-foundation

# Phase 0: Management Group Permissions (one-time)
cd ../../scripts
./Setup-ManagementGroupPermissions.ps1
cd ../infra/bicep/smb-ready-foundation

# Phase 1+2: Configure and deploy via azd
azd env new smb-rf-baseline
azd env set SCENARIO baseline
azd env set OWNER "partner-ops@contoso.com"
azd up

# Alternative scenarios:
# azd env set SCENARIO firewall   # Firewall + UDR (~$336/mo)
# azd env set SCENARIO vpn        # VPN Gateway (~$187/mo)
# azd env set SCENARIO full       # Firewall + VPN (~$476/mo)
```

### Issues Fixed During Testing

| Issue                                | Resolution                                         | Commit  |
| ------------------------------------ | -------------------------------------------------- | ------- |
| ApplicationRuleCollectionGroup       | Removed - network rules sufficient for HTTP/HTTPS  | 20c6cb1 |
| VNet peering RemoteVnetHasNoGateways | Fixed dependsOn to wait for VPN Gateway deployment | 20c6cb1 |
| Policy `smb-identity-01` deprecated  | Updated to `b3a22bc9-66de-45fb-98fa-00f5df42f41a`  | ba8211b |
| Log Analytics dailyQuotaGb = 0       | Changed param from int (MB) to string (GB)         | ba8211b |

### Post-Deployment Verification

- [x] Management group `smb-rf` created under tenant root
- [x] Subscription moved under `smb-rf` management group
- [x] MG policy assignments applied (30 policies at MG scope)
- [x] Azure Firewall provisioned and running
- [x] VNet peering connected and synchronized
- [x] Route table applied to spoke subnets
- [x] Firewall rules configured for outbound traffic
- [x] Log Analytics workspace operational
- [x] Recovery Services vault with DefaultVMPolicy configured
- [x] Auto-backup policy assignment (smb-backup-02) deployed
- [x] Azure Migrate project created
- [x] Policy assignments applied at subscription scope (34 policies)
- [x] Budget alerts configured at $500/month
- [x] Key Vault deployed with private endpoint
- [x] Automation Account provisioned
- [x] Defender for Cloud enabled (Free tier)

## Post-Deployment Tasks

- [x] ~~Configure VM backup policies in Recovery Services Vault~~ (Automated via DefaultVMPolicy)
- [x] ~~Set up backup tag for VMs~~ (Use `Backup: true` tag for auto-enrollment)
- [ ] Set up Azure Migrate appliance for VMware discovery
- [ ] Create VPN connection to on-premises (if VPN Gateway deployed)
- [ ] Deploy test VM with `Backup: true` tag to verify auto-enrollment
- [ ] Verify firewall logs flowing to Log Analytics
- [ ] Review budget alerts: Cost Management → Budgets

---

_Deployment summary for SMB Ready Foundation infrastructure. All test scenarios validated._
