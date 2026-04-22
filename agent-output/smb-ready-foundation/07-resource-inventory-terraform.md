---
title: "As-Built Resource Inventory - SMB Ready Foundations (Terraform)"
status: "Implemented"
date: "2026-04-17"
artifact_version: "1.0"
authors: "Terraform Code Agent"
tags: ["as-built", "resource-inventory", "terraform", "smb-ready-foundation"]
supersedes: ""
superseded_by: ""
companion: "07-resource-inventory.md"
---

# As-Built Resource Inventory — SMB Ready Foundations (Terraform)

> Terraform-track companion to [`07-resource-inventory.md`](./07-resource-inventory.md).
> Resource names, counts, and scenarios match the Bicep track 1:1, except for the
> `ManagedBy` tag value (`"Terraform"`).

## Summary by category

| Category                | Count (full scenario) | Notes                                                                   |
| ----------------------- | --------------------: | ----------------------------------------------------------------------- |
| Management group        |                     1 | `smb-rf` (imported if pre-existing).                                    |
| MG subscription link    |                     1 | Primary subscription association.                                       |
| Resource groups         |                     6 | 1 spoke + 5 shared (hub, monitoring, backup, migrate, mgmt).            |
| Virtual networks        |                     2 | Hub + spoke.                                                            |
| Subnets                 |                     8 | 4 hub + 4 spoke.                                                        |
| NSGs                    |                     2 | 1 per VNet.                                                             |
| Public IPs              |                     3 | 2 firewall + 1 VPN gateway.                                             |
| NAT gateway             |                0 or 1 | Present only when `deploy_firewall = false`.                            |
| Azure Firewall          |                0 or 1 | Basic tier; 2 rule collection groups.                                   |
| Firewall policy         |                0 or 1 | With Allow-Internet + Allow-VNet rule groups.                           |
| Route tables            |                1 or 2 | Spoke RT + optional `GatewaySubnet` RT.                                 |
| VPN gateway             |                0 or 1 | `VpnGw1AZ`; serialised after firewall.                                  |
| VNet peerings           |                0 or 2 | Hub↔spoke when `firewall` OR `vpn` enabled.                             |
| Private DNS zones       |                     1 | `privatelink.azure.com` shared.                                         |
| Private endpoints       |                     1 | Key Vault.                                                              |
| Log Analytics WS        |                     1 | 0.5 GB/day cap, 30-day retention.                                       |
| Recovery Services Vault |                     1 | With `DefaultVMPolicy`.                                                 |
| Migrate project         |                     1 | `azapi_resource`.                                                       |
| Key Vault               |                     1 | RBAC-enabled + purge protection.                                        |
| Automation Account      |                     1 | SystemAssigned identity + LAW linked service.                           |
| Diagnostic settings     |                    2+ | KV, Automation, policy-driven for others.                               |
| Budget                  |                     1 | `budget-smb-monthly`, 3 notifications.                                  |
| Defender pricings       |                     4 | VMs, Storage, KV, ARM — all Free tier.                                  |
| Auto-provisioning       |                     1 | Off.                                                                    |
| MG policy assignments   |                    33 | See `modules/policy-assignments-mg/`; output `policy_assignment_count`. |
| Sub policy assignment   |                     1 | `smb-backup-02` DINE.                                                   |
| Role assignments        |                     2 | Backup Contributor + VM Contributor for DINE MI.                        |

Total resources in the **full** scenario: ~74 (scenario dependent; `terraform plan`
against the target subscription produces the authoritative count).

## Management group hierarchy

```text
Tenant Root
└── smb-rf  (display name: "SMB Ready Foundations")
    └── <target subscription>
```

- Terraform resource: `azurerm_management_group.smb_rf`
- MG ID: `/providers/Microsoft.Management/managementGroups/smb-rf`
- Root-level `import` block in `main.tf` targets
  `module.management_group.azurerm_management_group.smb_rf` and ensures no failure
  if the MG pre-exists (e.g., created by Bicep or a prior Terraform run).
- `lifecycle.ignore_changes = [subscription_ids]` prevents drift on manual MG moves.

## Resource groups

| Name                                     | Purpose                 | Tag `ManagedBy` | Tag `Environment`      |
| ---------------------------------------- | ----------------------- | --------------- | ---------------------- |
| `rg-smbrf-{env}-{region_short}`          | Spoke workload          | `Terraform`     | `{env}` (e.g., `prod`) |
| `rg-smbrf-hub-smb-{region_short}`        | Hub networking          | `Terraform`     | `smb`                  |
| `rg-smbrf-monitoring-smb-{region_short}` | Log Analytics           | `Terraform`     | `smb`                  |
| `rg-smbrf-backup-smb-{region_short}`     | Recovery Services Vault | `Terraform`     | `smb`                  |
| `rg-smbrf-migrate-smb-{region_short}`    | Azure Migrate project   | `Terraform`     | `smb`                  |
| `rg-smbrf-mgmt-smb-{region_short}`       | KV + Automation         | `Terraform`     | `smb`                  |

`region_short` is `swc` (swedencentral) or `gwc` (germanywestcentral).

## Networking

### Hub VNet (`vnet-smbrf-hub-smb-{region_short}`)

| Subnet                          | CIDR derivation (from `/23` default)              | Notes          |
| ------------------------------- | ------------------------------------------------- | -------------- |
| `AzureFirewallSubnet`           | `cidrsubnet(hub, 26-prefix, 0)` — `10.0.0.0/26`   | Required name. |
| `AzureFirewallManagementSubnet` | `cidrsubnet(hub, 26-prefix, 1)` — `10.0.0.64/26`  | Required name. |
| `GatewaySubnet`                 | `cidrsubnet(hub, 27-prefix, 4)` — `10.0.0.128/27` | Required name. |
| `snet-management`               | `cidrsubnet(hub, 27-prefix, 5)` — `10.0.0.160/27` |                |

- NSG: `nsg-hub`, default deny-inbound.
- Private DNS zone `privatelink.azure.com` linked to hub and spoke VNets.

### Spoke VNet (`vnet-smbrf-spoke-{env}-{region_short}`)

| Subnet          | CIDR derivation (from `/23` default)                | Notes                                            |
| --------------- | --------------------------------------------------- | ------------------------------------------------ |
| `snet-workload` | `cidrsubnet(spoke, 26-prefix, 0)` — `10.0.2.0/26`   |                                                  |
| `snet-data`     | `cidrsubnet(spoke, 26-prefix, 1)` — `10.0.2.64/26`  |                                                  |
| `snet-app`      | `cidrsubnet(spoke, 27-prefix, 4)` — `10.0.2.128/27` |                                                  |
| `snet-pep`      | `cidrsubnet(spoke, 27-prefix, 5)` — `10.0.2.160/27` | `private_endpoint_network_policies = "Disabled"` |

- NSG: `nsg-spoke`, default deny-inbound.
- NAT gateway attached to `snet-workload` when `deploy_firewall = false`.

## Optional networking (scenario-gated)

### Firewall scenario (`deploy_firewall = true`)

| Resource                                                 | Name                                          |
| -------------------------------------------------------- | --------------------------------------------- |
| `azurerm_public_ip.fw_data`                              | `pip-fw-smbrf-smb-{region_short}`             |
| `azurerm_public_ip.fw_mgmt`                              | `pip-fwmgmt-smbrf-smb-{region_short}`         |
| `azurerm_firewall_policy.hub`                            | `afwp-smbrf-smb-{region_short}`               |
| `azurerm_firewall_policy_rule_collection_group.internet` | `rcg-allow-internet`                          |
| `azurerm_firewall_policy_rule_collection_group.vnet`     | `rcg-allow-vnet`                              |
| `azurerm_firewall.hub`                                   | `afw-smbrf-smb-{region_short}` (Basic SKU)    |
| `azurerm_route_table.spoke_to_fw`                        | Default route 0.0.0.0/0 → firewall private IP |
| `azurerm_subnet_route_table_association.workload`        | `snet-workload` → spoke RT                    |

### VPN scenario (`deploy_vpn = true`)

| Resource                              | Name                                        |
| ------------------------------------- | ------------------------------------------- |
| `azurerm_public_ip.vpn`               | `pip-vpn-smbrf-smb-{region_short}`          |
| `azurerm_virtual_network_gateway.vpn` | `vgw-smbrf-smb-{region_short}` (`VpnGw1AZ`) |
| `azurerm_route_table.gateway`         | Conditional when firewall also on           |
| `terraform_data.vpn_ready`            | Relay for peering gate                      |

### Peering (`deploy_firewall OR deploy_vpn`)

- `azurerm_virtual_network_peering.hub_to_spoke` / `.spoke_to_hub`
- `allow_gateway_transit = var.deploy_vpn`, `use_remote_gateways = var.deploy_vpn` on the
  spoke side.

## Monitoring, backup, security

| Resource                                              | Name                                          |
| ----------------------------------------------------- | --------------------------------------------- |
| `azurerm_log_analytics_workspace.main`                | `log-smbrf-smb-{region_short}` (0.5 GB/d cap) |
| `azurerm_recovery_services_vault.main`                | `rsv-smbrf-smb-{region_short}`                |
| `azurerm_backup_policy_vm.default`                    | `DefaultVMPolicy` (daily, 30d retention)      |
| `azurerm_consumption_budget_subscription.smb_monthly` | `budget-smb-monthly`                          |
| `azurerm_security_center_subscription_pricing.*` (4)  | Free tier: VMs, Storage, KV, ARM              |
| `azurerm_security_center_auto_provisioning.main`      | `Off` (cost reason)                           |

## Governance (policy-backup-auto)

| Resource                                             | Notes                                         |
| ---------------------------------------------------- | --------------------------------------------- |
| `azurerm_subscription_policy_assignment.backup_auto` | Subscription-scope DINE; tag-based include.   |
| `azurerm_role_assignment.backup_auto_backup`         | Backup Contributor to assignment MI.          |
| `azurerm_role_assignment.backup_auto_vm`             | Virtual Machine Contributor to assignment MI. |

## Management + data services

| Resource                                  | Name                                                                                |
| ----------------------------------------- | ----------------------------------------------------------------------------------- |
| `azapi_resource.migrate_project`          | `migrate-smbrf-smb-{region_short}` (`Microsoft.Migrate/migrateProjects@2020-05-01`) |
| `azurerm_key_vault.main`                  | `kv-smbrf-smb-{unique_suffix}`                                                      |
| `azurerm_private_endpoint.kv`             | `pe-kv-smbrf-smb-{region_short}` in `snet-pep`                                      |
| `azurerm_automation_account.main`         | `aa-smbrf-smb-{region_short}` (Basic)                                               |
| `azurerm_log_analytics_linked_service.aa` | Automation ↔ LAW linked service                                                     |

## Outputs surface

See `outputs.tf`. Example output for a full scenario:

```hcl
deployment_scenario       = "full"
feature_flags             = { firewall = true, vpn = true, nat = false, peering = true }
policy_assignment_count   = 33
unique_suffix             = "1a2b3c4d5e6f7"
key_vault_uri             = "https://kv-smbrf-smb-1a2b3c4d5e6f7.vault.azure.net/"
firewall_private_ip       = "10.0.0.4"
vpn_gateway_public_ip     = "20.x.x.x"
```

## References

- Bicep inventory: [`07-resource-inventory.md`](./07-resource-inventory.md)
- Terraform plan: [`04-implementation-plan-terraform.md`](./04-implementation-plan-terraform.md)
- Terraform reference: [`05-implementation-reference-terraform.md`](./05-implementation-reference-terraform.md)
- ADR-0005: [`07-ab-adr-0005-terraform-dual-track.md`](./07-ab-adr-0005-terraform-dual-track.md)
- ADR-0006: [`07-ab-adr-0006-terraform-single-root-composition.md`](./07-ab-adr-0006-terraform-single-root-composition.md)
