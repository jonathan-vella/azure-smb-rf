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
# API_BASE_URL is only used for an informational log line below — nginx
# resolves it at container startup, not at build time. So a missing value
# here is no longer fatal.

$webDir = Join-Path $PSScriptRoot '..' 'web'

# Vite env: bake auth IDs into the SPA bundle. API base is same-origin (/api),
# so VITE_API_BASE_URL is intentionally not set.
#
# Note: nginx.conf is NOT rendered here anymore. It is rendered at container
# startup by web/docker-entrypoint.sh from web/nginx.conf.template using the
# API_BASE_URL env var injected by Container Apps. That avoids a hook-timing
# bug: with `remoteBuild: true`, the docker build context is staged before
# `predeploy` hooks run, so a hook-generated nginx.conf would not make it
# into the ACR build. Keeping .env.production here is fine because it is
# explicitly re-included via web/.dockerignore (`!.env.production`).
$envFile = Join-Path $webDir '.env.production'
# Feature flags: default to disabled. Override via `azd env set FEATURE_VPN true`.
$featureVpn = if ($env:FEATURE_VPN) { $env:FEATURE_VPN } else { 'false' }
@(
    "VITE_TENANT_ID=$tenantId",
    "VITE_SPA_CLIENT_ID=$spaId",
    "VITE_API_CLIENT_ID=$apiId",
    "VITE_FEATURE_VPN=$featureVpn"
) | Set-Content -Path $envFile -Encoding utf8

Write-Host "Wrote $envFile"
Write-Host "  VITE_TENANT_ID=$tenantId"
Write-Host "  VITE_SPA_CLIENT_ID=$spaId"
Write-Host "  VITE_API_CLIENT_ID=$apiId"
Write-Host "  VITE_FEATURE_VPN=$featureVpn"
Write-Host "nginx.conf will be rendered at container startup from API_BASE_URL=$apiBaseUrl"
