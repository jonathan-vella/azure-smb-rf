# GitHub Issue: AVM Migration

> **Title**: refactor(bicep): Migrate raw Bicep modules to Azure Verified Modules (AVM)
> **Labels**: enhancement
> **Create with**: `gh issue create --title "..." --body-file ISSUE-avm-migration.md --label enhancement`

---

## Summary

Per AVM-first policy enforcement (commit d9d3b76), the following modules need migration from raw Bicep to Azure Verified Modules.

## Current State

| Module | Current | Target AVM | Version | Priority |
|--------|---------|------------|---------|----------|
| `firewall.bicep` | ✅ AVM | - | 0.9.2 | Complete |
| `networking-hub.bicep` | ❌ Raw | VNet, NSG, Bastion, DNS | 0.7.2, 0.5.2, 0.8.2, 0.8.0 | High |
| `networking-spoke.bicep` | ❌ Raw | VNet, NSG, NAT, PIP | 0.7.2, 0.5.2, 2.0.1, 0.12.0 | High |
| `vpn-gateway.bicep` | ❌ Raw | `virtual-network-gateway` | 0.10.1 | High |
| `backup.bicep` | ❌ Raw | `recovery-services/vault` | 0.11.1 | Medium |
| `monitoring.bicep` | ❌ Raw | `operational-insights/workspace` | 0.15.0 | Medium |
| `route-tables.bicep` | ❌ Raw | `route-table` | 0.5.0 | Medium |
| `budget.bicep` | ❌ Raw | `consumption/budget` | 0.3.8 | Low |
| `resource-groups.bicep` | ❌ Raw | `resources/resource-group` | 0.4.3 | Low |

## Justified Exceptions

- `migrate.bicep` - No AVM module exists for Azure Migrate
- `policy-*.bicep` - Raw ARM simplest for subscription-scope policies

## Acceptance Criteria

- [ ] All High priority modules migrated to AVM
- [ ] All Medium priority modules migrated to AVM
- [ ] All Low priority modules migrated to AVM
- [ ] Bicep linting passes after migration
- [ ] All scenarios still deploy successfully (baseline/firewall/vpn/full)

## References

- [AVM Module Index](https://aka.ms/avm/index)
- Guardrails implemented in: `_shared/defaults.md`, `bicep-code.agent.md`, `bicep-plan.agent.md`
