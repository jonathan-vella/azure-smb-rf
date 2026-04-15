<#
.SYNOPSIS
    Creates the smb-rf management group and moves the current subscription under it.

.DESCRIPTION
    Phase 1 deployment script. Creates the intermediate management group and
    associates the target subscription. Must be run AFTER Setup-ManagementGroupPermissions.ps1.

    This is a one-time setup per tenant. Subsequent runs are idempotent.

.PARAMETER ManagementGroupName
    Name for the management group. Default: smb-rf

.PARAMETER Location
    Deployment metadata location. Default: swedencentral

.PARAMETER SubscriptionId
    Subscription ID to move under the MG. Default: current subscription.

.EXAMPLE
    .\deploy-mg.ps1
    # Create smb-rf MG and move current subscription under it

.EXAMPLE
    .\deploy-mg.ps1 -SubscriptionId "00858ffc-dded-4f0f-8bbf-e17fff0d47d9"
    # Specify subscription explicitly

.NOTES
    Version: 1.0
    Author: Agentic InfraOps
    Prerequisites: Setup-ManagementGroupPermissions.ps1 must be run first
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ManagementGroupName = 'smb-rf',

    [Parameter()]
    [ValidateSet('swedencentral', 'germanywestcentral')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'
$scriptPath = $PSScriptRoot
$templateFile = Join-Path $scriptPath 'deploy-mg.bicep'

# Banner
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  MANAGEMENT GROUP DEPLOYMENT                                    ║" -ForegroundColor Cyan
Write-Host "║  Phase 1: Create smb-rf management group                       ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify authentication
Write-Host "  [1/4] Checking Azure authentication..." -ForegroundColor White
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    Write-Host "      └─ Subscription: $($account.name)" -ForegroundColor Green
} catch {
    Write-Host "      └─ ✗ Not authenticated. Run: az login" -ForegroundColor Red
    exit 1
}

# Auto-detect subscription ID if not provided
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $SubscriptionId = $account.id
}
Write-Host "      └─ Target subscription: $SubscriptionId" -ForegroundColor Gray

# Step 2: Verify MG permissions
Write-Host "  [2/4] Verifying management group permissions..." -ForegroundColor White

$tenantRootMgId = az account management-group list --query "[?displayName=='Tenant Root Group'].name | [0]" -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or -not $tenantRootMgId) {
    $tenantRootMgId = $account.tenantId
    $mgCheck = az account management-group show -n $tenantRootMgId 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "      └─ ✗ Cannot access management groups." -ForegroundColor Red
        Write-Host "        Run scripts/Setup-ManagementGroupPermissions.ps1 first" -ForegroundColor Yellow
        exit 1
    }
}
Write-Host "      └─ Tenant Root MG: $tenantRootMgId" -ForegroundColor Green

# Step 3: Check if MG already exists
Write-Host "  [3/4] Checking for existing management group..." -ForegroundColor White

$existingMg = az account management-group show -n $ManagementGroupName 2>$null
if ($LASTEXITCODE -eq 0 -and $existingMg) {
    Write-Host "      └─ Management group '$ManagementGroupName' already exists" -ForegroundColor Yellow

    # Check if subscription is already under it
    $mgSubs = az account management-group subscription show `
        --management-group-name $ManagementGroupName `
        --subscription $SubscriptionId 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      └─ Subscription already associated (idempotent - no changes needed)" -ForegroundColor Green
        Write-Host ""
        Write-Host "  ✓ Management group setup is already complete." -ForegroundColor Green
        Write-Host "  Next step: Run deploy.ps1 to deploy infrastructure." -ForegroundColor White
        Write-Host ""
        exit 0
    } else {
        Write-Host "      └─ Subscription not yet associated - will add" -ForegroundColor Yellow
    }
} else {
    Write-Host "      └─ Management group will be created" -ForegroundColor Gray
}

# Step 4: Deploy
Write-Host "  [4/4] Deploying management group..." -ForegroundColor White

$deploymentName = "mg-setup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployOutput = az deployment mg create `
    --management-group-id $tenantRootMgId `
    --location $Location `
    --name $deploymentName `
    --template-file $templateFile `
    --parameters "managementGroupName=$ManagementGroupName" `
    --parameters "subscriptionId=$SubscriptionId" 2>&1

$deployText = $deployOutput -join "`n"

if ($deployText -match 'provisioningState.*Succeeded' -or $LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "  ✓ MANAGEMENT GROUP CREATED SUCCESSFULLY" -ForegroundColor Green
    Write-Host ""
    Write-Host "      • Name: $ManagementGroupName" -ForegroundColor White
    Write-Host "      • Display: SMB Ready Foundation" -ForegroundColor White
    Write-Host "      • Subscription: $SubscriptionId (moved)" -ForegroundColor White
    Write-Host "      • Parent: $tenantRootMgId (Tenant Root)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Next step: Run deploy.ps1 to deploy infrastructure." -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "  ✗ Management group deployment failed" -ForegroundColor Red
    Write-Host $deployText -ForegroundColor Red
    exit 1
}
