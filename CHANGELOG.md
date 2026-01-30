# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-01-30

### Added

- Full Azure Verified Modules (AVM) migration across 7 Bicep modules
- AVM module inventory in implementation reference (13 AVM modules total)
- Documented justified exceptions for modules without AVM support
- What-if validation for all deployment scenarios

### Changed

- **networking-hub.bicep** (v0.3): Migrated to AVM VNet 0.7.2, NSG 0.5.2, Private DNS 0.8.0
- **networking-spoke.bicep** (v0.3): Migrated to AVM VNet 0.7.2, NSG 0.5.2, NAT Gateway 2.0.1
- **vpn-gateway.bicep** (v0.3): Migrated to AVM virtual-network-gateway 0.10.1
- **firewall.bicep** (v0.5): Complete AVM migration with public-ip-address 0.12.0
- **monitoring.bicep** (v0.2): Migrated to AVM operational-insights/workspace 0.15.0
- **backup.bicep** (v0.2): Migrated to AVM recovery-services/vault 0.11.1
- **route-tables.bicep** (v0.2): Migrated to AVM network/route-table 0.5.0
- **networking-peering.bicep** (v0.3): Documented as justified exception (no AVM module)
- Updated 05-implementation-reference.md to artifact v0.2

### Fixed

- NAT Gateway AVM parameters (availabilityZone, publicIPAddresses array format)
- VPN Gateway AVM parameters (clusterSettings, virtualNetworkResourceId)
- Monitoring module dailyQuotaGb type conversion for AVM compatibility

## [0.1.0] - 2026-01-28

### Added

- Initial SMB Landing Zone implementation
- Hub-spoke network topology with Azure Bastion
- 4 deployment scenarios: baseline, firewall, vpn, full
- 21 Azure Policy assignments for governance
- Recovery Services Vault with DefaultVMPolicy
- Azure Migrate project for migration assessments
- Log Analytics Workspace with daily ingestion cap
- Cost Management Budget with alerts
- NAT Gateway for baseline outbound connectivity
- Azure Firewall Basic (optional) with network rules
- VPN Gateway VpnGw1AZ (optional) for hybrid connectivity
- Route tables for forced tunneling through firewall
- Agent-based workflow with 9 custom agents
- Comprehensive artifact templates (01-07)

### Security

- Deny-by-default NSG rules (priority 4096)
- Azure Bastion Developer SKU (no public IP)
- Private DNS Zone with auto-registration
- Soft delete on Recovery Services Vault
- VM backup auto-enrollment via Azure Policy

---

[0.2.0]: https://github.com/jonathan-vella/azure-agentic-smb-lz/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jonathan-vella/azure-agentic-smb-lz/releases/tag/v0.1.0
