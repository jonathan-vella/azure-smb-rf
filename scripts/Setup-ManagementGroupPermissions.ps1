<#
.SYNOPSIS
    Sets up management group permissions for SMB Ready Foundation deployment.

.DESCRIPTION
    This script configures the required RBAC permissions at the tenant root
    management group level so that the deploying user can create the smb-rf
    management group and assign policies to it.

    PREREQUISITES:
    1. User must be a Global Administrator in Entra ID
    2. User must enable "Access management for Azure resources" in
       Entra ID → Properties BEFORE running this script

    WHAT THIS SCRIPT DOES:
    1. Verifies the elevation toggle is enabled
    2. Assigns Management Group Contributor at tenant root MG
    3. Assigns Resource Policy Contributor at tenant root MG
    4. Waits for RBAC propagation and verifies access
    5. Prompts user to disable the elevation toggle

    SECURITY NOTES:
    - The elevation toggle grants User Access Administrator at root scope
    - This script assigns only the minimum roles needed, then prompts
      de-elevation to remove the broad User Access Administrator grant
    - Roles assigned are scoped to the tenant root management group only
    - No service principals or app registrations are created

.PARAMETER SkipElevationCheck
    Skip the check for elevation toggle. Use only if you have already
    verified access via another method.

.EXAMPLE
    .\Setup-ManagementGroupPermissions.ps1
    # Interactive setup with elevation verification

.NOTES
    Version: 1.0
    Author: APEX
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipElevationCheck
)

$ErrorActionPreference = 'Stop'

# Banner
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  MANAGEMENT GROUP PERMISSION SETUP                              ║" -ForegroundColor Cyan
Write-Host "║  Phase 0: One-time tenant-level role assignment                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify Azure authentication
Write-Host "  [1/5] Verifying Azure authentication..." -ForegroundColor White
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    $currentUser = az ad signed-in-user show --query "id" -o tsv 2>$null
    $userUpn = az ad signed-in-user show --query "userPrincipalName" -o tsv 2>$null
    Write-Host "      └─ Logged in as: $userUpn" -ForegroundColor Green
} catch {
    Write-Host "      └─ ✗ Not authenticated. Run: az login" -ForegroundColor Red
    exit 1
}

# Step 2: Check elevation toggle
Write-Host "  [2/5] Checking tenant root access..." -ForegroundColor White

if (-not $SkipElevationCheck) {
    # Try to list management groups - if it fails, elevation is not enabled
    $mgList = az account management-group list --query "[0].name" -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $mgList) {
        Write-Host ""
        Write-Host "  ⚠ Cannot access management groups." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  You must enable the elevation toggle first:" -ForegroundColor Yellow
        Write-Host "  1. Go to: https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Properties" -ForegroundColor Cyan
        Write-Host "  2. Set 'Access management for Azure resources' to YES" -ForegroundColor Cyan
        Write-Host "  3. Click Save" -ForegroundColor Cyan
        Write-Host "  4. Wait 30 seconds, then re-run this script" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
    Write-Host "      └─ Tenant root access verified" -ForegroundColor Green
} else {
    Write-Host "      └─ Elevation check skipped" -ForegroundColor Yellow
}

# Get tenant root management group ID
$tenantRootMgId = az account management-group list --query "[?displayName=='Tenant Root Group'].name | [0]" -o tsv 2>$null
if (-not $tenantRootMgId) {
    # Fallback: tenant root MG name equals the tenant ID
    $tenantRootMgId = $account.tenantId
}
$tenantRootScope = "/providers/Microsoft.Management/managementGroups/$tenantRootMgId"
Write-Host "      └─ Tenant Root MG: $tenantRootMgId" -ForegroundColor Gray

# Step 3: Assign Management Group Contributor
Write-Host "  [3/5] Assigning Management Group Contributor..." -ForegroundColor White

$mgContributorRoleId = "5d58bcaf-24a5-4b20-bdb6-eed9f69fbe4c"  # Management Group Contributor

# Check if already assigned
$existingMgRole = az role assignment list --scope $tenantRootScope `
    --assignee $currentUser --role $mgContributorRoleId --query "[0].id" -o tsv 2>$null

if ($existingMgRole) {
    Write-Host "      └─ Already assigned (skipping)" -ForegroundColor Gray
} else {
    az role assignment create --assignee $currentUser `
        --role $mgContributorRoleId `
        --scope $tenantRootScope 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      └─ ✓ Management Group Contributor assigned" -ForegroundColor Green
    } else {
        Write-Host "      └─ ✗ Failed to assign role" -ForegroundColor Red
        exit 1
    }
}

# Step 4: Assign Resource Policy Contributor
Write-Host "  [4/5] Assigning Resource Policy Contributor..." -ForegroundColor White

$policyContributorRoleId = "36243c78-bf99-498c-9df9-86d9f8d28608"  # Resource Policy Contributor

$existingPolicyRole = az role assignment list --scope $tenantRootScope `
    --assignee $currentUser --role $policyContributorRoleId --query "[0].id" -o tsv 2>$null

if ($existingPolicyRole) {
    Write-Host "      └─ Already assigned (skipping)" -ForegroundColor Gray
} else {
    az role assignment create --assignee $currentUser `
        --role $policyContributorRoleId `
        --scope $tenantRootScope 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      └─ ✓ Resource Policy Contributor assigned" -ForegroundColor Green
    } else {
        Write-Host "      └─ ✗ Failed to assign role" -ForegroundColor Red
        exit 1
    }
}

# Step 5: Verify and prompt de-elevation
Write-Host "  [5/5] Verifying role propagation..." -ForegroundColor White

# Wait briefly for RBAC propagation
Start-Sleep -Seconds 10

# Verify by attempting to list MGs
$verifyMg = az account management-group list --query "[0].name" -o tsv 2>$null
if ($LASTEXITCODE -eq 0 -and $verifyMg) {
    Write-Host "      └─ ✓ Management group access verified" -ForegroundColor Green
} else {
    Write-Host "      └─ ⚠ RBAC may still be propagating (up to 5 minutes)" -ForegroundColor Yellow
    Write-Host "        Wait and verify with: az account management-group list" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  ─── Setup Complete ───" -ForegroundColor Green
Write-Host ""
Write-Host "  ⚠ IMPORTANT: Now disable the elevation toggle:" -ForegroundColor Yellow
Write-Host "  1. Go to: https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Properties" -ForegroundColor Cyan
Write-Host "  2. Set 'Access management for Azure resources' to NO" -ForegroundColor Cyan
Write-Host "  3. Click Save" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Your explicit role assignments will remain active." -ForegroundColor Gray
Write-Host "  The broad User Access Administrator grant will be removed." -ForegroundColor Gray
Write-Host ""
Write-Host "  Next step: Run deploy-mg.ps1 to create the management group." -ForegroundColor White
Write-Host ""
