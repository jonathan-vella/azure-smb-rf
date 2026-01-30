// ============================================================================
// SMB Landing Zone - Main Orchestration Template
// ============================================================================
// Purpose: Cost-optimized Azure landing zone for VMware-to-Azure migrations
// Version: v0.2
// Generated: 2026-01-29
// ============================================================================
// Deployment Scenarios:
// - baseline:   NAT Gateway only (~$48/mo) - cloud-native, no hybrid
// - firewall:   Azure Firewall + UDR (~$336/mo) - egress filtering
// - vpn:        VPN Gateway + Gateway Transit (~$187/mo) - hybrid connectivity
// - full:       Firewall + VPN + UDR (~$476/mo) - complete security
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Deployment scenario preset (determines which optional services are deployed)')
@allowed([
  'baseline'
  'firewall'
  'vpn'
  'full'
])
param scenario string = 'baseline'

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

@description('On-premises network address space CIDR (for VPN routing)')
param onPremisesAddressSpace string = ''

@description('Log Analytics daily ingestion cap in GB (decimal, e.g. 0.5 for ~500MB)')
param logAnalyticsDailyCapGb string = '0.5'

@description('Monthly budget amount in USD')
@minValue(100)
@maxValue(10000)
param budgetAmount int = 500

@description('Budget alert email address')
param budgetAlertEmail string = owner

@description('Deployment timestamp for budget start date')
param deploymentTimestamp string = utcNow('yyyy-MM-01')

// ============================================================================
// Variables - Scenario-Derived Feature Flags
// ============================================================================

// Derive feature flags from scenario parameter
var deployFirewall = scenario == 'firewall' || scenario == 'full'
var deployVpnGateway = scenario == 'vpn' || scenario == 'full'

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

// Determine if NAT Gateway should be deployed (only when no firewall)
var deploySpokeNatGateway = !deployFirewall

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

@description('Deploy hub VNet with NSG and Private DNS Zone')
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

@description('Deploy spoke VNet with conditional NAT Gateway')
module networkingSpoke 'modules/networking-spoke.bicep' = {
  name: 'networking-spoke-${uniqueSuffix}'
  scope: resourceGroup(rgNames.spoke)
  params: {
    location: location
    environment: environment
    regionShort: regionShort
    vnetAddressSpace: spokeVnetAddressSpace
    deployNatGateway: deploySpokeNatGateway
    #disable-next-line BCP318
    routeTableId: deployFirewall ? routeTables.outputs.spokeRouteTableId : ''
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
    dailyCapGb: logAnalyticsDailyCapGb
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
// Phase 5: Optional Services (Firewall, Route Tables, VPN Gateway)
// ----------------------------------------------------------------------------

@description('Deploy Azure Firewall Basic with sequential PIP creation for reliability (optional)')
module firewall 'modules/firewall.bicep' = if (deployFirewall) {
  name: 'firewall-${uniqueSuffix}'
  scope: resourceGroup(rgNames.hub)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    hubVnetId: networkingHub.outputs.vnetId
    spokeAddressSpace: spokeVnetAddressSpace
    onPremisesAddressSpace: onPremisesAddressSpace
    tags: sharedServicesTags
  }
}

@description('Deploy route tables for firewall routing (conditional)')
module routeTables 'modules/route-tables.bicep' = if (deployFirewall) {
  name: 'route-tables-${uniqueSuffix}'
  scope: resourceGroup(rgNames.hub)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    #disable-next-line BCP318
    firewallPrivateIp: firewall.outputs.firewallPrivateIp
    spokeAddressSpace: spokeVnetAddressSpace
    onPremisesAddressSpace: onPremisesAddressSpace
    tags: sharedServicesTags
  }
}

@description('Deploy VPN Gateway VpnGw1AZ (optional, zone-redundant)')
module vpnGateway 'modules/vpn-gateway.bicep' = if (deployVpnGateway) {
  name: 'vpn-gateway-${uniqueSuffix}'
  scope: resourceGroup(rgNames.hub)
  params: {
    location: location
    environment: 'slz'
    regionShort: regionShort
    gatewaySubnetId: networkingHub.outputs.gatewaySubnetId
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
    location: location
    environment: 'slz'
    regionShort: regionShort
    tags: sharedServicesTags
    hubVnetName: networkingHub.outputs.vnetName
    hubVnetId: networkingHub.outputs.vnetId
    spokeVnetName: networkingSpoke.outputs.vnetName
    spokeVnetId: networkingSpoke.outputs.vnetId
    spokeResourceGroupName: rgNames.spoke
    allowGatewayTransit: deployVpnGateway
    useRemoteGateways: deployVpnGateway
  }
  // Peering must wait for VPN Gateway when useRemoteGateway is true
  // Always include vpnGateway in dependsOn when deployVpnGateway is true
  #disable-next-line BCP319
  dependsOn: [
    vpnGateway
  ]
}

// ============================================================================
// Outputs
// ============================================================================

@description('Deployment scenario used')
output deploymentScenario string = scenario

@description('Feature flags derived from scenario')
output featureFlags object = {
  firewall: deployFirewall
  vpnGateway: deployVpnGateway
  natGateway: deploySpokeNatGateway
  peering: deployPeering
}

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

@description('NAT Gateway public IP address (if deployed)')
output natGatewayPublicIp string = networkingSpoke.outputs.natGatewayPublicIp

@description('Azure Firewall private IP (if deployed)')
#disable-next-line BCP318
output firewallPrivateIp string = deployFirewall && firewall != null ? firewall.outputs.firewallPrivateIp : ''

@description('VPN Gateway public IP (if deployed)')
#disable-next-line BCP318
output vpnGatewayPublicIp string = deployVpnGateway && vpnGateway != null ? vpnGateway.outputs.gatewayPublicIp : ''
