// ============================================================================
// SMB Landing Zone - Parameter File
// ============================================================================
// Default values for production deployment
// Version: v0.1
// ============================================================================

using 'main.bicep'

// Required parameter - must be provided at deployment time
param owner = ''  // e.g., 'partner-ops@contoso.com'

// Optional parameters with sensible defaults
param location = 'swedencentral'
param environment = 'prod'
param hubVnetAddressSpace = '10.0.0.0/16'
param spokeVnetAddressSpace = '10.1.0.0/16'

// Optional services - disabled by default for cost optimization
param deployFirewall = false
param deployVpnGateway = false
param vpnGatewaySku = 'Basic'

// Monitoring and cost controls
param logAnalyticsDailyCapMb = 500
param budgetAmount = 500
