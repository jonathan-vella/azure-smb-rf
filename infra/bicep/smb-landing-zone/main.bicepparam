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
param hubVnetAddressSpace = '10.0.0.0/23'
param spokeVnetAddressSpace = '10.0.2.0/23'

// Optional services - disabled by default for cost optimization
param deployFirewall = false
param deployVpnGateway = false

// Monitoring and cost controls
param logAnalyticsDailyCapGb = '0.5'  // ~500 MB/day
param budgetAmount = 500
