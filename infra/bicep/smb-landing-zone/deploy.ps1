<#
.SYNOPSIS
    Deploys the SMB Landing Zone infrastructure to Azure.

.DESCRIPTION
    This script validates and deploys the SMB Landing Zone Bicep templates
    to an Azure subscription. It performs pre-flight checks, validates templates,
    runs what-if analysis, and deploys the infrastructure.

    When run without parameters, it enters interactive mode and prompts for
    configuration values with sensible defaults.

.PARAMETER Environment
    The target environment (dev, staging, prod). Default: prod

.PARAMETER Owner
    Owner email or team name for resource tagging. If not provided, uses
    the email from the current Azure CLI login.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral

.PARAMETER HubVnetAddressSpace
    Hub VNet CIDR address space. Default: 10.0.0.0/16

.PARAMETER SpokeVnetAddressSpace
    Spoke VNet CIDR address space. Default: 10.1.0.0/16

.PARAMETER DeployFirewall
    Deploy Azure Firewall Basic (adds ~$277/month).

.PARAMETER DeployVpnGateway
    Deploy VPN Gateway for hybrid connectivity.

.PARAMETER VpnGatewaySku
    VPN Gateway SKU (Basic or VpnGw1AZ). Default: Basic

.PARAMETER LogAnalyticsDailyCapGb
    Log Analytics daily ingestion cap in GB (decimal). Default: 0.5 (~500MB)

.PARAMETER BudgetAmount
    Monthly budget in USD. Default: 500

.PARAMETER NonInteractive
    Skip interactive prompts and use defaults/provided parameters.

.EXAMPLE
    .\deploy.ps1
    # Interactive mode - prompts for configuration

.EXAMPLE
    .\deploy.ps1 -NonInteractive -Owner "partner-ops@contoso.com"
    # Non-interactive mode with explicit owner

.EXAMPLE
    .\deploy.ps1 -DeployFirewall -DeployVpnGateway
    # Interactive mode with firewall and VPN pre-selected

.NOTES
    Version: 0.2
    Author: Agentic InfraOps
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'prod',

    [Parameter()]
    [string]$Owner,

    [Parameter()]
    [ValidateSet('swedencentral', 'germanywestcentral')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [string]$HubVnetAddressSpace = '10.0.0.0/23',

    [Parameter()]
    [string]$SpokeVnetAddressSpace = '10.0.2.0/23',

    [Parameter()]
    [switch]$DeployFirewall,

    [Parameter()]
    [switch]$DeployVpnGateway,

    [Parameter()]
    [ValidateSet('Basic', 'VpnGw1AZ')]
    [string]$VpnGatewaySku = 'Basic',

    [Parameter()]
    [string]$LogAnalyticsDailyCapGb = '0.5',

    [Parameter()]
    [ValidateRange(100, 10000)]
    [int]$BudgetAmount = 500,

    [Parameter()]
    [switch]$NonInteractive
)

#region Helper Functions

function Write-Banner {
    $banner = @"

╔═══════════════════════════════════════════════════════════════════════════════╗
║   _____ __  __ ____    _                    _ _                 _____         ║
║  / ____|  \/  |  _ \  | |                  | (_)               |___  |        ║
║ | (___ | \  / | |_) | | |     __ _ _ __   __| |_ _ __   __ _     / /___  _ __  ║
║  \___ \| |\/| |  _ <  | |    / _` | '_ \ / _` | | '_ \ / _` |   / // _ \| '_ \ ║
║  ____) | |  | | |_) | | |___| (_| | | | | (_| | | | | | (_| |  / /| (_) | | | |║
║ |_____/|_|  |_|____/  |______\__,_|_| |_|\__,_|_|_| |_|\__, | /_/  \___/|_| |_|║
║                                                         __/ |                  ║
║   Azure Infrastructure Deployment                      |___/   v0.1           ║
╚═══════════════════════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "│  $($Title.PadRight(66))│" -ForegroundColor DarkGray
    Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Step {
    param(
        [string]$Step,
        [string]$Message
    )
    Write-Host "  [$Step] $Message" -ForegroundColor White
}

function Write-SubStep {
    param([string]$Message)
    Write-Host "      └─ $Message" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Label, [string]$Value)
    Write-Host "      • $($Label): " -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor White
}

function Read-HostWithDefault {
    param(
        [string]$Prompt,
        [string]$Default
    )
    $input = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
    return $input
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )
    $defaultText = if ($Default) { "Y/n" } else { "y/N" }
    $input = Read-Host "$Prompt [$defaultText]"
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
    return $input -match '^[Yy](es)?$'
}

function Test-CidrOverlap {
    param(
        [string]$Cidr1,
        [string]$Cidr2
    )
    # Parse CIDR notation
    $parts1 = $Cidr1 -split '/'
    $parts2 = $Cidr2 -split '/'
    
    $ip1 = [System.Net.IPAddress]::Parse($parts1[0])
    $ip2 = [System.Net.IPAddress]::Parse($parts2[0])
    $prefix1 = [int]$parts1[1]
    $prefix2 = [int]$parts2[1]
    
    # Convert to integers
    $bytes1 = $ip1.GetAddressBytes()
    $bytes2 = $ip2.GetAddressBytes()
    [Array]::Reverse($bytes1)
    [Array]::Reverse($bytes2)
    $int1 = [BitConverter]::ToUInt32($bytes1, 0)
    $int2 = [BitConverter]::ToUInt32($bytes2, 0)
    
    # Calculate network masks
    $mask1 = [uint32]::MaxValue -shl (32 - $prefix1)
    $mask2 = [uint32]::MaxValue -shl (32 - $prefix2)
    
    # Get network addresses
    $net1 = $int1 -band $mask1
    $net2 = $int2 -band $mask2
    
    # Check overlap using the smaller mask (larger network)
    $smallerMask = if ($prefix1 -lt $prefix2) { $mask1 } else { $mask2 }
    
    return ($net1 -band $smallerMask) -eq ($net2 -band $smallerMask)
}

function Test-ValidCidr {
    param([string]$Cidr)
    if ($Cidr -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$') {
        return $false
    }
    try {
        $parts = $Cidr -split '/'
        [System.Net.IPAddress]::Parse($parts[0]) | Out-Null
        $prefix = [int]$parts[1]
        return $prefix -ge 16 -and $prefix -le 29
    } catch {
        return $false
    }
}

#endregion

#region Main Script

$ErrorActionPreference = 'Stop'
$scriptPath = $PSScriptRoot
$templateFile = Join-Path $scriptPath 'main.bicep'

Write-Banner

# Get Azure account info early (needed for owner detection)
Write-Host ""
Write-Host "  Checking Azure authentication..." -ForegroundColor Gray
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    $azureUser = az ad signed-in-user show --query "mail" -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($azureUser)) {
        $azureUser = az ad signed-in-user show --query "userPrincipalName" -o tsv 2>$null
    }
    Write-Host "  ✓ Logged in as: $azureUser" -ForegroundColor Green
    Write-Host "  ✓ Subscription: $($account.name)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Not authenticated. Run: az login" -ForegroundColor Red
    exit 1
}

# Set default owner from Azure login if not provided
if ([string]::IsNullOrWhiteSpace($Owner)) {
    $Owner = $azureUser
}

# Interactive configuration mode
if (-not $NonInteractive) {
    Write-Host ""
    Write-Host "┌─────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│  DEPLOYMENT CONFIGURATION                                           │" -ForegroundColor Cyan
    Write-Host "├─────────────────────────────────────────────────────────────────────┤" -ForegroundColor Cyan
    Write-Host "│                                                                     │" -ForegroundColor Cyan
    Write-Host ("│  Owner:       {0}│" -f $Owner.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Region:      {0}│" -f $Location.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Environment: {0}│" -f $Environment.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Hub VNet:    {0}│" -f $HubVnetAddressSpace.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Spoke VNet:  {0}│" -f $SpokeVnetAddressSpace.PadRight(53)) -ForegroundColor Cyan
    $fwText = if ($DeployFirewall) { "Yes (+~`$277/mo)" } else { "No" }
    Write-Host ("│  Firewall:    {0}│" -f $fwText.PadRight(53)) -ForegroundColor Cyan
    $vpnText = if ($DeployVpnGateway) { "Yes ($VpnGatewaySku)" } else { "No" }
    Write-Host ("│  VPN Gateway: {0}│" -f $vpnText.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Budget:      `${0}/month{1}│" -f $BudgetAmount, "".PadRight(43 - $BudgetAmount.ToString().Length)) -ForegroundColor Cyan
    Write-Host "│                                                                     │" -ForegroundColor Cyan
    Write-Host "└─────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""

    $acceptDefaults = Read-YesNo "  Accept these defaults?" $true

    if (-not $acceptDefaults) {
        Write-Host ""
        Write-Host "  ─── Configure Deployment ───" -ForegroundColor Yellow
        Write-Host ""

        # Owner
        $Owner = Read-HostWithDefault "  Owner email" $Owner

        # Region
        Write-Host "  Available regions: swedencentral, germanywestcentral" -ForegroundColor Gray
        $Location = Read-HostWithDefault "  Region" $Location
        while ($Location -notin @('swedencentral', 'germanywestcentral')) {
            Write-Host "  Invalid region. Choose: swedencentral or germanywestcentral" -ForegroundColor Red
            $Location = Read-HostWithDefault "  Region" 'swedencentral'
        }

        # Environment
        Write-Host "  Available environments: dev, staging, prod" -ForegroundColor Gray
        $Environment = Read-HostWithDefault "  Environment" $Environment
        while ($Environment -notin @('dev', 'staging', 'prod')) {
            Write-Host "  Invalid environment. Choose: dev, staging, or prod" -ForegroundColor Red
            $Environment = Read-HostWithDefault "  Environment" 'prod'
        }

        # IP Address Spaces
        Write-Host ""
        Write-Host "  ─── Network Configuration ───" -ForegroundColor Yellow
        Write-Host ""
        
        # Hub VNet CIDR with validation
        do {
            $HubVnetAddressSpace = Read-HostWithDefault "  Hub VNet CIDR" $HubVnetAddressSpace
            if (-not (Test-ValidCidr $HubVnetAddressSpace)) {
                Write-Host "  Invalid CIDR format. Use format: x.x.x.x/prefix (prefix 16-29)" -ForegroundColor Red
            }
        } while (-not (Test-ValidCidr $HubVnetAddressSpace))
        
        # Spoke VNet CIDR with validation and overlap check
        do {
            $SpokeVnetAddressSpace = Read-HostWithDefault "  Spoke VNet CIDR" $SpokeVnetAddressSpace
            if (-not (Test-ValidCidr $SpokeVnetAddressSpace)) {
                Write-Host "  Invalid CIDR format. Use format: x.x.x.x/prefix (prefix 16-29)" -ForegroundColor Red
                continue
            }
            if (Test-CidrOverlap $HubVnetAddressSpace $SpokeVnetAddressSpace) {
                Write-Host "  ✗ Spoke CIDR overlaps with Hub CIDR. Choose non-overlapping ranges." -ForegroundColor Red
                $SpokeVnetAddressSpace = ""
            }
        } while (-not (Test-ValidCidr $SpokeVnetAddressSpace) -or (Test-CidrOverlap $HubVnetAddressSpace $SpokeVnetAddressSpace))

        # Optional services
        Write-Host ""
        Write-Host "  ─── Optional Services ───" -ForegroundColor Yellow
        Write-Host ""
        $DeployFirewall = Read-YesNo "  Deploy Azure Firewall Basic? (+~`$277/mo)" $DeployFirewall
        $DeployVpnGateway = Read-YesNo "  Deploy VPN Gateway for hybrid connectivity?" $DeployVpnGateway

        if ($DeployVpnGateway) {
            Write-Host "  VPN SKUs: Basic (~`$27/mo), VpnGw1AZ (~`$138/mo zone-redundant)" -ForegroundColor Gray
            $VpnGatewaySku = Read-HostWithDefault "  VPN Gateway SKU" $VpnGatewaySku
            while ($VpnGatewaySku -notin @('Basic', 'VpnGw1AZ')) {
                Write-Host "  Invalid SKU. Choose: Basic or VpnGw1AZ" -ForegroundColor Red
                $VpnGatewaySku = Read-HostWithDefault "  VPN Gateway SKU" 'Basic'
            }
        }

        # Budget and alerts
        Write-Host ""
        Write-Host "  ─── Cost Controls ───" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Budget alerts will be sent to: $Owner" -ForegroundColor Gray
        $budgetInput = Read-HostWithDefault "  Monthly budget (USD)" $BudgetAmount.ToString()
        $BudgetAmount = [int]$budgetInput

        Write-Host ""
    }
}

# Validate CIDR ranges don't overlap (for non-interactive mode)
if (Test-CidrOverlap $HubVnetAddressSpace $SpokeVnetAddressSpace) {
    Write-Host "  ✗ Hub and Spoke CIDR ranges overlap. Choose non-overlapping ranges." -ForegroundColor Red
    exit 1
}

# Validate owner is set
if ([string]::IsNullOrWhiteSpace($Owner)) {
    Write-Host "  ✗ Owner is required. Provide via -Owner parameter or Azure login." -ForegroundColor Red
    exit 1
}

Write-Banner

Write-Section "DEPLOYMENT CONFIGURATION"

Write-Info "Environment" $Environment
Write-Info "Owner" $Owner
Write-Info "Location" $Location
Write-Info "Hub VNet" $HubVnetAddressSpace
Write-Info "Spoke VNet" $SpokeVnetAddressSpace
Write-Info "Firewall" $(if ($DeployFirewall) { "Yes (+~$277/mo)" } else { "No" })
Write-Info "VPN Gateway" $(if ($DeployVpnGateway) { "Yes ($VpnGatewaySku)" } else { "No" })
Write-Info "Log Cap" "$LogAnalyticsDailyCapGb GB/day"
Write-Info "Budget" "`$$BudgetAmount/month"

Write-Section "PRE-FLIGHT CHECKS"

# Check Azure CLI
Write-Step "1/6" "Checking Azure CLI..."
try {
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    Write-SubStep "Azure CLI: $($azVersion.'azure-cli')"
} catch {
    Write-Error "Azure CLI not found. Install from https://aka.ms/installazurecli"
    exit 1
}

# Check Bicep CLI
Write-Step "2/6" "Checking Bicep CLI..."
try {
    $bicepVersion = bicep --version 2>&1
    Write-SubStep "Bicep: $bicepVersion"
} catch {
    Write-Error "Bicep CLI not found. Run: az bicep install"
    exit 1
}

# Azure authentication already verified earlier
Write-Step "3/6" "Azure authentication..."
Write-SubStep "Subscription: $($account.name)"
Write-SubStep "Tenant: $($account.tenantId)"

# Check resource providers
Write-Step "4/6" "Checking resource providers..."
$requiredProviders = @(
    'Microsoft.Network',
    'Microsoft.Compute',
    'Microsoft.Storage',
    'Microsoft.OperationalInsights',
    'Microsoft.RecoveryServices',
    'Microsoft.Migrate',
    'Microsoft.Authorization',
    'Microsoft.Resources'
)
$allProvidersRegistered = $true
$unregisteredProviders = @()
foreach ($provider in $requiredProviders) {
    try {
        $state = (az provider show -n $provider --query "registrationState" -o tsv 2>$null)
        if ($LASTEXITCODE -ne 0 -or $state -ne 'Registered') {
            $unregisteredProviders += $provider
            $allProvidersRegistered = $false
        }
    } catch {
        $unregisteredProviders += $provider
        $allProvidersRegistered = $false
    }
}
if ($allProvidersRegistered) {
    Write-SubStep "All $($requiredProviders.Count) resource providers registered"
} else {
    foreach ($p in $unregisteredProviders) {
        Write-Warning "$p not registered"
    }
    Write-Error "Register missing providers with: az provider register -n <provider>"
    exit 1
}

# Check for existing resource groups
Write-Step "5/6" "Checking for existing resource groups..."
$regionAbbrev = @{ 'swedencentral' = 'swc'; 'germanywestcentral' = 'gwc' }[$Location]
$targetRgs = @(
    "rg-hub-slz-$regionAbbrev",
    "rg-spoke-$Environment-$regionAbbrev",
    "rg-monitor-slz-$regionAbbrev",
    "rg-backup-slz-$regionAbbrev",
    "rg-migrate-slz-$regionAbbrev"
)
$existingRgs = az group list --query "[].name" -o tsv 2>$null
$conflictingRgs = $targetRgs | Where-Object { $_ -in $existingRgs }
if ($conflictingRgs.Count -gt 0) {
    Write-Warning "Existing resource groups found: $($conflictingRgs -join ', ')"
    Write-SubStep "Deployment will update existing resources"
} else {
    Write-SubStep "No conflicting resource groups (clean deployment)"
}

# Check for existing policy assignments
$subId = $account.id
$existingPolicies = az policy assignment list --scope "/subscriptions/$subId" `
    --query "[?starts_with(name, 'smb-lz')].name" -o tsv 2>$null
if ($existingPolicies) {
    $policyCount = ($existingPolicies -split "`n").Count
    Write-Warning "$policyCount existing smb-lz-* policy assignments found"
    Write-SubStep "Deployment will update existing policies"
} else {
    Write-SubStep "No conflicting policy assignments"
}

# Validate template
Write-Step "6/6" "Validating Bicep templates..."
try {
    $buildOutput = bicep build $templateFile --stdout 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Bicep build failed"
        Write-Host $buildOutput -ForegroundColor Red
        exit 1
    }
    Write-SubStep "Template validation passed"

    $lintOutput = bicep lint $templateFile 2>&1
    if ($lintOutput -match "Warning") {
        Write-Warning "Lint warnings found (review recommended)"
    } else {
        Write-SubStep "Lint check passed"
    }
} catch {
    Write-Error "Template validation failed: $_"
    exit 1
}

Write-Success "All pre-flight checks passed"

Write-Section "DEPLOYMENT PREVIEW (WHAT-IF)"

$deploymentName = "smb-lz-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$whatIfParams = @(
    'deployment', 'sub', 'what-if',
    '--location', $Location,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters', "environment=$Environment",
    '--parameters', "owner=$Owner",
    '--parameters', "location=$Location",
    '--parameters', "hubVnetAddressSpace=$HubVnetAddressSpace",
    '--parameters', "spokeVnetAddressSpace=$SpokeVnetAddressSpace",
    '--parameters', "deployFirewall=$($DeployFirewall.ToString().ToLower())",
    '--parameters', "deployVpnGateway=$($DeployVpnGateway.ToString().ToLower())",
    '--parameters', "vpnGatewaySku=$VpnGatewaySku",
    '--parameters', "logAnalyticsDailyCapGb=$LogAnalyticsDailyCapGb",
    '--parameters', "budgetAmount=$BudgetAmount"
)

Write-Step "1/2" "Running what-if analysis..."
Write-Host ""

# Run what-if and display output
$whatIfOutput = az @whatIfParams 2>&1
$whatIfText = $whatIfOutput -join "`n"

# Display the what-if output for user review
Write-Host $whatIfText -ForegroundColor Gray

# Parse resource counts from the summary line "Resource changes: X to create."
$createCount = 0
$modifyCount = 0
$deleteCount = 0
$noChangeCount = 0

if ($whatIfText -match 'Resource changes:\s*(\d+)\s*to create') {
    $createCount = [int]$Matches[1]
}
if ($whatIfText -match '(\d+)\s*to modify') {
    $modifyCount = [int]$Matches[1]
}
if ($whatIfText -match '(\d+)\s*to delete') {
    $deleteCount = [int]$Matches[1]
}
if ($whatIfText -match '(\d+)\s*no change') {
    $noChangeCount = [int]$Matches[1]
}

Write-Host ""
Write-Host "┌─────────────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "│  CHANGE SUMMARY                         │" -ForegroundColor DarkGray
Write-Host "│  + Create: $($createCount.ToString().PadRight(3)) resources               │" -ForegroundColor Green
Write-Host "│  ~ Modify: $($modifyCount.ToString().PadRight(3)) resources               │" -ForegroundColor Yellow
Write-Host "│  - Delete: $($deleteCount.ToString().PadRight(3)) resources               │" -ForegroundColor Red
Write-Host "│  = NoChange: $($noChangeCount.ToString().PadRight(3)) resources            │" -ForegroundColor Gray
Write-Host "└─────────────────────────────────────────┘" -ForegroundColor DarkGray
Write-Host ""

# Confirmation
if ($WhatIfPreference) {
    Write-Warning "WhatIf mode - no changes will be made"
    exit 0
}

Write-Step "2/2" "Awaiting confirmation..."
Write-Host ""
$confirmation = Read-Host "  Deploy $createCount resources to Azure? (y/yes to confirm)"

if ($confirmation -notmatch '^[Yy](es)?$') {
    Write-Warning "Deployment cancelled by user"
    exit 0
}

Write-Section "DEPLOYING INFRASTRUCTURE"

$deployParams = @(
    'deployment', 'sub', 'create',
    '--location', $Location,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters', "environment=$Environment",
    '--parameters', "owner=$Owner",
    '--parameters', "location=$Location",
    '--parameters', "hubVnetAddressSpace=$HubVnetAddressSpace",
    '--parameters', "spokeVnetAddressSpace=$SpokeVnetAddressSpace",
    '--parameters', "deployFirewall=$($DeployFirewall.ToString().ToLower())",
    '--parameters', "deployVpnGateway=$($DeployVpnGateway.ToString().ToLower())",
    '--parameters', "vpnGatewaySku=$VpnGatewaySku",
    '--parameters', "logAnalyticsDailyCapGb=$LogAnalyticsDailyCapGb",
    '--parameters', "budgetAmount=$BudgetAmount"
)

Write-Step "1/1" "Deploying to Azure..."
Write-Host ""
$startTime = Get-Date

# Run deployment and capture output
$deployOutput = az @deployParams 2>&1
$deployText = $deployOutput -join "`n"

# Check for errors in text output
if ($deployText -match 'ERROR:') {
    Write-Error "Deployment failed"
    Write-Host $deployText -ForegroundColor Red
    exit 1
}

# Try to parse JSON from output
try {
    $jsonStart = $deployOutput | Where-Object { $_ -match '^\s*\{' } | Select-Object -First 1
    if ($jsonStart) {
        $jsonIndex = [array]::IndexOf($deployOutput, $jsonStart)
        $jsonContent = ($deployOutput[$jsonIndex..($deployOutput.Count - 1)]) -join "`n"
        $deployResult = $jsonContent | ConvertFrom-Json
    } else {
        # Deployment succeeded but no JSON output
        $deployResult = $null
    }
} catch {
    $deployResult = $null
}

$duration = (Get-Date) - $startTime

if ($deployResult -and $deployResult.properties.provisioningState -eq 'Succeeded') {
    Write-Host ""
    Write-Success "DEPLOYMENT SUCCESSFUL"
    Write-Host ""
    Write-Info "Duration" "$([math]::Round($duration.TotalMinutes, 1)) minutes"
    Write-Info "Deployment" $deploymentName

    Write-Section "DEPLOYED RESOURCES"

    $outputs = $deployResult.properties.outputs

    Write-Info "Hub VNet" $outputs.hubVnetId.value.Split('/')[-1]
    Write-Info "Spoke VNet" $outputs.spokeVnetId.value.Split('/')[-1]
    Write-Info "Bastion" $outputs.bastionName.value
    Write-Info "NAT Gateway IP" $outputs.natGatewayPublicIp.value
    Write-Info "Log Analytics" $outputs.logAnalyticsWorkspaceId.value.Split('/')[-1]
    Write-Info "Recovery Vault" $outputs.recoveryServicesVaultId.value.Split('/')[-1]
    Write-Info "Migrate Project" $outputs.migrateProjectId.value.Split('/')[-1]

    if ($DeployFirewall) {
        Write-Info "Firewall IP" $outputs.firewallPrivateIp.value
    }
    if ($DeployVpnGateway) {
        Write-Info "VPN Gateway IP" $outputs.vpnGatewayPublicIp.value
    }

    Write-Section "NEXT STEPS"

    Write-Host "  1. Connect via Bastion: Azure Portal → Bastion → Connect" -ForegroundColor White
    Write-Host "  2. Configure VM backup policies in Recovery Services Vault" -ForegroundColor White
    Write-Host "  3. Set up Azure Migrate appliance for VMware discovery" -ForegroundColor White
    Write-Host "  4. Review budget alerts: Cost Management → Budgets" -ForegroundColor White
    Write-Host ""
} elseif ($deployResult) {
    Write-Error "Deployment failed: $($deployResult.properties.provisioningState)"
    if ($deployResult.properties.error) {
        Write-Host $deployResult.properties.error -ForegroundColor Red
    }
    exit 1
} else {
    # Check if deployment succeeded without JSON output
    if ($deployText -match 'provisioningState.*Succeeded') {
        Write-Success "DEPLOYMENT SUCCESSFUL"
        Write-Info "Duration" "$([math]::Round($duration.TotalMinutes, 1)) minutes"
        Write-Info "Deployment" $deploymentName
        Write-Host ""
        Write-Host "  Check the Azure Portal for deployed resources." -ForegroundColor White
    } else {
        Write-Error "Deployment status unknown. Check Azure Portal."
        exit 1
    }
}

#endregion
