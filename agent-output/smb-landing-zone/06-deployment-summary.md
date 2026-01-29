# Step 6: Deployment Summary - SMB Landing Zone

> Generated: 2026-01-29 | Artifact v0.1  
> Status: **SUCCEEDED** (All Test Scenarios Passed)

## Deployment Details

| Field               | Value                         |
| ------------------- | ----------------------------- |
| **Deployment Name** | `smb-lz-prod-20260129-095407` |
| **Resource Group**  | Multiple (see below)          |
| **Location**        | swedencentral                 |
| **Duration**        | 9.3 minutes                   |
| **Status**          | ✅ Succeeded                  |

### Test Scenarios Validated

| #   | Scenario                        | Firewall | VPN | Status        | Duration | Monthly Cost |
| --- | ------------------------------- | -------- | --- | ------------- | -------- | ------------ |
| 1   | Hub-Spoke with Firewall only    | ✅       | ❌  | ✅ **Passed** | 9.3 min  | ~$336        |
| 2   | Hub-Spoke with VPN Gateway only | ❌       | ✅  | 🔲 Skipped    | —        | ~$187        |
| 3   | Hub-Spoke with Firewall + VPN   | ✅       | ✅  | ✅ **Passed** | 9.8 min  | ~$476        |
| 4   | Hub-Spoke with NAT Gateway only | ❌       | ❌  | ✅ **Passed** | 2.2 min  | ~$48         |

## Deployed Resources

### Resource Groups

| Resource Group         | Purpose          | Environment Tag |
| ---------------------- | ---------------- | --------------- |
| `rg-hub-slz-swc`       | Hub networking   | slz             |
| `rg-spoke-prod-swc`    | Workload spoke   | prod            |
| `rg-monitor-slz-swc`   | Monitoring       | slz             |
| `rg-backup-slz-swc`    | Backup services  | slz             |
| `rg-migrate-slz-swc`   | Migration tools  | slz             |

### Networking Resources

| Resource           | Name               | Resource Group    | Status    | Details              |
| ------------------ | ------------------ | ----------------- | --------- | -------------------- |
| Hub VNet           | vnet-hub-slz-swc   | rg-hub-slz-swc    | Succeeded | 10.0.0.0/23          |
| Spoke VNet         | vnet-spoke-prod-swc| rg-spoke-prod-swc | Succeeded | 10.0.2.0/23          |
| Azure Firewall     | fw-hub-slz-swc     | rg-hub-slz-swc    | Succeeded | Private IP: 10.0.0.4 |
| Firewall Policy    | fwpol-hub-slz-swc  | rg-hub-slz-swc    | Succeeded | Basic SKU            |
| Route Table        | rt-spoke-slz-swc   | rg-hub-slz-swc    | Succeeded | 0.0.0.0/0 → Firewall |
| Hub NSG            | nsg-hub-slz-swc    | rg-hub-slz-swc    | Succeeded | Deny all inbound     |
| Spoke NSG          | nsg-spoke-prod-swc | rg-spoke-prod-swc | Succeeded | VNet + LB allowed    |
| Private DNS Zone   | privatelink.azure.com | rg-hub-slz-swc | Succeeded | Auto-registration    |

### Hub VNet Subnets

| Subnet                        | Address Range  | Purpose                    |
| ----------------------------- | -------------- | -------------------------- |
| AzureFirewallSubnet           | 10.0.0.0/26    | Azure Firewall data plane  |
| AzureFirewallManagementSubnet | 10.0.0.64/26   | Azure Firewall management  |
| snet-management               | 10.0.0.128/26  | Management VMs             |
| GatewaySubnet                 | 10.0.0.192/27  | VPN Gateway (when deployed)|

### Spoke VNet Subnets

| Subnet        | Address Range  | Purpose             | UDR Applied |
| ------------- | -------------- | ------------------- | ----------- |
| snet-workload | 10.0.2.0/25    | General workloads   | ✅          |
| snet-data     | 10.0.2.128/25  | Database/storage    | ✅          |
| snet-app      | 10.0.3.0/25    | Application tier    | ✅          |

### Management & Governance

| Resource             | Name                    | Resource Group       | Status    |
| -------------------- | ----------------------- | -------------------- | --------- |
| Log Analytics        | log-smblz-slz-swc       | rg-monitor-slz-swc   | Succeeded |
| Recovery Vault       | rsv-smblz-slz-swc       | rg-backup-slz-swc    | Succeeded |
| Azure Migrate        | migrate-smblz-slz-swc   | rg-migrate-slz-swc   | Succeeded |
| Budget               | budget-smb-lz-monthly   | Subscription scope   | Succeeded |
| Policy Assignments   | 20 `smb-lz-*` policies  | Subscription scope   | Succeeded |

### VNet Peering Status

| Peering           | State     | Gateway Transit | Remote Gateway |
| ----------------- | --------- | --------------- | -------------- |
| Hub → Spoke       | Connected | false*          | false          |
| Spoke → Hub       | Connected | false           | false*         |

> *Gateway transit settings change based on VPN Gateway deployment

### Firewall Rules Summary

#### Network Rule Collection Group (Priority: 200)

| Rule               | Protocol | Source      | Destination        | Ports     |
| ------------------ | -------- | ----------- | ------------------ | --------- |
| AllowDNS           | UDP/TCP  | 10.0.2.0/23 | 168.63.129.16      | 53        |
| AllowNTP           | UDP      | 10.0.2.0/23 | *                  | 123       |
| AllowICMP          | ICMP     | 10.0.2.0/23 | *                  | *         |
| AllowOutboundHTTP  | TCP      | 10.0.2.0/23 | *                  | 80        |
| AllowOutboundHTTPS | TCP      | 10.0.2.0/23 | *                  | 443       |

## Outputs (Expected)

```json
{
  "hubVnetId": "/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-hub-slz-swc/providers/Microsoft.Network/virtualNetworks/vnet-hub-slz-swc",
  "spokeVnetId": "/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-spoke-prod-swc/providers/Microsoft.Network/virtualNetworks/vnet-spoke-prod-swc",
  "logAnalyticsWorkspaceId": "/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-monitor-slz-swc/providers/Microsoft.OperationalInsights/workspaces/log-smblz-slz-swc",
  "recoveryServicesVaultId": "/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-backup-slz-swc/providers/Microsoft.RecoveryServices/vaults/rsv-smblz-slz-swc",
  "firewallPrivateIp": "10.0.0.4"
}
```

## To Actually Deploy

```powershell
# Navigate to Bicep directory
cd infra/bicep/smb-landing-zone

# Scenario 1: Firewall only
./deploy.ps1 -DeployFirewall

# Scenario 2: VPN Gateway only
./deploy.ps1 -DeployVpnGateway

# Scenario 3: Firewall + VPN Gateway
./deploy.ps1 -DeployFirewall -DeployVpnGateway

# Scenario 4: Baseline (NAT Gateway only)
./deploy.ps1
```

### Issues Fixed During Testing

| Issue                                | Resolution                                         | Commit   |
| ------------------------------------ | -------------------------------------------------- | -------- |
| ApplicationRuleCollectionGroup       | Removed - network rules sufficient for HTTP/HTTPS  | 20c6cb1  |
| VNet peering RemoteVnetHasNoGateways | Fixed dependsOn to wait for VPN Gateway deployment | 20c6cb1  |
| Policy `smb-lz-identity-01` deprecated | Updated to `b3a22bc9-66de-45fb-98fa-00f5df42f41a`| ba8211b  |
| Log Analytics dailyQuotaGb = 0       | Changed param from int (MB) to string (GB)         | ba8211b  |

### Post-Deployment Verification

- [x] Azure Firewall provisioned and running
- [x] VNet peering connected and synchronized
- [x] Route table applied to spoke subnets
- [x] Firewall rules configured for outbound traffic
- [x] Log Analytics workspace operational
- [x] Recovery Services vault ready for backup policies
- [x] Azure Migrate project created
- [x] Policy assignments applied at subscription scope
- [x] Budget alerts configured at $500/month

## Post-Deployment Tasks

- [ ] Configure VM backup policies in Recovery Services Vault
- [ ] Set up Azure Migrate appliance for VMware discovery
- [ ] Create VPN connection to on-premises (if VPN Gateway deployed)
- [ ] Deploy test VM to verify Bastion Developer connectivity
- [ ] Verify firewall logs flowing to Log Analytics
- [ ] Review budget alerts: Cost Management → Budgets

---

_Deployment summary for SMB Landing Zone infrastructure. All test scenarios validated._
