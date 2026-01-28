<#
.SYNOPSIS
    Deploys the Azure Firewall Basic test lab.

.DESCRIPTION
    This script deploys an isolated Azure Firewall Basic environment
    for testing and validating deployment patterns. Optionally includes
    VPN Gateway for hybrid connectivity testing.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral

.PARAMETER ResourceGroupName
    Resource group name. Default: rg-fw-test-swc

.PARAMETER DeployVpnGateway
    Deploy VPN Gateway for testing. Default: false

.PARAMETER WhatIf
    Preview changes without deploying.

.EXAMPLE
    .\deploy.ps1
    # Deploy firewall only

.EXAMPLE
    .\deploy.ps1 -DeployVpnGateway
    # Deploy firewall + VPN Gateway

.EXAMPLE
    .\deploy.ps1 -WhatIf
    # Preview deployment
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('swedencentral', 'germanywestcentral')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [string]$ResourceGroupName = 'rg-fw-test-swc',

    [Parameter()]
    [switch]$DeployVpnGateway
)

$ErrorActionPreference = 'Stop'
$scriptPath = $PSScriptRoot
$templateFile = Join-Path $scriptPath 'main.bicep'

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Azure Firewall Basic - Test Lab Deployment                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check Azure authentication
Write-Host "  Checking Azure authentication..." -ForegroundColor Gray
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    Write-Host "  ✓ Logged in: $($account.user.name)" -ForegroundColor Green
    Write-Host "  ✓ Subscription: $($account.name)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Not authenticated. Run: az login" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Configuration:" -ForegroundColor Yellow
Write-Host "    • Location: $Location"
Write-Host "    • Resource Group: $ResourceGroupName"
Write-Host "    • VPN Gateway: $(if ($DeployVpnGateway) { 'Yes' } else { 'No' })"
Write-Host ""

# Validate Bicep
Write-Host "  Validating Bicep templates..." -ForegroundColor Gray
try {
    $buildOutput = bicep build $templateFile --stdout 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✗ Bicep validation failed" -ForegroundColor Red
        Write-Host $buildOutput -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✓ Bicep validation passed" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Bicep validation failed: $_" -ForegroundColor Red
    exit 1
}

$deploymentName = "fw-test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# What-If or Deploy
if ($WhatIfPreference) {
    Write-Host ""
    Write-Host "  Running what-if analysis..." -ForegroundColor Yellow
    Write-Host ""
    
    az deployment sub what-if `
        --location $Location `
        --name $deploymentName `
        --template-file $templateFile `
        --parameters location=$Location `
        --parameters resourceGroupName=$ResourceGroupName `
        --parameters deployVpnGateway=$($DeployVpnGateway.ToString().ToLower())
} else {
    Write-Host ""
    Write-Host "  Deploying to Azure..." -ForegroundColor Yellow
    if ($DeployVpnGateway) {
        Write-Host "  (This may take 30-45 minutes for Firewall + VPN Gateway)" -ForegroundColor Gray
    } else {
        Write-Host "  (This may take 10-15 minutes for Azure Firewall)" -ForegroundColor Gray
    }
    Write-Host ""
    
    $startTime = Get-Date
    
    $result = az deployment sub create `
        --location $Location `
        --name $deploymentName `
        --template-file $templateFile `
        --parameters location=$Location `
        --parameters resourceGroupName=$ResourceGroupName `
        --parameters deployVpnGateway=$($DeployVpnGateway.ToString().ToLower()) `
        --output json 2>&1
    
    $duration = (Get-Date) - $startTime
    
    if ($LASTEXITCODE -eq 0) {
        $deployment = $result | ConvertFrom-Json
        
        Write-Host ""
        Write-Host "  ✓ DEPLOYMENT SUCCESSFUL" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Duration: $([math]::Round($duration.TotalMinutes, 1)) minutes" -ForegroundColor White
        Write-Host ""
        Write-Host "  Outputs:" -ForegroundColor Yellow
        Write-Host "    • Resource Group: $($deployment.properties.outputs.resourceGroupName.value)"
        Write-Host "    • Firewall Private IP: $($deployment.properties.outputs.firewallPrivateIp.value)"
        Write-Host "    • Firewall Public IP: $($deployment.properties.outputs.firewallPublicIp.value)"
        if ($DeployVpnGateway -and $deployment.properties.outputs.vpnGatewayPublicIp.value) {
            Write-Host "    • VPN Gateway Public IP: $($deployment.properties.outputs.vpnGatewayPublicIp.value)"
        }
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "  ✗ DEPLOYMENT FAILED" -ForegroundColor Red
        Write-Host ""
        Write-Host $result -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
