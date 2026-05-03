<#
.SYNOPSIS
    Builds and runs the Partner Management Console API and SPA locally.

.DESCRIPTION
    Loads Entra app reg IDs from the active azd env (so the SPA can sign in
    against the same partner tenant the deployed console uses), builds both
    projects, then starts the .NET API on http://localhost:8080 and the Vite
    dev server on http://localhost:5173 in two background jobs.

    Press Ctrl+C to stop both.

.PARAMETER AzdEnv
    azd environment to source IDs from. Defaults to the currently selected env.

.PARAMETER SkipBuild
    Skip dotnet restore/build and npm install. Useful for fast restarts.

.PARAMETER ApiPort
    Port for the API. Default 8080.

.PARAMETER WebPort
    Port for the SPA dev server. Default 5173.

.EXAMPLE
    pwsh ./runlocal.ps1
    pwsh ./runlocal.ps1 -SkipBuild
    pwsh ./runlocal.ps1 -AzdEnv partner-prod
#>
[CmdletBinding()]
param(
    [string]$AzdEnv,
    [switch]$SkipBuild,
    [int]$ApiPort = 8080,
    [int]$WebPort = 5173
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$apiDir = Join-Path $root 'api'
$webDir = Join-Path $root 'web'

function Test-Tool([string]$name, [string]$hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "$name not found on PATH. $hint"
    }
}

Test-Tool dotnet 'Install .NET 10 SDK: https://dotnet.microsoft.com/download'
Test-Tool node   'Install Node.js 20+: https://nodejs.org/'
Test-Tool npm    'Comes with Node.js'

# ---------------------------------------------------------------------------
# Pull Entra IDs from azd env (optional but recommended).
# ---------------------------------------------------------------------------
$apiClientId = $env:API_APP_CLIENT_ID
$spaClientId = $env:SPA_APP_CLIENT_ID
$tenantId    = $env:AZURE_TENANT_ID
$cosmosEndpoint = $env:COSMOS_ENDPOINT
$workerSubId   = $env:WORKER_SUBSCRIPTION_ID
$workerRg      = $env:WORKER_RG
$workerJobName = $env:WORKER_JOB_NAME
$uamiPrincipalId = $env:UAMI_PRINCIPAL_ID

if (Get-Command azd -ErrorAction SilentlyContinue) {
    Push-Location $root
    try {
        if ($AzdEnv) { & azd env select $AzdEnv | Out-Null }
        $envValues = @{}
        & azd env get-values 2>$null | ForEach-Object {
            if ($_ -match '^([A-Za-z0-9_]+)="?(.*?)"?$') { $envValues[$Matches[1]] = $Matches[2] }
        }
        if (-not $apiClientId     -and $envValues.ContainsKey('API_APP_CLIENT_ID'))     { $apiClientId     = $envValues['API_APP_CLIENT_ID'] }
        if (-not $spaClientId     -and $envValues.ContainsKey('SPA_APP_CLIENT_ID'))     { $spaClientId     = $envValues['SPA_APP_CLIENT_ID'] }
        if (-not $tenantId        -and $envValues.ContainsKey('AZURE_TENANT_ID'))       { $tenantId        = $envValues['AZURE_TENANT_ID'] }
        if (-not $cosmosEndpoint  -and $envValues.ContainsKey('COSMOS_ENDPOINT'))       { $cosmosEndpoint  = $envValues['COSMOS_ENDPOINT'] }
        if (-not $workerSubId     -and $envValues.ContainsKey('AZURE_SUBSCRIPTION_ID')) { $workerSubId     = $envValues['AZURE_SUBSCRIPTION_ID'] }
        if (-not $workerRg        -and $envValues.ContainsKey('RESOURCE_GROUP_NAME'))   { $workerRg        = $envValues['RESOURCE_GROUP_NAME'] }
        if (-not $workerJobName   -and $envValues.ContainsKey('WORKER_JOB_NAME'))       { $workerJobName   = $envValues['WORKER_JOB_NAME'] }
        if (-not $uamiPrincipalId -and $envValues.ContainsKey('UAMI_PRINCIPAL_ID'))     { $uamiPrincipalId = $envValues['UAMI_PRINCIPAL_ID'] }
    } finally {
        Pop-Location
    }
}

if (-not $apiClientId -or -not $spaClientId -or -not $tenantId) {
    Write-Warning "Entra IDs not fully resolved (API_APP_CLIENT_ID / SPA_APP_CLIENT_ID / AZURE_TENANT_ID)."
    Write-Warning "SPA sign-in will fail until these are set. Run ``azd provision`` once to populate them, or export them manually."
}

if (-not $cosmosEndpoint) {
    Write-Warning "cosmosEndpoint not resolved — API calls that hit Cosmos DB will fail. Run ``azd provision`` first."
}

Write-Host "Tenant:   $tenantId"        -ForegroundColor Cyan
Write-Host "API app:  $apiClientId"     -ForegroundColor Cyan
Write-Host "SPA app:  $spaClientId"     -ForegroundColor Cyan
Write-Host "Cosmos:   $cosmosEndpoint"  -ForegroundColor Cyan
Write-Host "Worker:   $workerJobName ($workerRg)" -ForegroundColor Cyan
Write-Host "UAMI:     $uamiPrincipalId" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Ensure the signed-in user has Cosmos DB data-plane access for local dev.
# CosmosFactory uses DefaultAzureCredential, which falls back to the az CLI
# identity. The 'Cosmos DB Built-in Data Contributor' role is required to
# read/write items via RBAC (key-based auth is not used).
# ---------------------------------------------------------------------------
if ($cosmosEndpoint -and $workerRg -and (Get-Command az -ErrorAction SilentlyContinue)) {
    try {
        $cosmosAccount = ([Uri]$cosmosEndpoint).Host.Split('.')[0]
        $userObjectId  = (& az ad signed-in-user show --query id -o tsv 2>$null).Trim()
        if ($userObjectId) {
            $existing = & az cosmosdb sql role assignment list `
                --account-name $cosmosAccount -g $workerRg `
                --query "[?principalId=='$userObjectId'] | [0].id" -o tsv 2>$null
            if (-not $existing) {
                Write-Host "==> Granting 'Cosmos DB Built-in Data Contributor' to $userObjectId on $cosmosAccount" -ForegroundColor Green
                & az cosmosdb sql role assignment create `
                    --account-name $cosmosAccount -g $workerRg `
                    --scope "/" --principal-id $userObjectId `
                    --role-definition-id 00000000-0000-0000-0000-000000000002 1>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Failed to assign Cosmos data-plane role; you may need to do this manually."
                    $LASTEXITCODE = 0
                }
            }
        }
    } catch {
        Write-Warning "Could not verify Cosmos data-plane role: $_"
    }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host "`n==> Restoring + building API" -ForegroundColor Green
    Push-Location $apiDir
    try { & dotnet build -c Debug --nologo } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }

    Write-Host "`n==> Installing SPA deps" -ForegroundColor Green
    Push-Location $webDir
    try {
        if (Test-Path (Join-Path $webDir 'package-lock.json')) { & npm ci } else { & npm install }
    } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
}

# ---------------------------------------------------------------------------
# Run — both processes in background jobs; tail their output.
# ---------------------------------------------------------------------------
Write-Host "`n==> Starting API on http://localhost:$ApiPort" -ForegroundColor Green

# For local dev, also delegate Lighthouse access to the signed-in az user so
# /lighthouse/verify (which uses DefaultAzureCredential = your az login) can
# see the assignment after onboarding. In cloud only the UAMI is in the list.
$devUserOid = az ad signed-in-user show --query id -o tsv 2>$null
$lighthousePrincipals = @($uamiPrincipalId, $devUserOid) |
    Where-Object { $_ } |
    Select-Object -Unique
$lighthousePrincipalsCsv = ($lighthousePrincipals -join ',')
if ($lighthousePrincipalsCsv) {
    Write-Host "Lighthouse principals (local): $lighthousePrincipalsCsv" -ForegroundColor DarkGray
}

$apiJob = Start-Job -Name mc-api -ScriptBlock {
    param($dir, $port, $tenantId, $apiClientId, $cosmosEndpoint, $workerSubId, $workerRg, $workerJobName, $lighthousePrincipalsCsv)
    Set-Location $dir
    $env:ASPNETCORE_URLS = "http://+:$port"
    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    $env:AzureAd__TenantId = $tenantId
    $env:AzureAd__ClientId = $apiClientId
    $env:AzureAd__Audience = "api://$apiClientId"
    $env:Spa__Origin = "http://localhost:5173"
    if ($cosmosEndpoint)            { $env:COSMOS_ENDPOINT = $cosmosEndpoint }
    if ($workerSubId)               { $env:WORKER_SUBSCRIPTION_ID = $workerSubId }
    if ($workerRg)                  { $env:WORKER_RG = $workerRg }
    if ($workerJobName)             { $env:WORKER_JOB_NAME = $workerJobName }
    if ($lighthousePrincipalsCsv)   { $env:Lighthouse__PartnerPrincipalIds = $lighthousePrincipalsCsv }
    & dotnet run --no-build --project (Get-ChildItem '*.csproj').FullName
} -ArgumentList $apiDir, $ApiPort, $tenantId, $apiClientId, $cosmosEndpoint, $workerSubId, $workerRg, $workerJobName, $lighthousePrincipalsCsv

Write-Host "==> Starting SPA on http://localhost:$WebPort" -ForegroundColor Green
$webJob = Start-Job -Name mc-web -ScriptBlock {
    param($dir, $port, $apiPort, $tenantId, $apiClientId, $spaClientId)
    Set-Location $dir
    $env:VITE_API_BASE_URL   = "http://localhost:$apiPort"
    $env:VITE_API_CLIENT_ID  = $apiClientId
    $env:VITE_SPA_CLIENT_ID  = $spaClientId
    $env:VITE_TENANT_ID      = $tenantId
    & npm run dev -- --port $port --strictPort
} -ArgumentList $webDir, $WebPort, $ApiPort, $tenantId, $apiClientId, $spaClientId

Write-Host "`nAPI:  http://localhost:$ApiPort"  -ForegroundColor Yellow
Write-Host "SPA:  http://localhost:$WebPort"    -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop.`n"            -ForegroundColor Yellow

# Cleanup on exit (Ctrl+C / script end).
$cleanup = {
    Write-Host "`nStopping local services..." -ForegroundColor Yellow
    Get-Job -Name mc-api, mc-web -ErrorAction SilentlyContinue | Stop-Job -PassThru | Remove-Job -Force
}
try {
    while ($true) {
        foreach ($j in @($apiJob, $webJob)) {
            Receive-Job $j | ForEach-Object { Write-Host "[$($j.Name)] $_" }
            if ($j.State -in 'Failed','Completed','Stopped') {
                Write-Warning "[$($j.Name)] job ended with state $($j.State)"
                & $cleanup
                return
            }
        }
        Start-Sleep -Milliseconds 500
    }
} finally {
    & $cleanup
}
