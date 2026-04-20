<#
.SYNOPSIS
    Pre-provision hook for SMB Ready Foundation (Terraform variant).
.DESCRIPTION
    Mirrors hooks/pre-provision.sh for Windows PowerShell environments.
    Jobs: parameter + CIDR validation, Azure preflight, enable
    azd alpha.terraform, bootstrap state backend, write auto.tfvars.json
    (with budget_start_date pinned to first-of-month UTC), delete stale
    budget, clean faulted resources, terraform init.
#>

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$iacDir    = Split-Path -Parent $scriptDir
. "$scriptDir/_lib.ps1"

# ---- env resolution ----------------------------------------------------------
$scenario     = if ($env:SCENARIO) { $env:SCENARIO } else { 'baseline' }
$owner        = if ($env:OWNER)    { $env:OWNER }    else { '' }
$location     = if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION } else { 'swedencentral' }
$environment  = if ($env:ENVIRONMENT) { $env:ENVIRONMENT } else { 'prod' }
$hubCidr      = if ($env:HUB_VNET_ADDRESS_SPACE) { $env:HUB_VNET_ADDRESS_SPACE } else { '10.0.0.0/23' }
$spokeCidr    = if ($env:SPOKE_VNET_ADDRESS_SPACE) { $env:SPOKE_VNET_ADDRESS_SPACE } else { '10.0.2.0/23' }
$onPremCidr   = if ($env:ON_PREMISES_ADDRESS_SPACE) { $env:ON_PREMISES_ADDRESS_SPACE } else { '' }
$lawCap       = if ($env:LOG_ANALYTICS_DAILY_CAP_GB) { [double]$env:LOG_ANALYTICS_DAILY_CAP_GB } else { 0.5 }
$budgetAmount = if ($env:BUDGET_AMOUNT) { [int]$env:BUDGET_AMOUNT } else { 100 }
$budgetEmail  = if ($env:BUDGET_ALERT_EMAIL) { $env:BUDGET_ALERT_EMAIL } else { '' }

$flags = Resolve-ScenarioFlags -Scenario $scenario

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  SMB Ready Foundation (Terraform) — Pre-Provision' -ForegroundColor Cyan
Write-Host "  Scenario: $scenario" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

# ---- 1. Parameters -----------------------------------------------------------
Write-HookStep 1 'Validating parameters'
if ([string]::IsNullOrWhiteSpace($owner)) {
    $owner = az ad signed-in-user show --query mail -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($owner)) {
        $owner = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
    }
    if ([string]::IsNullOrWhiteSpace($owner)) {
        throw 'OWNER not set and could not auto-detect. Run: azd env set OWNER your@email.com'
    }
    Write-HookSub "Auto-detected owner: $owner"
}
if ($flags.Vpn -and [string]::IsNullOrWhiteSpace($onPremCidr)) {
    throw "ON_PREMISES_ADDRESS_SPACE required for VPN scenarios."
}

# ---- 2. CIDR -----------------------------------------------------------------
Write-HookStep 2 'Validating CIDR address spaces'
if (-not (Test-ValidCidr $hubCidr))   { throw "Invalid hub CIDR: $hubCidr" }
if (-not (Test-ValidCidr $spokeCidr)) { throw "Invalid spoke CIDR: $spokeCidr" }
if (Test-CidrOverlap $hubCidr $spokeCidr) { throw "Hub and spoke CIDRs overlap" }
if (-not [string]::IsNullOrWhiteSpace($onPremCidr)) {
    if (-not (Test-ValidCidr $onPremCidr))            { throw "Invalid on-prem CIDR: $onPremCidr" }
    if (Test-CidrOverlap $hubCidr   $onPremCidr)     { throw 'Hub and on-prem overlap' }
    if (Test-CidrOverlap $spokeCidr $onPremCidr)     { throw 'Spoke and on-prem overlap' }
}
Write-HookSub 'All CIDRs valid and non-overlapping'

# ---- 3. Azure preflight ------------------------------------------------------
Write-HookStep 3 'Azure preflight'
$subId = az account show --query id -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($subId)) { throw 'Not authenticated. Run: az login' }
Write-HookSub "Subscription: $subId"

$providers = @(
    'Microsoft.Compute','Microsoft.Network','Microsoft.Storage','Microsoft.KeyVault',
    'Microsoft.OperationalInsights','Microsoft.RecoveryServices','Microsoft.Automation',
    'Microsoft.Insights','Microsoft.Authorization','Microsoft.Management',
    'Microsoft.PolicyInsights','Microsoft.Migrate','Microsoft.Security','Microsoft.Consumption'
)
foreach ($rp in $providers) {
    $state = az provider show -n $rp --query registrationState -o tsv 2>$null
    if ($state -ne 'Registered') {
        Write-HookSub "Registering $rp (state: $state)..."
        az provider register -n $rp --wait 2>&1 | Out-Null
    }
}

# ---- 4. Enable azd alpha.terraform ------------------------------------------
Write-HookStep 4 'Enabling azd alpha.terraform feature'
azd config set alpha.terraform on | Out-Null

# ---- 5. Bootstrap state backend ---------------------------------------------
Write-HookStep 5 'Bootstrapping Terraform state backend'
& (Join-Path $iacDir 'scripts/bootstrap-tf-backend.ps1') -Location $location -EnvName ($env:AZURE_ENV_NAME ?? 'smb-ready-foundation')

# ---- 6. Write terraform.auto.tfvars.json ------------------------------------
Write-HookStep 6 'Writing terraform.auto.tfvars.json'
$budgetStartDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-01')

$tfvars = [ordered]@{
    subscription_id            = $subId
    location                   = $location
    environment                = $environment
    owner                      = $owner
    hub_vnet_address_space     = $hubCidr
    spoke_vnet_address_space   = $spokeCidr
    on_premises_address_space  = $onPremCidr
    log_analytics_daily_cap_gb = $lawCap
    budget_amount              = $budgetAmount
    budget_alert_email         = $budgetEmail
    budget_start_date          = $budgetStartDate
    deploy_firewall            = $flags.Firewall
    deploy_vpn                 = $flags.Vpn
}
$tfvars | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $iacDir 'terraform.auto.tfvars.json') -Encoding UTF8
Write-HookSub "budget_start_date=$budgetStartDate, deploy_firewall=$($flags.Firewall), deploy_vpn=$($flags.Vpn)"

# ---- 7. Clean stale resources -----------------------------------------------
Write-HookStep 7 'Cleaning stale resources'
$budgetShow = az consumption budget show --budget-name 'budget-smb-monthly' 2>$null
if ($LASTEXITCODE -eq 0 -and $budgetShow) {
    Write-HookSub 'Deleting existing budget-smb-monthly (start_date is immutable)'
    az consumption budget delete --budget-name 'budget-smb-monthly' 2>$null | Out-Null
} else {
    Write-HookSub 'No stale budget'
}

$regionShort = switch ($location) {
    'swedencentral'      { 'swc' }
    'germanywestcentral' { 'gwc' }
    default              { $location.Substring(0, 3) }
}
$hubRg = "rg-hub-smb-$regionShort"
if ((az group exists --name $hubRg) -eq 'true') {
    $fwState = az network firewall show -g $hubRg -n "fw-hub-smb-$regionShort" --query provisioningState -o tsv 2>$null
    if ($fwState -eq 'Failed') {
        Write-HookSub 'Deleting faulted firewall'
        az network firewall delete -g $hubRg -n "fw-hub-smb-$regionShort" 2>$null | Out-Null
        az network firewall policy delete -g $hubRg -n "fwpol-hub-smb-$regionShort" 2>$null | Out-Null
    }
    $vpnState = az network vnet-gateway show -g $hubRg -n "vpng-hub-smb-$regionShort" --query provisioningState -o tsv 2>$null
    if ($vpnState -eq 'Failed') {
        Write-HookSub 'Deleting faulted VPN gateway'
        az network vnet-gateway delete -g $hubRg -n "vpng-hub-smb-$regionShort" --no-wait 2>$null | Out-Null
    }
}

# ---- 8. terraform init -------------------------------------------------------
Write-HookStep 8 'terraform init -reconfigure'
$backendFile = Join-Path $iacDir (".azure/" + ($env:AZURE_ENV_NAME ?? 'smb-ready-foundation') + '/backend.hcl')
Push-Location $iacDir
try {
    terraform init -reconfigure -backend-config="$backendFile" -input=false | Out-Null
} finally { Pop-Location }
Write-HookSub 'Ready for azd provision'

Write-Host ''
Write-Host '==> Pre-provision complete.' -ForegroundColor Green
Write-Host ''
