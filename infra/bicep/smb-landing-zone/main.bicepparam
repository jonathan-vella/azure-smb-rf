// ============================================================================
// SMB Landing Zone - Parameter File
// ============================================================================
// Default values for production deployment
// Version: v0.2
// ============================================================================
// Deployment Scenarios:
// - baseline:   NAT Gateway only (~$48/mo) - cloud-native, no hybrid
// - firewall:   Azure Firewall + UDR (~$336/mo) - egress filtering
// - vpn:        VPN Gateway + Gateway Transit (~$187/mo) - hybrid connectivity
// - enterprise: Firewall + VPN + UDR (~$476/mo) - full enterprise security
// ============================================================================

using 'main.bicep'

// Deployment scenario preset
param scenario = 'baseline'  // 'baseline', 'firewall', 'vpn', 'enterprise'

// Required parameter - must be provided at deployment time
param owner = ''  // e.g., 'partner-ops@contoso.com'

// Optional parameters with sensible defaults
param location = 'swedencentral'
param environment = 'prod'
param hubVnetAddressSpace = '10.0.0.0/23'
param spokeVnetAddressSpace = '10.0.2.0/23'

// On-premises CIDR for VPN routing (required for vpn/enterprise scenarios)
param onPremisesAddressSpace = ''  // e.g., '192.168.0.0/16'

// Monitoring and cost controls
param logAnalyticsDailyCapGb = '0.5'  // ~500 MB/day
param budgetAmount = 500
