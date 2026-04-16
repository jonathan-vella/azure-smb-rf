<#
.SYNOPSIS
    Removes all SMB Ready Foundation resources from an Azure subscription.
.DESCRIPTION
    Full cleanup script for SMB Ready Foundation deployments. Deletes:
    - All 6 resource groups and their contents
    - Subscription-level budget
    - MG-scoped policy assignments (via Remove-SmbReadyFoundationPolicies.ps1)
    - Optionally removes the smb-rf management group

    Idempotent — safe to run multiple times. Skips resources that don't exist.

.PARAMETER Location
    Azure region of the deployment. Used to derive resource group names.
    Default: swedencentral

.PARAMETER WhatIf
    Preview mode — shows what would be deleted without deleting.

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER RemoveManagementGroup
    Also remove the smb-rf management group after cleanup.

.PARAMETER Environment
    The spoke environment suffix (dev, staging, prod). Default: prod

.EXAMPLE
    ./Remove-SmbReadyFoundation.ps1 -WhatIf
    # Preview what would be deleted

.EXAMPLE
    ./Remove-SmbReadyFoundation.ps1 -Force
    # Delete all resources without prompting

.EXAMPLE
    ./Remove-SmbReadyFoundation.ps1 -Force -RemoveManagementGroup
    # Delete all resources and remove the management group

.NOTES
    Version: 1.0
    Author: APEX
    Replaces the ghost reference from README.md that previously did not exist.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('swedencentral', 'germanywestcentral')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$RemoveManagementGroup,

    [Parameter()]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'prod'
)

$ErrorActionPreference = 'Stop'

# Region abbreviation
$regionAbbr = switch ($Location) {
    'swedencentral'      { 'swc' }
    'germanywestcentral' { 'gwc' }
    default              { $Location.Substring(0, 3) }
}

# Resource groups to delete
$resourceGroups = @(
    "rg-hub-smb-$regionAbbr",
    "rg-spoke-$Environment-$regionAbbr",
    "rg-monitor-smb-$regionAbbr",
    "rg-backup-smb-$regionAbbr",
    "rg-migrate-smb-$regionAbbr",
    "rg-security-smb-$regionAbbr"
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SMB Ready Foundation — Cleanup" -ForegroundColor Cyan
Write-Host "  Region: $Location ($regionAbbr)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify Azure authentication
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  ERROR: Not authenticated. Run: az login" -ForegroundColor Red
    exit 1
}
Write-Host "  Subscription: $($account.name)" -ForegroundColor Gray
Write-Host ""

# Show what will be deleted
Write-Host "  Resources to delete:" -ForegroundColor White
foreach ($rg in $resourceGroups) {
    $exists = az group exists --name $rg 2>$null
    $status = if ($exists -eq 'true') { 'EXISTS' } else { 'not found' }
    $color = if ($exists -eq 'true') { 'Yellow' } else { 'DarkGray' }
    Write-Host "    - $rg ($status)" -ForegroundColor $color
}
Write-Host "    - Budget: budget-smb-monthly" -ForegroundColor Yellow
Write-Host "    - MG policies: 20 policy assignments" -ForegroundColor Yellow
if ($RemoveManagementGroup) {
    Write-Host "    - Management group: smb-rf" -ForegroundColor Red
}
Write-Host ""

# WhatIf mode
if ($WhatIfPreference) {
    Write-Host "  [WhatIf] No resources deleted. Remove -WhatIf to execute." -ForegroundColor Cyan
    return
}

# Confirmation
if (-not $Force) {
    $confirm = Read-Host "  Are you sure you want to delete all resources? (y/N)"
    if ($confirm -notmatch '^[Yy](es)?$') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }
}

# 1. Remove MG-scoped policies
Write-Host "  [1/4] Removing MG-scoped policies..." -ForegroundColor White
$policyScript = Join-Path $PSScriptRoot 'Remove-SmbReadyFoundationPolicies.ps1'
if (Test-Path $policyScript) {
    & $policyScript -Force
} else {
    Write-Host "    WARNING: $policyScript not found. Skipping policy removal." -ForegroundColor Yellow
}

# 2. Delete budget
Write-Host "  [2/4] Removing budget..." -ForegroundColor White
az consumption budget delete --budget-name 'budget-smb-monthly' 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    - Budget deleted" -ForegroundColor Green
} else {
    Write-Host "    - Budget not found or already deleted" -ForegroundColor DarkGray
}

# 3. Delete resource groups (parallel with --no-wait, then wait)
Write-Host "  [3/4] Deleting resource groups..." -ForegroundColor White
$deletedRgs = @()
foreach ($rg in $resourceGroups) {
    $exists = az group exists --name $rg 2>$null
    if ($exists -eq 'true') {
        Write-Host "    - Deleting $rg..." -ForegroundColor Yellow
        az group delete --name $rg --yes --no-wait 2>$null
        $deletedRgs += $rg
    } else {
        Write-Host "    - $rg (already deleted)" -ForegroundColor DarkGray
    }
}

# Wait for all deletions to complete
if ($deletedRgs.Count -gt 0) {
    Write-Host "    Waiting for resource group deletions to complete..." -ForegroundColor Gray
    foreach ($rg in $deletedRgs) {
        az group wait --name $rg --deleted 2>$null
        Write-Host "    - $rg deleted" -ForegroundColor Green
    }
}

# 4. Optionally remove management group
if ($RemoveManagementGroup) {
    Write-Host "  [4/4] Removing management group 'smb-rf'..." -ForegroundColor White

    # Move subscription back to tenant root first
    $tenantId = $account.tenantId
    az account management-group subscription remove `
        --name 'smb-rf' `
        --subscription $account.id 2>$null

    az account management-group delete --name 'smb-rf' 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    - Management group removed" -ForegroundColor Green
    } else {
        Write-Host "    - Failed to remove management group (may require elevated permissions)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [4/4] Skipping management group removal (use -RemoveManagementGroup to include)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Cleanup complete." -ForegroundColor Green
Write-Host ""
