<#
.SYNOPSIS
    Removes all Azure Policy assignments deployed by the SMB Ready Foundation project.

.DESCRIPTION
    This script removes all policy assignments created by the SMB Ready Foundation Bicep templates.
    It identifies policies by the 'Project' tag set to 'smb-ready-foundation' or by a naming convention prefix.

.PARAMETER SubscriptionId
    The Azure subscription ID where policies are deployed. If not specified, uses the current context.

.PARAMETER ProjectName
    The project name used to identify policy assignments. Defaults to 'smb-ready-foundation'.

.PARAMETER WhatIf
    Shows what would be removed without actually removing anything.

.PARAMETER Force
    Skips confirmation prompts.

.EXAMPLE
    .\Remove-SmbReadyFoundationPolicies.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\Remove-SmbReadyFoundationPolicies.ps1 -WhatIf

.EXAMPLE
    .\Remove-SmbReadyFoundationPolicies.ps1 -Force

.NOTES
    Author: Agentic InfraOps
    Requires: Az.Resources module
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$SubscriptionId,

    [Parameter()]
    [string]$ProjectName = 'smb-ready-foundation',

    [Parameter()]
    [switch]$Force
)

#Requires -Modules Az.Resources

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Policy assignment prefix used by this project
$PolicyAssignmentPrefix = 'smb-'

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'Info'    { 'Cyan' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Success' { 'Green' }
    }

    Write-Host "[$timestamp] " -NoNewline
    Write-Host $Message -ForegroundColor $color
}

function Get-PolicyAssignmentsToRemove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    Write-LogMessage "Searching for policy assignments in scope: $Scope" -Level Info

    # Get all policy assignments at subscription scope
    $allAssignments = Get-AzPolicyAssignment -Scope $Scope -ErrorAction SilentlyContinue

    if (-not $allAssignments) {
        Write-LogMessage 'No policy assignments found at subscription scope.' -Level Warning
        return @()
    }

    Write-LogMessage "Found $($allAssignments.Count) total policy assignments" -Level Info

    # Filter by project tag or naming prefix
    $matchingAssignments = $allAssignments | Where-Object {
        $matchByTag = $_.Properties.Metadata.Project -eq $ProjectName
        $matchByPrefix = $_.Name -like "$Prefix*"
        $matchByManagedBy = $_.Properties.Metadata.ManagedBy -eq 'Bicep'

        # Match if tagged with project OR uses our naming prefix AND managed by Bicep
        $matchByTag -or ($matchByPrefix -and $matchByManagedBy)
    }

    if ($matchingAssignments.Count -eq 0) {
        Write-LogMessage "No policy assignments found matching project '$ProjectName' or prefix '$Prefix'" -Level Warning
    }
    else {
        Write-LogMessage "Found $($matchingAssignments.Count) policy assignments to remove" -Level Info
    }

    return $matchingAssignments
}

function Remove-PolicyAssignments {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [array]$Assignments,

        [Parameter()]
        [switch]$Force
    )

    $removedCount = 0
    $failedCount = 0

    foreach ($assignment in $Assignments) {
        $displayName = $assignment.Properties.DisplayName
        $assignmentName = $assignment.Name

        Write-LogMessage "Processing: $displayName ($assignmentName)" -Level Info

        if ($PSCmdlet.ShouldProcess($displayName, 'Remove Policy Assignment')) {
            try {
                Remove-AzPolicyAssignment -Id $assignment.PolicyAssignmentId -ErrorAction Stop
                Write-LogMessage "  ✓ Removed: $displayName" -Level Success
                $removedCount++
            }
            catch {
                Write-LogMessage "  ✗ Failed to remove: $displayName - $($_.Exception.Message)" -Level Error
                $failedCount++
            }
        }
    }

    return @{
        Removed = $removedCount
        Failed  = $failedCount
    }
}

# Main execution
try {
    Write-LogMessage '═══════════════════════════════════════════════════════════════' -Level Info
    Write-LogMessage '  SMB Ready Foundation - Policy Cleanup Script' -Level Info
    Write-LogMessage '═══════════════════════════════════════════════════════════════' -Level Info

    # Set subscription context if specified
    if ($SubscriptionId) {
        Write-LogMessage "Setting subscription context to: $SubscriptionId" -Level Info
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }

    # Get current context
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not logged in to Azure. Run Connect-AzAccount first.'
    }

    $currentSubscriptionId = $context.Subscription.Id
    $currentSubscriptionName = $context.Subscription.Name

    Write-LogMessage "Subscription: $currentSubscriptionName ($currentSubscriptionId)" -Level Info
    Write-LogMessage "Project: $ProjectName" -Level Info
    Write-LogMessage "Policy prefix: $PolicyAssignmentPrefix" -Level Info
    Write-Host ''

    # Define scope
    $subscriptionScope = "/subscriptions/$currentSubscriptionId"

    # Get policy assignments to remove
    $assignmentsToRemove = Get-PolicyAssignmentsToRemove `
        -Scope $subscriptionScope `
        -ProjectName $ProjectName `
        -Prefix $PolicyAssignmentPrefix

    if ($assignmentsToRemove.Count -eq 0) {
        Write-LogMessage 'No policy assignments to remove. Exiting.' -Level Info
        exit 0
    }

    # Display what will be removed
    Write-Host ''
    Write-LogMessage 'The following policy assignments will be removed:' -Level Warning
    Write-Host ''

    foreach ($assignment in $assignmentsToRemove) {
        $displayName = $assignment.Properties.DisplayName
        $effect = $assignment.Properties.Parameters.effect.value
        if (-not $effect) { $effect = 'N/A' }
        Write-Host "  • $displayName (Effect: $effect)"
    }

    Write-Host ''

    # Confirm unless Force or WhatIf
    if (-not $Force -and -not $WhatIfPreference) {
        $confirmation = Read-Host "Remove $($assignmentsToRemove.Count) policy assignments? (y/N)"
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
            Write-LogMessage 'Operation cancelled by user.' -Level Warning
            exit 0
        }
    }

    # Remove policy assignments
    $result = Remove-PolicyAssignments -Assignments $assignmentsToRemove -Force:$Force

    # Summary
    Write-Host ''
    Write-LogMessage '═══════════════════════════════════════════════════════════════' -Level Info
    Write-LogMessage '  Summary' -Level Info
    Write-LogMessage '═══════════════════════════════════════════════════════════════' -Level Info
    Write-LogMessage "Removed: $($result.Removed) policy assignments" -Level Success

    if ($result.Failed -gt 0) {
        Write-LogMessage "Failed: $($result.Failed) policy assignments" -Level Error
        exit 1
    }

    Write-LogMessage 'Policy cleanup completed successfully.' -Level Success
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level Error
    exit 1
}
