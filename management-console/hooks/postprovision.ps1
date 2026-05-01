#!/usr/bin/env pwsh
<#
.SYNOPSIS
  azd post-provision hook (cross-platform PowerShell).

.DESCRIPTION
  After infra is deployed, retrieves the SPA Container App FQDN from azd
  outputs and registers both the production HTTPS URL and the local dev URL
  as redirect URIs on the SPA app registration.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log { param([string]$Message) Write-Host "[postprovision] $Message" }
function Stop-Hook { param([string]$Message) Write-Error "[postprovision] FAIL: $Message"; exit 1 }

function Test-Cmd { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# az ... -o tsv returns $null on empty results, which breaks .Trim() under StrictMode.
function ConvertTo-TrimmedString {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [array]) { $Value = $Value -join "`n" }
    return ([string]$Value).Trim()
}

if (-not (Test-Cmd az))  { Stop-Hook 'az CLI not found' }
if (-not (Test-Cmd azd)) { Stop-Hook 'azd not found' }

& az account show 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Stop-Hook 'az CLI is not signed in. Run: az login --tenant <partner-tenant-id>'
}

$envDump = & azd env get-values 2>$null
$envMap  = @{}
if ($envDump) {
    foreach ($line in $envDump) {
        if ($line -match '^([A-Za-z0-9_]+)="?(.*?)"?$') { $envMap[$Matches[1]] = $Matches[2] }
    }
}
function Get-AzdEnv { param([string]$Key) if ($envMap.ContainsKey($Key)) { return $envMap[$Key] } return '' }

$spaAppId = Get-AzdEnv 'SPA_APP_CLIENT_ID'
if (-not $spaAppId) { Stop-Hook 'SPA_APP_CLIENT_ID missing — preprovision hook did not run?' }

$webFqdn = Get-AzdEnv 'WEB_FQDN'
$apiFqdn = Get-AzdEnv 'API_FQDN'
$securityGroupId = Get-AzdEnv 'SECURITY_GROUP_OBJECT_ID'
$uamiPrincipalId = Get-AzdEnv 'UAMI_PRINCIPAL_ID'
if (-not $webFqdn) { Stop-Hook 'WEB_FQDN output missing from infra deployment' }

$webUrl   = "https://$webFqdn"
$localUrl = 'http://localhost:5173'

Write-Log "SPA app: $spaAppId"
Write-Log "Adding redirect URIs: $webUrl, $localUrl"

$redirectBody = @{
    spa = @{ redirectUris = @($webUrl, $localUrl) }
} | ConvertTo-Json -Depth 4 -Compress

$spaObjectId = ConvertTo-TrimmedString (& az ad app show --id $spaAppId --query id -o tsv)
if (-not $spaObjectId) { Stop-Hook "Could not resolve object id for SPA app $spaAppId" }

$tmpFile = [IO.Path]::GetTempFileName()
try {
    Set-Content -Path $tmpFile -Value $redirectBody -NoNewline -Encoding utf8
    # Use /applications/{objectId} (no parens) so cmd.exe doesn't choke on
    # az.cmd's argument parsing on Windows ("--headers was unexpected").
    & az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$spaObjectId" --headers "Content-Type=application/json" --body "@$tmpFile" 1>$null
} finally {
    Remove-Item $tmpFile -ErrorAction SilentlyContinue
}

# Surface the URLs prominently in the azd env for downstream tools.
& azd env set SPA_REDIRECT_URI_PROD  $webUrl
& azd env set SPA_REDIRECT_URI_LOCAL $localUrl
if ($apiFqdn) { & azd env set API_BASE_URL "https://$apiFqdn" }

# Add the worker UAMI's service principal to the management group. Group
# membership propagates to Azure RBAC (so the UAMI is covered by the same
# Lighthouse delegation as human admins) but NOT to app role / `roles` JWT
# claims for service principals — those require a direct assignment, which
# we make below.
if ($securityGroupId -and $uamiPrincipalId) {
    $isMember = ConvertTo-TrimmedString (& az ad group member check --group $securityGroupId --member-id $uamiPrincipalId --query value -o tsv 2>$null)
    if ($isMember -ne 'true') {
        Write-Log "Adding UAMI ($uamiPrincipalId) to management group"
        & az ad group member add --group $securityGroupId --member-id $uamiPrincipalId 2>$null
        $LASTEXITCODE = 0
    } else {
        Write-Log 'UAMI already a member of management group'
    }
} else {
    Write-Log 'WARN: SECURITY_GROUP_OBJECT_ID or UAMI_PRINCIPAL_ID missing; skipping UAMI->group add'
}

# Direct app role assignment for the UAMI on the API SP so the worker's
# client-credentials token includes the AZURE-SMB-RF-MANAGEMENT role.
$apiAppId = Get-AzdEnv 'API_APP_CLIENT_ID'
if ($apiAppId -and $uamiPrincipalId) {
    $apiSpId = ConvertTo-TrimmedString (& az ad sp show --id $apiAppId --query id -o tsv 2>$null)
    $rolesJson = & az ad app show --id $apiAppId --query 'appRoles' -o json 2>$null
    $mgmtRoleId = ''
    if ($rolesJson) {
        $roles = $rolesJson | ConvertFrom-Json
        $mgmtRole = @($roles) | Where-Object { $_.value -eq 'AZURE-SMB-RF-MANAGEMENT' } | Select-Object -First 1
        if ($mgmtRole) { $mgmtRoleId = $mgmtRole.id }
    }
    if ($apiSpId -and $mgmtRoleId) {
        $existingJson = & az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apiSpId/appRoleAssignedTo" -o json 2>$null
        $alreadyAssigned = $false
        if ($existingJson) {
            foreach ($a in @(($existingJson | ConvertFrom-Json).value)) {
                if ($a.principalId -eq $uamiPrincipalId -and $a.appRoleId -eq $mgmtRoleId) { $alreadyAssigned = $true; break }
            }
        }
        if ($alreadyAssigned) {
            Write-Log 'UAMI already has direct app role assignment on API SP'
        } else {
            Write-Log 'Assigning UAMI directly to API app role'
            $body = @{ principalId = $uamiPrincipalId; resourceId = $apiSpId; appRoleId = $mgmtRoleId } | ConvertTo-Json -Compress
            $tmp = [IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tmp -Value $body -NoNewline -Encoding utf8
                & az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apiSpId/appRoleAssignedTo" --headers "Content-Type=application/json" --body "@$tmp" 1>$null
                $LASTEXITCODE = 0
            } finally {
                Remove-Item $tmp -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-Log 'WARN: could not resolve API SP or app role id; skipping UAMI->role assignment'
    }
} else {
    Write-Log 'WARN: API_APP_CLIENT_ID or UAMI_PRINCIPAL_ID missing; skipping UAMI->role assignment'
}

# ---------------------------------------------------------------------------
# Microsoft Graph app role: CrossTenantInformation.ReadBasic.All
# ---------------------------------------------------------------------------
# Required so the API can resolve customer tenant display names via Graph
# `findTenantInformationByTenantId` during onboarding (used to prefill the
# wizard's display name as <tenantName>/<subscriptionName>). Without it the
# SPA falls back gracefully to the subscription name only — the grant is
# optional but improves UX. Requires that whoever runs `azd up` has
# Application.Read.All + AppRoleAssignment.ReadWrite.All in the partner
# tenant (Global Admin, Privileged Role Administrator, or Cloud App Admin).
if ($uamiPrincipalId) {
    $graphAppId = '00000003-0000-0000-c000-000000000000'
    $graphSpId = ConvertTo-TrimmedString (& az ad sp show --id $graphAppId --query id -o tsv 2>$null)
    if ($graphSpId) {
        $graphRolesJson = & az ad sp show --id $graphAppId --query 'appRoles' -o json 2>$null
        $crossTenantRoleId = ''
        if ($graphRolesJson) {
            $graphRoles = $graphRolesJson | ConvertFrom-Json
            $role = @($graphRoles) | Where-Object { $_.value -eq 'CrossTenantInformation.ReadBasic.All' } | Select-Object -First 1
            if ($role) { $crossTenantRoleId = $role.id }
        }
        if ($crossTenantRoleId) {
            $existingGraphJson = & az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$uamiPrincipalId/appRoleAssignments" -o json 2>$null
            $alreadyGranted = $false
            if ($existingGraphJson) {
                foreach ($a in @(($existingGraphJson | ConvertFrom-Json).value)) {
                    if ($a.appRoleId -eq $crossTenantRoleId -and $a.resourceId -eq $graphSpId) { $alreadyGranted = $true; break }
                }
            }
            if ($alreadyGranted) {
                Write-Log 'UAMI already has Graph CrossTenantInformation.ReadBasic.All'
            } else {
                Write-Log 'Granting Graph CrossTenantInformation.ReadBasic.All to UAMI'
                $body = @{ principalId = $uamiPrincipalId; resourceId = $graphSpId; appRoleId = $crossTenantRoleId } | ConvertTo-Json -Compress
                $tmp = [IO.Path]::GetTempFileName()
                try {
                    Set-Content -Path $tmp -Value $body -NoNewline -Encoding utf8
                    & az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$uamiPrincipalId/appRoleAssignments" --headers "Content-Type=application/json" --body "@$tmp" 1>$null
                    if ($LASTEXITCODE -ne 0) {
                        Write-Log 'WARN: Graph admin grant failed. The signed-in az user needs Global Admin / Privileged Role Admin / Cloud App Admin in the partner tenant. Tenant-name lookup will degrade to subscription name only.'
                    }
                    $LASTEXITCODE = 0
                } finally {
                    Remove-Item $tmp -ErrorAction SilentlyContinue
                }
            }
        } else {
            Write-Log 'WARN: could not resolve CrossTenantInformation.ReadBasic.All role id'
        }
    } else {
        Write-Log 'WARN: could not resolve Microsoft Graph SP'
    }
} else {
    Write-Log 'WARN: UAMI_PRINCIPAL_ID missing; skipping Graph CrossTenantInformation grant'
}

# ----------------------------------------------------------------------------
# Worker container image: build with `az acr build` and update the job.
# azd doesn't natively host Microsoft.App/jobs, so we keep the worker image
# in sync from this hook. After the first push we flip
# SERVICE_WORKER_RESOURCE_EXISTS=true so the bicep `existing` lookup
# preserves the image on subsequent `azd up` runs (otherwise the template
# would revert to the ACA placeholder).
# ----------------------------------------------------------------------------
$acrEndpoint   = Get-AzdEnv 'AZURE_CONTAINER_REGISTRY_ENDPOINT'
$workerJobName = Get-AzdEnv 'WORKER_JOB_NAME'
$rgName        = Get-AzdEnv 'RESOURCE_GROUP_NAME'

if ($acrEndpoint -and $workerJobName -and $rgName) {
    $acrName    = $acrEndpoint.Split('.')[0]
    $imageRepo  = "management-console/worker-$(Get-AzdEnv 'AZURE_ENV_NAME')"
    if ($imageRepo -eq 'management-console/worker-') {
        # Fall back: derive env name from job name (caj-worker-<envName>)
        $imageRepo = "management-console/$($workerJobName -replace '^caj-','')"
    }
    $imageTag   = "${acrEndpoint}/${imageRepo}:latest"
    $workerCtx  = Join-Path $PSScriptRoot '..' 'worker'

    Write-Log "Building worker image via ACR: $imageTag"
    & az acr build --registry $acrName --image "${imageRepo}:latest" --file (Join-Path $workerCtx 'Dockerfile') $workerCtx 1>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hook "az acr build failed for worker image" }

    Write-Log "Updating container app job $workerJobName -> $imageTag"
    & az containerapp job update --name $workerJobName --resource-group $rgName --image $imageTag --query "properties.template.containers[0].image" -o tsv 1>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hook "Failed to update worker job image" }

    & azd env set SERVICE_WORKER_RESOURCE_EXISTS true 1>$null
    Write-Log 'Worker image deployed; SERVICE_WORKER_RESOURCE_EXISTS=true persisted in azd env.'
} else {
    Write-Log 'WARN: AZURE_CONTAINER_REGISTRY_ENDPOINT/WORKER_JOB_NAME/RESOURCE_GROUP_NAME missing; skipping worker image build.'
}

Write-Log 'Redirect URIs updated.'
Write-Log "  Web (prod):  $webUrl"
Write-Log "  Web (local): $localUrl"
if ($apiFqdn) { Write-Log "  API base:    https://$apiFqdn" }
