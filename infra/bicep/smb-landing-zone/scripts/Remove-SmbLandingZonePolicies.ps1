<#
.SYNOPSIS
    Removes all SMB Landing Zone policy assignments from the subscription.

.DESCRIPTION
    This script removes all 20 Azure Policy assignments created by the SMB Landing Zone
    deployment. Use this script to clean up policies before redeploying or when
    decommissioning the landing zone.

.PARAMETER WhatIf
    Shows what policies would be removed without actually removing them.

.PARAMETER Force
    Skips the confirmation prompt.

.EXAMPLE
    .\Remove-SmbLandingZonePolicies.ps1 -WhatIf

.EXAMPLE
    .\Remove-SmbLandingZonePolicies.ps1 -Force

.NOTES
    Version: 0.1
    Author: Agentic InfraOps
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# All policy assignment names (prefixed with 'smb-lz-')
$policyAssignments = @(
    'smb-lz-compute-01'      # Allowed VM SKUs
    'smb-lz-compute-02'      # No public IPs on NICs
    'smb-lz-compute-03'      # Audit managed disks
    'smb-lz-compute-04'      # Audit ARM VMs
    'smb-lz-network-01'      # NSG on subnets
    'smb-lz-network-02'      # Close management ports
    'smb-lz-network-03'      # Restrict NSG ports
    'smb-lz-network-04'      # Disable IP forwarding
    'smb-lz-storage-01'      # HTTPS only
    'smb-lz-storage-02'      # No public blob access
    'smb-lz-storage-03'      # TLS 1.2 minimum
    'smb-lz-storage-04'      # Restrict network access
    'smb-lz-storage-05'      # ARM migration
    'smb-lz-identity-01'     # SQL Azure AD-only
    'smb-lz-identity-02'     # SQL no public access
    'smb-lz-tagging-01'      # Require Environment tag
    'smb-lz-tagging-02'      # Require Owner tag
    'smb-lz-governance-01'   # Allowed locations
    'smb-lz-backup-01'       # VM backup required
    'smb-lz-monitoring-01'   # Diagnostic settings
)

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SMB Landing Zone - Policy Cleanup Script" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Check Azure authentication
Write-Host "Checking Azure authentication..." -ForegroundColor Gray
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    Write-Host "  Subscription: $($account.name)" -ForegroundColor White
    Write-Host "  Tenant: $($account.tenantId)" -ForegroundColor White
} catch {
    Write-Host "  ✗ Not authenticated. Run: az login" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Policies to remove:" -ForegroundColor Yellow
foreach ($policy in $policyAssignments) {
    Write-Host "  • $policy" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Total: $($policyAssignments.Count) policy assignments" -ForegroundColor White
Write-Host ""

# Confirmation
if (-not $Force -and -not $WhatIfPreference) {
    $confirmation = Read-Host "Remove all $($policyAssignments.Count) policy assignments? (yes/no)"
    if ($confirmation -ne 'yes') {
        Write-Host "  ⚠ Operation cancelled" -ForegroundColor Yellow
        exit 0
    }
}

# Remove policies
$removed = 0
$failed = 0
$notFound = 0

foreach ($policyName in $policyAssignments) {
    Write-Host "  Processing: $policyName..." -NoNewline

    if ($WhatIfPreference) {
        Write-Host " [WhatIf]" -ForegroundColor Cyan
        $removed++
        continue
    }

    try {
        # Check if policy exists
        $existing = az policy assignment show --name $policyName 2>$null
        if ($null -eq $existing) {
            Write-Host " Not found" -ForegroundColor Gray
            $notFound++
            continue
        }

        # Remove policy
        az policy assignment delete --name $policyName --output none 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host " ✓ Removed" -ForegroundColor Green
            $removed++
        } else {
            Write-Host " ✗ Failed" -ForegroundColor Red
            $failed++
        }
    } catch {
        Write-Host " ✗ Error: $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ✓ Removed: $removed" -ForegroundColor Green
Write-Host "  - Not found: $notFound" -ForegroundColor Gray
Write-Host "  ✗ Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })
Write-Host ""

if ($failed -gt 0) {
    exit 1
}
