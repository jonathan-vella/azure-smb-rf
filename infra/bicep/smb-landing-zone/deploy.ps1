<#
.SYNOPSIS
    Deploys the SMB Landing Zone infrastructure to Azure.

.DESCRIPTION
    This script validates and deploys the SMB Landing Zone Bicep templates
    to an Azure subscription. It performs pre-flight checks, validates templates,
    runs what-if analysis, and deploys the infrastructure.

.PARAMETER Environment
    The target environment (dev, staging, prod). Default: prod

.PARAMETER Owner
    Owner email or team name for resource tagging (required).

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

.PARAMETER LogAnalyticsDailyCapMb
    Log Analytics daily ingestion cap in MB. Default: 500

.PARAMETER BudgetAmount
    Monthly budget in USD. Default: 500

.EXAMPLE
    .\deploy.ps1 -Owner "partner-ops@contoso.com" -WhatIf

.EXAMPLE
    .\deploy.ps1 -Environment prod -Owner "partner-ops@contoso.com"

.EXAMPLE
    .\deploy.ps1 -Environment prod -Owner "partner-ops@contoso.com" -DeployFirewall -DeployVpnGateway

.NOTES
    Version: 0.1
    Author: Agentic InfraOps
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Owner,

    [Parameter()]
    [ValidateSet('swedencentral', 'germanywestcentral')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [string]$HubVnetAddressSpace = '10.0.0.0/16',

    [Parameter()]
    [string]$SpokeVnetAddressSpace = '10.1.0.0/16',

    [Parameter()]
    [switch]$DeployFirewall,

    [Parameter()]
    [switch]$DeployVpnGateway,

    [Parameter()]
    [ValidateSet('Basic', 'VpnGw1AZ')]
    [string]$VpnGatewaySku = 'Basic',

    [Parameter()]
    [ValidateRange(100, 5000)]
    [int]$LogAnalyticsDailyCapMb = 500,

    [Parameter()]
    [ValidateRange(100, 10000)]
    [int]$BudgetAmount = 500
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

#endregion

#region Main Script

$ErrorActionPreference = 'Stop'
$scriptPath = $PSScriptRoot
$templateFile = Join-Path $scriptPath 'main.bicep'

Write-Banner

Write-Section "DEPLOYMENT CONFIGURATION"

Write-Info "Environment" $Environment
Write-Info "Owner" $Owner
Write-Info "Location" $Location
Write-Info "Hub VNet" $HubVnetAddressSpace
Write-Info "Spoke VNet" $SpokeVnetAddressSpace
Write-Info "Firewall" $(if ($DeployFirewall) { "Yes (+~$277/mo)" } else { "No" })
Write-Info "VPN Gateway" $(if ($DeployVpnGateway) { "Yes ($VpnGatewaySku)" } else { "No" })
Write-Info "Log Cap" "$LogAnalyticsDailyCapMb MB/day"
Write-Info "Budget" "`$$BudgetAmount/month"

Write-Section "PRE-FLIGHT CHECKS"

# Check Azure CLI
Write-Step "1/4" "Checking Azure CLI..."
try {
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    Write-SubStep "Azure CLI: $($azVersion.'azure-cli')"
} catch {
    Write-Error "Azure CLI not found. Install from https://aka.ms/installazurecli"
    exit 1
}

# Check Bicep CLI
Write-Step "2/4" "Checking Bicep CLI..."
try {
    $bicepVersion = bicep --version 2>&1
    Write-SubStep "Bicep: $bicepVersion"
} catch {
    Write-Error "Bicep CLI not found. Run: az bicep install"
    exit 1
}

# Check Azure authentication
Write-Step "3/4" "Checking Azure authentication..."
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    Write-SubStep "Subscription: $($account.name)"
    Write-SubStep "Tenant: $($account.tenantId)"
} catch {
    Write-Error "Not authenticated. Run: az login"
    exit 1
}

# Validate template
Write-Step "4/4" "Validating Bicep templates..."
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
    '--parameters', "logAnalyticsDailyCapMb=$LogAnalyticsDailyCapMb",
    '--parameters', "budgetAmount=$BudgetAmount"
)

Write-Step "1/2" "Running what-if analysis..."
$whatIfResult = az @whatIfParams --output json 2>&1 | ConvertFrom-Json

# Parse what-if results
$createCount = 0
$modifyCount = 0
$deleteCount = 0
$noChangeCount = 0

if ($whatIfResult.changes) {
    foreach ($change in $whatIfResult.changes) {
        switch ($change.changeType) {
            'Create' { $createCount++ }
            'Modify' { $modifyCount++ }
            'Delete' { $deleteCount++ }
            'NoChange' { $noChangeCount++ }
        }
    }
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
$confirmation = Read-Host "  Deploy $createCount resources to Azure? (yes/no)"

if ($confirmation -ne 'yes') {
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
    '--parameters', "logAnalyticsDailyCapMb=$LogAnalyticsDailyCapMb",
    '--parameters', "budgetAmount=$BudgetAmount",
    '--output', 'json'
)

Write-Step "1/1" "Deploying to Azure..."
$startTime = Get-Date

try {
    $deployResult = az @deployParams 2>&1 | ConvertFrom-Json

    if ($deployResult.properties.provisioningState -eq 'Succeeded') {
        $duration = (Get-Date) - $startTime
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

    } else {
        Write-Error "Deployment failed: $($deployResult.properties.provisioningState)"
        Write-Host $deployResult.properties.error -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Error "Deployment error: $_"
    exit 1
}

#endregion
