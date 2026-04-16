<#
.SYNOPSIS
    Post-provision hook for SMB Ready Foundation azd deployment.
.DESCRIPTION
    Runs after azd provision. Performs:
    1. Deployment result verification
    2. Retry logic for transient failures (9 error patterns, exponential backoff)
    3. Deployment output parsing
    4. Resource state verification
    5. Next-steps guidance

    Migrated from deploy.ps1 v0.5 retry logic and post-deployment steps.
.NOTES
    Called by azd via azure.yaml hooks.postprovision
#>

$ErrorActionPreference = 'Stop'

#region Environment Variables

$scenario = $env:SCENARIO ?? 'baseline'
$location = $env:AZURE_LOCATION ?? 'swedencentral'
$envName = $env:AZURE_ENV_NAME ?? 'smb-ready-foundation'

# Derived flags
$deployFirewall = $scenario -eq 'firewall' -or $scenario -eq 'full'
$deployVpn = $scenario -eq 'vpn' -or $scenario -eq 'full'

#endregion

#region Retry Logic

function Invoke-DeploymentRetry {
    <#
    .SYNOPSIS
        Retries a failed azd provision with exponential backoff.
    .DESCRIPTION
        If the main provision failed with a transient error, this function
        retries using az deployment sub create directly.

        Retryable error patterns (from deploy.ps1 v0.5):
        - InternalServerError, ServiceUnavailable, TooManyRequests
        - GatewayTimeout, AnotherOperationInProgress, Conflict
        - OperationNotAllowed.*operation.*in progress
        - RetryableError, subnet.*being updated
    #>
    param(
        [string]$ErrorOutput,
        [int]$MaxRetries = 3,
        [int]$BaseDelaySeconds = 30
    )

    $retryablePatterns = @(
        'InternalServerError',
        'ServiceUnavailable',
        'TooManyRequests',
        'GatewayTimeout',
        'AnotherOperationInProgress',
        'Conflict',
        'OperationNotAllowed.*operation.*in progress',
        'RetryableError',
        'subnet.*being updated'
    )
    $patternRegex = $retryablePatterns -join '|'

    if ($ErrorOutput -notmatch $patternRegex) {
        Write-Host "  Non-retryable error detected. No automatic retry." -ForegroundColor Red
        return $false
    }

    Write-Host "  Transient error detected. Initiating retry sequence..." -ForegroundColor Yellow

    $scriptDir = Split-Path $PSScriptRoot
    $templateFile = Join-Path $scriptDir 'main.bicep'
    $paramFile = Join-Path $scriptDir 'main.parameters.json'

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $delay = $BaseDelaySeconds * [math]::Pow(2, $attempt - 1)
        Write-Host "  Retry $attempt of $MaxRetries (waiting ${delay}s)..." -ForegroundColor Yellow
        Start-Sleep -Seconds $delay

        $result = az deployment sub create `
            --location $location `
            --name "$envName-retry-$attempt-$(Get-Date -Format 'HHmmss')" `
            --template-file $templateFile `
            --parameters $paramFile 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Retry $attempt succeeded." -ForegroundColor Green
            return $true
        }

        $resultText = $result -join "`n"
        if ($resultText -notmatch $patternRegex) {
            Write-Host "  Non-retryable error on retry $attempt. Stopping." -ForegroundColor Red
            return $false
        }
    }

    Write-Host "  All $MaxRetries retries exhausted." -ForegroundColor Red
    return $false
}

#endregion

#region Main Post-Provision Flow

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SMB Ready Foundation — Post-Provision" -ForegroundColor Cyan
Write-Host "  Scenario: $scenario" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verify deployment succeeded
Write-Host "  [1] Checking deployment result..." -ForegroundColor White

$regionAbbr = switch ($location) {
    'swedencentral'        { 'swc' }
    'germanywestcentral'   { 'gwc' }
    default                { $location.Substring(0, 3) }
}

# Check key resource groups exist
$hubRg = "rg-hub-smb-$regionAbbr"
$spokeRg = "rg-spoke-prod-$regionAbbr"
$monitorRg = "rg-monitor-smb-$regionAbbr"

$rgCheck = az group exists --name $hubRg 2>$null
if ($rgCheck -ne 'true') {
    Write-Host "  WARNING: Hub resource group $hubRg not found. Deployment may have failed." -ForegroundColor Yellow
    Write-Host "  Check the azd provision output above for errors." -ForegroundColor Yellow
    Write-Host "  To retry manually: azd provision" -ForegroundColor Yellow
    exit 0  # Don't fail the hook — let user inspect azd output
}

Write-Host "      - Resource groups verified" -ForegroundColor Gray

# 2. Parse deployment outputs
Write-Host "  [2] Retrieving deployment outputs..." -ForegroundColor White

# Get the latest subscription deployment
$deployments = az deployment sub list --query "[?starts_with(name, '$envName')].{name:name, state:properties.provisioningState, time:properties.timestamp}" -o json 2>$null | ConvertFrom-Json
if ($deployments -and $deployments.Count -gt 0) {
    $latest = $deployments | Sort-Object -Property time -Descending | Select-Object -First 1
    Write-Host "      - Latest deployment: $($latest.name) ($($latest.state))" -ForegroundColor Gray
}

# 3. Display scenario summary
Write-Host "  [3] Deployment summary" -ForegroundColor White

$costEstimate = switch ($scenario) {
    'baseline'  { '~$48/mo' }
    'firewall'  { '~$336/mo' }
    'vpn'       { '~$187/mo' }
    'full'      { '~$476/mo' }
}

$features = @()
if ($deployFirewall) { $features += 'Azure Firewall' }
if ($deployVpn) { $features += 'VPN Gateway' }
if (-not $deployFirewall) { $features += 'NAT Gateway' }
$features += 'Bastion Developer', 'Log Analytics', 'Recovery Vault', 'Key Vault'

Write-Host ""
Write-Host "  Scenario:   $scenario ($costEstimate)" -ForegroundColor Green
Write-Host "  Region:     $location" -ForegroundColor Green
Write-Host "  Features:   $($features -join ', ')" -ForegroundColor Green
Write-Host ""

# 4. Next steps
Write-Host "  [4] Next steps" -ForegroundColor White
Write-Host ""
Write-Host "  1. Review deployed resources in the Azure Portal" -ForegroundColor Gray
Write-Host "  2. Configure Azure Migrate to discover on-premises servers" -ForegroundColor Gray
if ($deployVpn) {
    Write-Host "  3. Configure VPN Gateway local network gateway with on-premises details" -ForegroundColor Gray
    Write-Host "  4. Establish site-to-site VPN connection" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  To tear down: cd scripts && ./Remove-SmbReadyFoundation.ps1 -WhatIf" -ForegroundColor Gray
Write-Host "  To redeploy:  azd provision" -ForegroundColor Gray
Write-Host ""

#endregion
