# Azure Firewall Basic - Test Lab

## Purpose

Isolated test environment for validating Azure Firewall Basic deployment patterns following Azure Verified Modules (AVM) standards.

## Test Objectives

1. Validate Firewall Policy Basic tier deployment
2. Validate rule collection group sequencing
3. Validate Firewall Basic with management IP configuration
4. Document working patterns for incorporation into main landing zone

## Key Requirements (Azure Firewall Basic)

| Requirement            | Details                                                      |
| ---------------------- | ------------------------------------------------------------ |
| Management Subnet      | `AzureFirewallManagementSubnet` (/26 minimum) - **REQUIRED** |
| Management Public IP   | Separate Standard/Static public IP - **REQUIRED**            |
| Policy Tier            | Must match firewall tier (`Basic`)                           |
| Threat Intel Mode      | Only `Alert` or `Off` supported (not `Deny`)                 |
| DNS Proxy              | **NOT supported** on Basic                                   |
| Network FQDN filtering | **NOT supported** on Basic                                   |

## Test Resources

| Resource        | Name Pattern            | Purpose                     |
| --------------- | ----------------------- | --------------------------- |
| Resource Group  | `rg-fw-test-{region}`   | Test isolation              |
| VNet            | `vnet-fw-test-{region}` | Minimal hub with FW subnets |
| Firewall Policy | `fwpol-test-{region}`   | Basic tier policy           |
| Firewall        | `fw-test-{region}`      | Basic tier firewall         |
| Public IPs      | `pip-fw-*`              | Data + Management IPs       |

## Minimal Rules (Test Set)

| Rule | Protocol | Source | Destination   | Port |
| ---- | -------- | ------ | ------------- | ---- |
| DNS  | UDP/TCP  | VNet   | 168.63.129.16 | 53   |
| NTP  | UDP      | VNet   | \*            | 123  |

## Deployment

```bash
cd /workspaces/agentic-infraops-smb/infra/bicep/firewall-test
pwsh -File deploy.ps1
```

## Test Status

- [ ] VNet deployment
- [ ] Firewall Policy deployment
- [ ] Rule Collection Groups deployment
- [ ] Firewall deployment
- [ ] End-to-end validation
