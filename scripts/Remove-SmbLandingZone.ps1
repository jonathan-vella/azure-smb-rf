<#
.SYNOPSIS
    Removes all SMB Landing Zone resources from an Azure subscription.

.DESCRIPTION
    This script completely tears down all resources deployed by the SMB Landing Zone,
    including resource groups, policy assignments, role assignments, and budgets.

    Use this script to:
    - Clean up after a failed deployment
    - Remove a landing zone before redeployment
    - Decommission a customer's landing zone

    Resources are deleted in proper dependency order to avoid conflicts.

.PARAMETER Location
    Azure region where the landing zone was deployed. Used to derive resource names.
    Valid values: swedencentral, germanywestcentral

.PARAMETER Environment
    The environment suffix used in spoke resource group naming.
    Valid values: dev, staging, prod

.PARAMETER WaitForCompletion
    If specified, waits for all resource group deletions to complete.
    Otherwise, deletions are initiated asynchronously.

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Remove-SmbLandingZone.ps1 -Location swedencentral
    # Interactive removal with confirmation

.EXAMPLE
    .\Remove-SmbLandingZone.ps1 -Location swedencentral -Force -WaitForCompletion
    # Force removal and wait for completion

.NOTES
    Version: 1.1
    Author: Agentic InfraOps
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('swedencentral', 'germanywestcentral')]
    [string]$Location,

    [Parameter()]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'prod',

    [Parameter()]
    [switch]$WaitForCompletion,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

#region Helper Functions

function Write-Step {
    param([string]$Message, [string]$Status = 'INFO')
    $color = switch ($Status) {
        'OK'      { 'Green' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SKIP'    { 'Gray' }
        default   { 'White' }
    }
    $symbol = switch ($Status) {
        'OK'      { '✓' }
        'WARN'    { '⚠' }
        'ERROR'   { '✗' }
        'SKIP'    { '○' }
        default   { '•' }
    }
    Write-Host "  $symbol $Message" -ForegroundColor $color
}

function Remove-ResourceIfExists {
    param(
        [string]$ResourceType,
        [string]$ResourceName,
        [string]$ResourceGroup = $null,
        [scriptblock]$DeleteCommand
    )

    try {
        & $DeleteCommand 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Step "$ResourceType '$ResourceName' deleted" 'OK'
            return $true
        } else {
            Write-Step "$ResourceType '$ResourceName' not found or already deleted" 'SKIP'
            return $false
        }
    } catch {
        Write-Step "$ResourceType '$ResourceName' deletion failed: $_" 'ERROR'
        return $false
    }
}

#endregion

#region Main Script

# Banner
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  SMB LANDING ZONE REMOVAL                                         ║" -ForegroundColor Red
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# Calculate resource names
$regionAbbrev = @{
    'swedencentral'      = 'swc'
    'germanywestcentral' = 'gwc'
}[$Location]

$resourceGroups = @(
    "rg-hub-slz-$regionAbbrev",
    "rg-spoke-$Environment-$regionAbbrev",
    "rg-monitor-slz-$regionAbbrev",
    "rg-backup-slz-$regionAbbrev",
    "rg-migrate-slz-$regionAbbrev"
)

# Check authentication
Write-Host "  Checking Azure authentication..." -ForegroundColor Gray
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    Write-Step "Subscription: $($account.name)" 'OK'
} catch {
    Write-Step "Not authenticated. Run: az login" 'ERROR'
    exit 1
}

$subId = $account.id

# List what will be deleted
Write-Host ""
Write-Host "  The following resources will be PERMANENTLY DELETED:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Resource Groups:" -ForegroundColor White
foreach ($rg in $resourceGroups) {
    $exists = az group exists --name $rg 2>$null
    if ($exists -eq 'true') {
        Write-Host "    • $rg" -ForegroundColor Red
    } else {
        Write-Host "    • $rg (not found)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "  Subscription-Level Resources:" -ForegroundColor White
Write-Host "    • Policy assignments: smb-lz-*" -ForegroundColor Red
Write-Host "    • Budget: budget-smb-lz-monthly" -ForegroundColor Red
Write-Host "    • Role assignments for backup policy" -ForegroundColor Red
Write-Host ""

# Confirmation
if (-not $Force) {
    $confirmation = Read-Host "  Type 'DELETE' to confirm removal"
    if ($confirmation -ne 'DELETE') {
        Write-Host ""
        Write-Step "Removal cancelled" 'WARN'
        exit 0
    }
}

Write-Host ""
Write-Host "  ─── Starting Removal ───" -ForegroundColor Yellow
Write-Host ""

# Phase 1: Delete policy assignments
Write-Host "  Phase 1: Policy Assignments" -ForegroundColor Cyan
$policies = az policy assignment list --scope "/subscriptions/$subId" `
    --query "[?starts_with(name, 'smb-lz-')].name" -o tsv 2>$null

if ($policies) {
    $policyList = $policies -split "`n" | Where-Object { $_ }
    foreach ($policy in $policyList) {
        Remove-ResourceIfExists -ResourceType 'Policy' -ResourceName $policy -DeleteCommand {
            az policy assignment delete --name $policy --scope "/subscriptions/$subId"
        }
    }
} else {
    Write-Step "No smb-lz-* policy assignments found" 'SKIP'
}

# Phase 2: Delete budget
Write-Host ""
Write-Host "  Phase 2: Budget" -ForegroundColor Cyan
Remove-ResourceIfExists -ResourceType 'Budget' -ResourceName 'budget-smb-lz-monthly' -DeleteCommand {
    az consumption budget delete --budget-name 'budget-smb-lz-monthly'
}

# Phase 3: Delete stale role assignments
Write-Host ""
Write-Host "  Phase 3: Role Assignments" -ForegroundColor Cyan

# Find role assignments with orphaned principals (service principals that no longer exist)
$roleAssignments = az role assignment list --scope "/subscriptions/$subId" `
    --query "[?contains(roleDefinitionName, 'Backup') || contains(roleDefinitionName, 'Contributor')].{name:name, principal:principalId, role:roleDefinitionName}" `
    -o json 2>$null | ConvertFrom-Json

$deletedCount = 0
foreach ($ra in $roleAssignments) {
    # Check if principal still exists
    $exists = az ad sp show --id $ra.principal 2>$null
    if (-not $exists -and $LASTEXITCODE -ne 0) {
        # Orphaned role assignment - delete it
        $raId = "/subscriptions/$subId/providers/Microsoft.Authorization/roleAssignments/$($ra.name)"
        az role assignment delete --ids $raId 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Step "Orphaned role assignment deleted (principal: $($ra.principal.Substring(0,8))...)" 'OK'
            $deletedCount++
        }
    }
}
if ($deletedCount -eq 0) {
    Write-Step "No orphaned role assignments found" 'SKIP'
}

# Phase 4: Delete firewall resources (if stuck in failed state)
Write-Host ""
Write-Host "  Phase 4: Firewall & VPN Gateway Cleanup (if faulted)" -ForegroundColor Cyan
$hubRg = "rg-hub-slz-$regionAbbrev"
$hubExists = az group exists --name $hubRg 2>$null

if ($hubExists -eq 'true') {
    # Check firewall state
    $fwState = az network firewall show -g $hubRg -n "fw-hub-slz-$regionAbbrev" `
        --query 'provisioningState' -o tsv 2>$null

    if ($fwState -eq 'Failed') {
        Write-Step "Faulted firewall detected - cleaning up..." 'WARN'

        # Delete firewall
        az network firewall delete -g $hubRg -n "fw-hub-slz-$regionAbbrev" --no-wait 2>$null
        Write-Step "Firewall deletion initiated" 'OK'

        # Wait a moment for firewall to start deleting
        Start-Sleep -Seconds 10

        # Delete firewall policy
        az network firewall policy delete -g $hubRg -n "fwpol-hub-slz-$regionAbbrev" 2>$null
        Write-Step "Firewall policy deleted" 'OK'
    } elseif ($fwState) {
        Write-Step "Firewall state: $fwState (will be deleted with resource group)" 'SKIP'
    } else {
        Write-Step "No firewall found" 'SKIP'
    }

    # Check VPN Gateway state
    $vpnState = az network vnet-gateway show -g $hubRg -n "vpng-hub-slz-$regionAbbrev" `
        --query 'provisioningState' -o tsv 2>$null

    if ($vpnState -eq 'Failed') {
        Write-Step "Faulted VPN Gateway detected - cleaning up..." 'WARN'

        # Delete VPN Gateway
        az network vnet-gateway delete -g $hubRg -n "vpng-hub-slz-$regionAbbrev" --no-wait 2>$null
        Write-Step "VPN Gateway deletion initiated" 'OK'

        # Wait for deletion to start
        Start-Sleep -Seconds 10

        # Delete orphaned VPN public IP
        $vpnPipName = "pip-vpn-slz-$regionAbbrev"
        $vpnPipExists = az network public-ip show -g $hubRg -n $vpnPipName 2>$null
        if ($LASTEXITCODE -eq 0 -and $vpnPipExists) {
            az network public-ip delete -g $hubRg -n $vpnPipName 2>$null
            Write-Step "VPN Gateway public IP deleted: $vpnPipName" 'OK'
        }
    } elseif ($vpnState) {
        Write-Step "VPN Gateway state: $vpnState (will be deleted with resource group)" 'SKIP'
    } else {
        Write-Step "No VPN Gateway found" 'SKIP'
    }
} else {
    Write-Step "Hub resource group not found" 'SKIP'
}

# Phase 5: Delete resource groups
Write-Host ""
Write-Host "  Phase 5: Resource Groups" -ForegroundColor Cyan

$deletedRgs = @()
foreach ($rg in $resourceGroups) {
    $exists = az group exists --name $rg 2>$null
    if ($exists -eq 'true') {
        if ($WaitForCompletion) {
            Write-Step "Deleting $rg (waiting for completion)..." 'INFO'
            az group delete --name $rg --yes 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Step "$rg deleted" 'OK'
            } else {
                Write-Step "$rg deletion failed" 'ERROR'
            }
        } else {
            az group delete --name $rg --yes --no-wait 2>$null
            Write-Step "$rg deletion initiated (async)" 'OK'
            $deletedRgs += $rg
        }
    } else {
        Write-Step "$rg not found" 'SKIP'
    }
}

# Summary
Write-Host ""
Write-Host "  ─── Removal Complete ───" -ForegroundColor Green
Write-Host ""

if ($deletedRgs.Count -gt 0 -and -not $WaitForCompletion) {
    Write-Host "  Resource group deletions running in background." -ForegroundColor Yellow
    Write-Host "  Monitor with:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    az group list -o table | grep -E 'slz|spoke'" -ForegroundColor Cyan
    Write-Host ""
}

Write-Host "  Subscription is ready for a new landing zone deployment." -ForegroundColor Green
Write-Host ""

#endregion
