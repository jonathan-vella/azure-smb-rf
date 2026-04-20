<#
.SYNOPSIS
    Post-provision hook for SMB Ready Foundation (Terraform variant).
.DESCRIPTION
    Prints deployment summary and next-steps guidance after azd provision.
    Non-blocking on failure so partners can inspect the terraform output.
#>

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$iacDir    = Split-Path -Parent $scriptDir
. "$scriptDir/_lib.ps1"

$scenario = if ($env:SCENARIO) { $env:SCENARIO } else { 'baseline' }
$location = if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION } else { 'swedencentral' }
$flags    = Resolve-ScenarioFlags -Scenario $scenario

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  SMB Ready Foundation (Terraform) — Post-Provision' -ForegroundColor Cyan
Write-Host "  Scenario: $scenario" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

Write-HookStep 1 'Checking deployment result'
$regionShort = switch ($location) {
    'swedencentral'      { 'swc' }
    'germanywestcentral' { 'gwc' }
    default              { $location.Substring(0, 3) }
}
$hubRg = "rg-hub-smb-$regionShort"
if ((az group exists --name $hubRg) -ne 'true') {
    Write-HookSub "Hub resource group $hubRg not found — provision may have failed"
    Write-Host ''
    Write-Host '  To retry: azd provision' -ForegroundColor Yellow
    exit 0
}
Write-HookSub 'Core resource groups present'

Write-HookStep 2 'Retrieving Terraform outputs'
Push-Location $iacDir
try {
    $outputsJson = terraform output -json 2>$null
    if ($LASTEXITCODE -eq 0 -and $outputsJson) {
        $outputs = $outputsJson | ConvertFrom-Json
        Write-HookSub "scenario:    $($outputs.deployment_scenario.value)"
        Write-HookSub "policies:    $($outputs.policy_assignment_count.value)"
        Write-HookSub "key vault:   $($outputs.key_vault_name.value)"
        $lawId = $outputs.log_analytics_workspace_id.value
        Write-HookSub "law:         $($lawId -split '/' | Select-Object -Last 1)"
    } else {
        Write-HookSub '(outputs unavailable — state may not be initialized)'
    }
} finally { Pop-Location }

Write-HookStep 3 'Deployment summary'
$cost = switch ($scenario) {
    'baseline' { '~$48/mo' }
    'firewall' { '~$336/mo' }
    'vpn'      { '~$187/mo' }
    'full'     { '~$476/mo' }
    default    { '(unknown)' }
}

$features = @()
if ($flags.Firewall)       { $features += 'Azure Firewall' }
if ($flags.Vpn)            { $features += 'VPN Gateway' }
if (-not $flags.Firewall)  { $features += 'NAT Gateway' }
$features += 'Log Analytics', 'Recovery Vault', 'Key Vault', 'Automation Account'

Write-Host ''
Write-Host "  Scenario:   $scenario ($cost)" -ForegroundColor Green
Write-Host "  Region:     $location"         -ForegroundColor Green
Write-Host "  Features:   $($features -join ', ')" -ForegroundColor Green
Write-Host ''

Write-HookStep 4 'Next steps'
Write-Host '  1. Review deployed resources in the Azure Portal' -ForegroundColor Gray
Write-Host '  2. Configure Azure Migrate to discover on-premises servers' -ForegroundColor Gray
if ($flags.Vpn) {
    Write-Host '  3. Configure VPN local network gateway with on-premises details' -ForegroundColor Gray
    Write-Host '  4. Establish site-to-site VPN connection' -ForegroundColor Gray
}
Write-Host ''
Write-Host '  Teardown:   ./scripts/Remove-SmbReadyFoundation.ps1' -ForegroundColor Gray
Write-Host '  Redeploy:   azd provision' -ForegroundColor Gray
Write-Host ''
