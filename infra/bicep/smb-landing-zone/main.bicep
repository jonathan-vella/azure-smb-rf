// ============================================================================
// SMB Landing Zone - Main Orchestration Template
// ============================================================================
// Purpose: Cost-optimized Azure landing zone for VMware-to-Azure migrations
// Version: v0.1
// Generated: 2026-01-28
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Primary deployment region')
@allowed([
  'swedencentral'
  'germanywestcentral'
])
param location string = 'swedencentral'

@description('Environment name for resource naming and tagging')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'prod'

@description('Owner email or team name (required for tagging)')
param owner string

@description('Hub VNet address space CIDR')
param hubVnetAddressSpace string = '10.0.0.0/16'

@description('Spoke VNet address space CIDR')
param spokeVnetAddressSpace string = '10.1.0.0/16'

@description('Deploy Azure Firewall Basic (adds ~$277/month)')
param deployFirewall bool = false

@description('Deploy VPN Gateway for hybrid connectivity')
param deployVpnGateway bool = false

@description('VPN Gateway SKU (Basic for dev/test, VpnGw1AZ for production)')
@allowed([
  'Basic'
  'VpnGw1AZ'
])
param vpnGatewaySku string = 'Basic'

@description('Log Analytics daily ingestion cap in MB')
@minValue(100)
@maxValue(5000)
param logAnalyticsDailyCapMb int = 500

@description('Monthly budget amount in USD')
@minValue(100)
@maxValue(10000)
param budgetAmount int = 500

@description('Budget alert email address')
param budgetAlertEmail string = owner

@description('Deployment timestamp for budget start date')
param deploymentTimestamp string = utcNow('yyyy-MM-01')

// ============================================================================
// Variables
// ============================================================================

// Unique suffix for globally unique resource names
var uniqueSuffix = uniqueString(subscription().subscriptionId)

// Region abbreviation for naming
var regionAbbreviations = {
  swedencentral: 'swc'
  germanywestcentral: 'gwc'
}
var regionShort = regionAbbreviations[location]

// Determine if peering is needed (requires Firewall or VPN Gateway)
var deployPeering = deployFirewall || deployVpnGateway

// Tags for shared services (hub, monitor, backup, migrate) - hardcoded 'slz'
var sharedServicesTags = {
  Environment: 'slz'
  Owner: owner
  Project: 'smb-landing-zone'
  ManagedBy: 'Bicep'
}

// Tags for spoke resources (environment-specific)
var spokeTags = {
  Environment: environment
  Owner: owner
  Project: 'smb-landing-zone'
  ManagedBy: 'Bicep'
}

// Resource group names - shared services use 'slz', spoke uses environment
var rgNames = {
  hub: 'rg-hub-slz-${regionShort}'
  spoke: 'rg-spoke-${environment}-${regionShort}'
  monitor: 'rg-monitor-slz-${regionShort}'
  backup: 'rg-backup-slz-${regionShort}'
  migrate: 'rg-migrate-slz-${regionShort}'
}

// ============================================================================
// Module Deployments
// ============================================================================

// ----------------------------------------------------------------------------
// Phase 1: Subscription-Scope Resources (Policies + Budget)
// ----------------------------------------------------------------------------

@description('Deploy 20 Azure Policy assignments at subscription scope')
module policyAssignments 'modules/policy-assignments.bicep' = {
  name: 'policy-assignments-${uniqueSuffix}'
  params: {
    location: location
  }
}

@description('Deploy Cost Management budget with alerts')
module budget 'modules/budget.bicep' = {
  name: 'budget-${uniqueSuffix}'
  params: {
    budgetAmount: budgetAmount
    alertEmail: budgetAlertEmail
    startDate: deploymentTimestamp
  }
}

// ----------------------------------------------------------------------------
// Phase 2: Resource Groups
// ----------------------------------------------------------------------------

@description('Create 5 resource groups for landing zone workloads')
module resourceGroups 'modules/resource-groups.bicep' = {
  name: 'resource-groups-${uniqueSuffix}'
  params: {
    location: location
    environment: environment
    regionShort: regionShort
    sharedServicesTags: sharedServicesTags
    spokeTags: spokeTags
  }
  dependsOn: [
    policyAssignments
  ]
}

// ----------------------------------------------------------------------------
// Phase 3: Core Networking
// ----------------------------------------------------------------------------

@description('Deploy hub VNet with Bastion, NSG, and Private DNS Zone')
module networkingHub 'modules/networking-hub.bicep' = {
  name: 'networking-hub-${uniqueSuffix}'
  scope: resourceGroup(rgNames.hub)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    vnetAddressSpace: hubVnetAddressSpace
    tags: sharedServicesTags
  }
  dependsOn: [
    resourceGroups
  ]
}

@description('Deploy spoke VNet with NAT Gateway and NSG')
module networkingSpoke 'modules/networking-spoke.bicep' = {
  name: 'networking-spoke-${uniqueSuffix}'
  scope: resourceGroup(rgNames.spoke)
  params: {
    location: location
    environment: environment
    regionShort: regionShort
    vnetAddressSpace: spokeVnetAddressSpace
    tags: spokeTags
  }
  dependsOn: [
    resourceGroups
  ]
}

// ----------------------------------------------------------------------------
// Phase 4: Supporting Services
// ----------------------------------------------------------------------------

@description('Deploy Log Analytics Workspace with daily cap')
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-${uniqueSuffix}'
  scope: resourceGroup(rgNames.monitor)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    dailyCapMb: logAnalyticsDailyCapMb
    tags: sharedServicesTags
  }
  dependsOn: [
    resourceGroups
  ]
}

@description('Deploy Recovery Services Vault for VM backup')
module backup 'modules/backup.bicep' = {
  name: 'backup-${uniqueSuffix}'
  scope: resourceGroup(rgNames.backup)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    tags: sharedServicesTags
  }
  dependsOn: [
    resourceGroups
  ]
}

@description('Deploy Azure Migrate project for VMware assessment')
module migrate 'modules/migrate.bicep' = {
  name: 'migrate-${uniqueSuffix}'
  scope: resourceGroup(rgNames.migrate)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    tags: sharedServicesTags
  }
  dependsOn: [
    resourceGroups
  ]
}

// ----------------------------------------------------------------------------
// Phase 5: Optional Services (Firewall, VPN Gateway)
// ----------------------------------------------------------------------------

@description('Deploy Azure Firewall Basic (optional)')
module firewall 'modules/firewall.bicep' = if (deployFirewall) {
  name: 'firewall-${uniqueSuffix}'
  scope: resourceGroup(rgNames.hub)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    firewallSubnetId: networkingHub.outputs.firewallSubnetId
    tags: sharedServicesTags
  }
}

@description('Deploy VPN Gateway (optional)')
module vpnGateway 'modules/vpn-gateway.bicep' = if (deployVpnGateway) {
  name: 'vpn-gateway-${uniqueSuffix}'
  scope: resourceGroup(rgNames.hub)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    gatewaySubnetId: networkingHub.outputs.gatewaySubnetId
    vpnGatewaySku: vpnGatewaySku
    tags: sharedServicesTags
  }
}

// ----------------------------------------------------------------------------
// Phase 6: VNet Peering (Conditional - only if Firewall or VPN deployed)
// ----------------------------------------------------------------------------

@description('Configure hub-spoke VNet peering (conditional)')
module networkingPeering 'modules/networking-peering.bicep' = if (deployPeering) {
  name: 'networking-peering-${uniqueSuffix}'
  scope: resourceGroup(rgNames.hub)
  params: {
    hubVnetName: networkingHub.outputs.vnetName
    hubVnetId: networkingHub.outputs.vnetId
    spokeVnetName: networkingSpoke.outputs.vnetName
    spokeVnetId: networkingSpoke.outputs.vnetId
    spokeResourceGroupName: rgNames.spoke
    useRemoteGateway: deployVpnGateway
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource group names for reference')
output resourceGroupNames object = rgNames

@description('Hub VNet resource ID')
output hubVnetId string = networkingHub.outputs.vnetId

@description('Spoke VNet resource ID')
output spokeVnetId string = networkingSpoke.outputs.vnetId

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId

@description('Recovery Services Vault ID')
output recoveryServicesVaultId string = backup.outputs.vaultId

@description('Azure Migrate Project ID')
output migrateProjectId string = migrate.outputs.projectId

@description('Azure Bastion name (for connection reference)')
output bastionName string = networkingHub.outputs.bastionName

@description('NAT Gateway public IP address')
output natGatewayPublicIp string = networkingSpoke.outputs.natGatewayPublicIp

@description('Azure Firewall private IP (if deployed)')
#disable-next-line BCP318
output firewallPrivateIp string = deployFirewall && firewall != null ? firewall.outputs.firewallPrivateIp : ''

@description('VPN Gateway public IP (if deployed)')
#disable-next-line BCP318
output vpnGatewayPublicIp string = deployVpnGateway && vpnGateway != null ? vpnGateway.outputs.gatewayPublicIp : ''
