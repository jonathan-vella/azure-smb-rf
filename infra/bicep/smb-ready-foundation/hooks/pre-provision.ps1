<#
.SYNOPSIS
    Pre-provision hook for SMB Ready Foundation azd deployment.
.DESCRIPTION
    Runs before azd provision. Performs:
    1. CIDR validation (hub/spoke/on-prem overlap detection)
    2. Azure pre-flight checks (CLI, Bicep, resource providers)
    3. Management group existence verification
    4. MG creation (deploy-mg.bicep) + MG-scope policy deployment (policy-assignments-mg.bicep)
    5. Budget deletion workaround (Azure API limitation)
    6. Faulted resource cleanup (Firewall, VPN Gateway)
    7. Orphaned role assignment cleanup

    Migrated from deploy.ps1 v0.5 (archived to scripts/legacy/).
    All configuration read from azd environment variables.
.NOTES
    Called by azd via azure.yaml hooks.preprovision
    Partners configure via: azd env set SCENARIO baseline
#>

$ErrorActionPreference = 'Stop'

#region Environment Variables

$scenario = $env:SCENARIO ?? 'baseline'
$owner = $env:OWNER ?? ''
$location = $env:AZURE_LOCATION ?? 'swedencentral'
$environment = $env:ENVIRONMENT ?? 'prod'
$hubCidr = $env:HUB_VNET_ADDRESS_SPACE ?? '10.0.0.0/23'
$spokeCidr = $env:SPOKE_VNET_ADDRESS_SPACE ?? '10.0.2.0/23'
$onPremCidr = $env:ON_PREMISES_ADDRESS_SPACE ?? ''
$managementGroupId = $env:MANAGEMENT_GROUP_ID ?? 'smb-rf'

# Derived flags
$deployFirewall = $scenario -eq 'firewall' -or $scenario -eq 'full'
$deployVpn = $scenario -eq 'vpn' -or $scenario -eq 'full'

#endregion

#region Helper Functions

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "  [$Step] $Message" -ForegroundColor White
}

function Write-SubStep {
    param([string]$Message)
    Write-Host "      - $Message" -ForegroundColor Gray
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

function Test-CidrOverlap {
    param([string]$Cidr1, [string]$Cidr2)
    $parts1 = $Cidr1 -split '/'
    $parts2 = $Cidr2 -split '/'
    $ip1 = [System.Net.IPAddress]::Parse($parts1[0])
    $ip2 = [System.Net.IPAddress]::Parse($parts2[0])
    $prefix1 = [int]$parts1[1]
    $prefix2 = [int]$parts2[1]
    $bytes1 = $ip1.GetAddressBytes(); [Array]::Reverse($bytes1)
    $bytes2 = $ip2.GetAddressBytes(); [Array]::Reverse($bytes2)
    $int1 = [BitConverter]::ToUInt32($bytes1, 0)
    $int2 = [BitConverter]::ToUInt32($bytes2, 0)
    $mask1 = [uint32]::MaxValue -shl (32 - $prefix1)
    $mask2 = [uint32]::MaxValue -shl (32 - $prefix2)
    $net1 = $int1 -band $mask1
    $net2 = $int2 -band $mask2
    $smallerMask = if ($prefix1 -lt $prefix2) { $mask1 } else { $mask2 }
    return ($net1 -band $smallerMask) -eq ($net2 -band $smallerMask)
}

function Remove-StaleBudget {
    param([string]$BudgetName = 'budget-smb-monthly')
    Write-Step "CLEANUP" "Checking for existing budget..."
    $budget = az consumption budget show --budget-name $BudgetName 2>$null
    if ($LASTEXITCODE -eq 0 -and $budget) {
        Write-SubStep "Found existing budget - deleting (Azure cannot update start date after creation)..."
        az consumption budget delete --budget-name $BudgetName 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-SubStep "Budget deleted (will be recreated with current month)"
        } else {
            Write-Host "  WARNING: Failed to delete budget - deployment may fail" -ForegroundColor Yellow
        }
    } else {
        Write-SubStep "No existing budget found"
    }
}

function Remove-FaultedFirewall {
    param([string]$ResourceGroupName, [string]$FirewallName, [string]$PolicyName)
    $rgExists = az group exists --name $ResourceGroupName 2>$null
    if ($rgExists -ne 'true') { return }

    Write-Step "CLEANUP" "Checking for faulted firewall resources..."
    $fwState = az network firewall show -g $ResourceGroupName -n $FirewallName `
        --query 'provisioningState' -o tsv 2>$null

    if ($fwState -eq 'Failed') {
        Write-SubStep "Faulted firewall detected - cleaning up..."
        az network firewall delete -g $ResourceGroupName -n $FirewallName 2>$null
        Start-Sleep -Seconds 15
        az network firewall policy delete -g $ResourceGroupName -n $PolicyName 2>$null
        Write-SubStep "Faulted firewall resources cleaned up"
    } elseif ($fwState) {
        Write-SubStep "Firewall state: $fwState (OK)"
    } else {
        Write-SubStep "No existing firewall found"
    }
}

function Remove-FaultedVpnGateway {
    param([string]$ResourceGroupName, [string]$GatewayName, [string]$PublicIpName)
    $rgExists = az group exists --name $ResourceGroupName 2>$null
    if ($rgExists -ne 'true') { return }

    Write-Step "CLEANUP" "Checking for faulted VPN Gateway resources..."
    $vpnState = az network vnet-gateway show -g $ResourceGroupName -n $GatewayName `
        --query 'provisioningState' -o tsv 2>$null

    if ($vpnState -eq 'Failed') {
        Write-SubStep "Faulted VPN Gateway detected - cleaning up..."
        az network vnet-gateway delete -g $ResourceGroupName -n $GatewayName --no-wait 2>$null
        Start-Sleep -Seconds 15
        $pipExists = az network public-ip show -g $ResourceGroupName -n $PublicIpName 2>$null
        if ($LASTEXITCODE -eq 0 -and $pipExists) {
            az network public-ip delete -g $ResourceGroupName -n $PublicIpName 2>$null
            Write-SubStep "Orphaned public IP deleted: $PublicIpName"
        }
        Write-SubStep "Faulted VPN Gateway resources cleaned up"
    } elseif ($vpnState) {
        Write-SubStep "VPN Gateway state: $vpnState (OK)"
    } else {
        Write-SubStep "No existing VPN Gateway found"
    }
}

function Remove-OrphanedRoleAssignments {
    param([string]$SubscriptionId)
    Write-Step "CLEANUP" "Checking for orphaned role assignments..."
    $roleAssignments = az role assignment list --scope "/subscriptions/$SubscriptionId" `
        --query "[?contains(roleDefinitionName, 'Backup') || roleDefinitionName=='Virtual Machine Contributor'].{name:name, principal:principalId, role:roleDefinitionName}" `
        -o json 2>$null | ConvertFrom-Json

    $deletedCount = 0
    foreach ($ra in $roleAssignments) {
        if (-not $ra.principal) { continue }
        $exists = az ad sp show --id $ra.principal 2>$null
        if (-not $exists -and $LASTEXITCODE -ne 0) {
            Write-SubStep "Found orphaned: $($ra.role) for principal $($ra.principal.Substring(0,8))..."
            $raId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleAssignments/$($ra.name)"
            az role assignment delete --ids $raId 2>$null
            if ($LASTEXITCODE -eq 0) { $deletedCount++ }
        }
    }
    if ($deletedCount -gt 0) {
        Write-SubStep "Deleted $deletedCount orphaned role assignments"
    } else {
        Write-SubStep "No orphaned role assignments found"
    }
}

#endregion

#region Main Pre-Provision Flow

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SMB Ready Foundation — Pre-Provision" -ForegroundColor Cyan
Write-Host "  Scenario: $scenario" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Validate required parameters
Write-Step "1" "Validating parameters..."

if ([string]::IsNullOrWhiteSpace($owner)) {
    $owner = az ad signed-in-user show --query "mail" -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($owner)) {
        $owner = az ad signed-in-user show --query "userPrincipalName" -o tsv 2>$null
    }
    if ([string]::IsNullOrWhiteSpace($owner)) {
        Write-Host "  ERROR: OWNER not set and cannot auto-detect. Run: azd env set OWNER your@email.com" -ForegroundColor Red
        exit 1
    }
    Write-SubStep "Auto-detected owner: $owner"
}

if (($deployVpn) -and [string]::IsNullOrWhiteSpace($onPremCidr)) {
    Write-Host "  ERROR: ON_PREMISES_ADDRESS_SPACE required for scenario '$scenario'. Run: azd env set ON_PREMISES_ADDRESS_SPACE 192.168.0.0/16" -ForegroundColor Red
    exit 1
}

# 2. CIDR Validation
Write-Step "2" "Validating CIDR address spaces..."

if (-not (Test-ValidCidr $hubCidr)) {
    Write-Host "  ERROR: Invalid hub CIDR: $hubCidr (must be x.x.x.x/16-29)" -ForegroundColor Red
    exit 1
}
if (-not (Test-ValidCidr $spokeCidr)) {
    Write-Host "  ERROR: Invalid spoke CIDR: $spokeCidr (must be x.x.x.x/16-29)" -ForegroundColor Red
    exit 1
}
if (Test-CidrOverlap $hubCidr $spokeCidr) {
    Write-Host "  ERROR: Hub ($hubCidr) and Spoke ($spokeCidr) address spaces overlap" -ForegroundColor Red
    exit 1
}
if (-not [string]::IsNullOrWhiteSpace($onPremCidr)) {
    if (-not (Test-ValidCidr $onPremCidr)) {
        Write-Host "  ERROR: Invalid on-premises CIDR: $onPremCidr" -ForegroundColor Red
        exit 1
    }
    if (Test-CidrOverlap $hubCidr $onPremCidr) {
        Write-Host "  ERROR: Hub ($hubCidr) and on-premises ($onPremCidr) address spaces overlap" -ForegroundColor Red
        exit 1
    }
    if (Test-CidrOverlap $spokeCidr $onPremCidr) {
        Write-Host "  ERROR: Spoke ($spokeCidr) and on-premises ($onPremCidr) address spaces overlap" -ForegroundColor Red
        exit 1
    }
}
Write-SubStep "All CIDR ranges valid and non-overlapping"

# 3. Azure pre-flight checks
Write-Step "3" "Azure pre-flight checks..."

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  ERROR: Not authenticated. Run: az login" -ForegroundColor Red
    exit 1
}
$subscriptionId = $account.id
Write-SubStep "Subscription: $($account.name) ($subscriptionId)"

# Check required resource providers
$requiredProviders = @(
    'Microsoft.Network', 'Microsoft.Compute', 'Microsoft.Storage',
    'Microsoft.KeyVault', 'Microsoft.RecoveryServices', 'Microsoft.OperationalInsights',
    'Microsoft.Automation', 'Microsoft.Migrate'
)
foreach ($provider in $requiredProviders) {
    $state = az provider show -n $provider --query 'registrationState' -o tsv 2>$null
    if ($state -ne 'Registered') {
        Write-SubStep "Registering provider: $provider..."
        az provider register -n $provider --wait 2>$null
    }
}
Write-SubStep "All resource providers registered"

# 4. Management group verification
Write-Step "4" "Verifying management group '$managementGroupId'..."
$mgExists = az account management-group show --name $managementGroupId 2>$null
if (-not $mgExists -or $LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Management group '$managementGroupId' not found." -ForegroundColor Red
    Write-Host "  Run Phase 0 first: cd scripts && ./Setup-ManagementGroupPermissions.ps1" -ForegroundColor Yellow
    Write-Host "  Then: az account management-group create --name $managementGroupId" -ForegroundColor Yellow
    exit 1
}
Write-SubStep "Management group '$managementGroupId' exists"

# 5a. Ensure MG exists and subscription is associated
Write-Step "5a" "Ensuring management group and subscription association..."
$scriptDir = $PSScriptRoot
$projectDir = Split-Path $scriptDir -Parent
$mgTemplatePath = Join-Path $projectDir 'deploy-mg.bicep'

if (-not (Test-Path $mgTemplatePath)) {
    Write-Host "  ERROR: deploy-mg.bicep not found at $mgTemplatePath" -ForegroundColor Red
    exit 1
}

# deploy-mg.bicep must be deployed to the PARENT MG (tenant root)
# because it creates the smb-rf MG as a child
$parentMgId = az account management-group show --name $managementGroupId --query "properties.details.parent.name" -o tsv 2>$null
if (-not $parentMgId) {
    # MG doesn't exist yet — deploy to tenant root
    $parentMgId = (az account show --query tenantId -o tsv)
}

Write-SubStep "Deploying MG creation template..."
$mgCreateResult = az deployment mg create `
    --management-group-id $parentMgId `
    --location $location `
    --name "smb-rf-mg-create-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
    --template-file $mgTemplatePath `
    --parameters subscriptionId=$subscriptionId 2>&1

if ($LASTEXITCODE -ne 0) {
    # If MG already exists, this is expected — check if it's just a conflict
    $createText = $mgCreateResult -join "`n"
    if ($createText -match 'already exists' -or $createText -match 'Conflict') {
        Write-SubStep "Management group already exists (idempotent — OK)"
    } else {
        Write-Host "  ERROR: MG creation failed:" -ForegroundColor Red
        Write-Host ($mgCreateResult | Out-String) -ForegroundColor Red
        exit 1
    }
}

# 5b. Deploy 30 MG-scoped policies
Write-Step "5b" "Deploying 30 management group-scoped policies..."
$mgPolicyTemplatePath = Join-Path $projectDir 'modules' 'policy-assignments-mg.bicep'

if (-not (Test-Path $mgPolicyTemplatePath)) {
    Write-Host "  ERROR: policy-assignments-mg.bicep not found at $mgPolicyTemplatePath" -ForegroundColor Red
    exit 1
}

Write-SubStep "Running what-if for MG policies..."
az deployment mg what-if `
    --management-group-id $managementGroupId `
    --location $location `
    --template-file $mgPolicyTemplatePath `
    --parameters location=$location 2>$null

Write-SubStep "Deploying MG policies..."
$mgPolicyResult = az deployment mg create `
    --management-group-id $managementGroupId `
    --location $location `
    --name "smb-rf-mg-policies-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
    --template-file $mgPolicyTemplatePath `
    --parameters location=$location 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: MG policy deployment failed:" -ForegroundColor Red
    Write-Host ($mgPolicyResult | Out-String) -ForegroundColor Red
    exit 1
}
Write-SubStep "30 MG-scope policies deployed successfully"

# 6. Pre-deployment cleanup
Write-Step "6" "Pre-deployment cleanup..."

# Region abbreviation for resource group names
$regionAbbr = switch ($location) {
    'swedencentral'        { 'swc' }
    'germanywestcentral'   { 'gwc' }
    default                { $location.Substring(0, 3) }
}

$hubRgName = "rg-hub-smb-$regionAbbr"

Remove-StaleBudget

if ($deployFirewall) {
    Remove-FaultedFirewall `
        -ResourceGroupName $hubRgName `
        -FirewallName "fw-hub-smb-$regionAbbr" `
        -PolicyName "fwpol-hub-smb-$regionAbbr"
}

if ($deployVpn) {
    Remove-FaultedVpnGateway `
        -ResourceGroupName $hubRgName `
        -GatewayName "vpng-hub-smb-$regionAbbr" `
        -PublicIpName "pip-vpng-hub-smb-$regionAbbr"
}

Remove-OrphanedRoleAssignments -SubscriptionId $subscriptionId

Write-Host ""
Write-Host "  Pre-provision complete. azd will now deploy infrastructure." -ForegroundColor Green
Write-Host ""

#endregion
