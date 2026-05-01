#!/usr/bin/env pwsh
# Service-level prepackage hook for the `web` service.
# Writes web/.env.production from azd env vars so Vite bakes the right
# tenant/client IDs into the SPA bundle during the ACR remote build.
$ErrorActionPreference = 'Stop'

$tenantId   = $env:AZURE_TENANT_ID
$spaId      = $env:SPA_APP_CLIENT_ID
$apiId      = $env:API_APP_CLIENT_ID
$apiBaseUrl = $env:API_BASE_URL

if (-not $tenantId -or -not $spaId -or -not $apiId) {
    Write-Error "Missing azd env vars (AZURE_TENANT_ID/SPA_APP_CLIENT_ID/API_APP_CLIENT_ID). Run 'azd provision' first."
    exit 1
}
if (-not $apiBaseUrl) {
    Write-Error "Missing API_BASE_URL azd env var. Run 'azd provision' first."
    exit 1
}

$webDir = Join-Path $PSScriptRoot '..' 'web'

# 1. Vite env: bake auth IDs into the SPA bundle. API base is same-origin
# (/api), so VITE_API_BASE_URL is intentionally not set.
$envFile = Join-Path $webDir '.env.production'
@(
    "VITE_TENANT_ID=$tenantId",
    "VITE_SPA_CLIENT_ID=$spaId",
    "VITE_API_CLIENT_ID=$apiId"
) | Set-Content -Path $envFile -Encoding utf8

# 2. Render nginx.conf from template with the upstream API URL substituted in.
# nginx then proxies /api/* and /hubs/* to the API container, so the browser
# only ever talks to the web origin (no CORS).
$tmpl = Get-Content -Path (Join-Path $webDir 'nginx.conf.template') -Raw
$apiHost = ([uri]$apiBaseUrl).Host
$conf = $tmpl.Replace('__API_BASE_URL__', $apiBaseUrl).Replace('__API_HOST__', $apiHost)
Set-Content -Path (Join-Path $webDir 'nginx.conf') -Value $conf -Encoding utf8 -NoNewline

Write-Host "Wrote $envFile"
Write-Host "  VITE_TENANT_ID=$tenantId"
Write-Host "  VITE_SPA_CLIENT_ID=$spaId"
Write-Host "  VITE_API_CLIENT_ID=$apiId"
Write-Host "Rendered web/nginx.conf with upstream $apiBaseUrl"
