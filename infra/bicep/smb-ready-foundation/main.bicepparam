// ============================================================================
// SMB Ready Foundations - Parameter File (azd-driven)
// ============================================================================
// Reads values from azd environment variables. Set via:
//   azd env set <NAME> <VALUE>
// Falls back to sensible defaults when an env var is not set.
// ============================================================================

using 'main.bicep'

// Deployment scenario: 'baseline' | 'firewall' | 'vpn' | 'full'
param scenario = readEnvironmentVariable('SCENARIO', 'baseline')

// Required: owner contact (e.g., 'partner-ops@contoso.com')
param owner = readEnvironmentVariable('OWNER', '')

// Location and environment
param location = readEnvironmentVariable('AZURE_LOCATION', 'swedencentral')
param environment = readEnvironmentVariable('ENVIRONMENT', 'prod')

// Network address spaces
param hubVnetAddressSpace = readEnvironmentVariable('HUB_VNET_ADDRESS_SPACE', '10.0.0.0/23')
param spokeVnetAddressSpace = readEnvironmentVariable('SPOKE_VNET_ADDRESS_SPACE', '10.0.2.0/23')
param onPremisesAddressSpace = readEnvironmentVariable('ON_PREMISES_ADDRESS_SPACE', '')
param onPremisesGatewayPublicIp = readEnvironmentVariable('ON_PREMISES_GATEWAY_PUBLIC_IP', '192.0.2.1')

// Monitoring and cost controls
param logAnalyticsDailyCapGb = readEnvironmentVariable('LOG_ANALYTICS_DAILY_CAP_GB', '0.5')
param budgetAmount = int(readEnvironmentVariable('BUDGET_AMOUNT', '500'))

// Optional: managed identity for policy remediation
// this is there for the management console can be ignored
// when using azd from the command line.
param policyMiResourceId = readEnvironmentVariable('POLICY_MI_RESOURCE_ID', '')
