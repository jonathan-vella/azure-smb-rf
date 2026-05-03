#!/usr/bin/env pwsh
<#
.SYNOPSIS
  azd pre-provision hook (cross-platform PowerShell).

.DESCRIPTION
  Ensures the partner-tenant Entra app registrations (API + SPA) exist BEFORE
  infra deploys, then feeds their client IDs into azd env so the Bicep
  parameters file can pick them up.

  Idempotent: looks up apps by display name and reuses them on re-runs.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log  { param([string]$Message) Write-Host "[preprovision] $Message" }
function Stop-Hook  { param([string]$Message) Write-Error "[preprovision] FAIL: $Message"; exit 1 }

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

# Confirm an az session exists — `azd auth login` is NOT enough for `az ad ...`.
& az account show 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Stop-Hook 'az CLI is not signed in. Run: az login --tenant <partner-tenant-id>'
}

# Read all azd env values once into a hashtable.
$envDump = & azd env get-values 2>$null
$envMap  = @{}
if ($envDump) {
    foreach ($line in $envDump) {
        if ($line -match '^([A-Za-z0-9_]+)="?(.*?)"?$') { $envMap[$Matches[1]] = $Matches[2] }
    }
}
function Get-AzdEnv {
    param([string]$Key, [string]$Default = '')
    if ($envMap.ContainsKey($Key) -and $envMap[$Key]) { return $envMap[$Key] }
    return $Default
}

$envName      = if ($env:AZURE_ENV_NAME)  { $env:AZURE_ENV_NAME }  else { Get-AzdEnv 'AZURE_ENV_NAME' 'prod' }
$tenantId     = if ($env:AZURE_TENANT_ID) { $env:AZURE_TENANT_ID } else { ConvertTo-TrimmedString (& az account show --query tenantId -o tsv) }

$apiName = "$envName-api"
$spaName = "$envName-spa"

Write-Log "Tenant: $tenantId"
Write-Log "Env:    $envName"
Write-Log "API app name: $apiName"
Write-Log "SPA app name: $spaName"

# ---------------------------------------------------------------------------
# 1. API app registration
# ---------------------------------------------------------------------------
$apiAppId = ConvertTo-TrimmedString (& az ad app list --display-name $apiName --query '[0].appId' -o tsv 2>$null)
if (-not $apiAppId) {
    Write-Log 'Creating API app registration'
    $apiAppId = ConvertTo-TrimmedString (& az ad app create `
        --display-name $apiName `
        --sign-in-audience AzureADMyOrg `
        --query appId -o tsv)
} else {
    Write-Log "Reusing existing API app $apiAppId"
}

# Identifier URI must equal api://{appId}; safe to set repeatedly.
& az ad app update --id $apiAppId --identifier-uris "api://$apiAppId" 1>$null

# Expose the access_as_user scope (idempotent — only adds when missing).
$apiObjectId = ConvertTo-TrimmedString (& az ad app show --id $apiAppId --query id -o tsv)
$existingScopesJson = & az ad app show --id $apiAppId --query "api.oauth2PermissionScopes" -o json 2>$null
$existingScopes = @()
if ($existingScopesJson) {
    $parsed = $existingScopesJson | ConvertFrom-Json
    if ($parsed) { $existingScopes = @($parsed) }
}
$accessAsUser = $existingScopes | Where-Object { $_.value -eq 'access_as_user' } | Select-Object -First 1
if ($accessAsUser) {
    $scopeId = $accessAsUser.id
    Write-Log "Reusing access_as_user scope ($scopeId)"
} else {
    $scopeId = [guid]::NewGuid().ToString()
    Write-Log "Adding access_as_user scope ($scopeId)"

    # Graph PATCH on api.oauth2PermissionScopes REPLACES the array, and Entra
    # refuses to delete enabled scopes. So merge with any pre-existing scopes.
    $newScope = [pscustomobject]@{
        id                      = $scopeId
        adminConsentDescription = 'Allow the partner console SPA to call the API on behalf of the signed-in user.'
        adminConsentDisplayName = 'Access partner console API'
        userConsentDescription  = 'Allow the partner console SPA to call the API on your behalf.'
        userConsentDisplayName  = 'Access partner console API'
        isEnabled               = $true
        type                    = 'User'
        value                   = 'access_as_user'
    }
    $mergedScopes = @($existingScopes) + @($newScope)
    $scopeBody = @{ api = @{ oauth2PermissionScopes = $mergedScopes } } | ConvertTo-Json -Depth 6 -Compress

    $tmpFile = [IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmpFile -Value $scopeBody -NoNewline -Encoding utf8
        # NOTE: Use /applications/{objectId} form rather than (appId='...').
        # Parentheses in the URL break cmd.exe arg parsing in az.cmd on Windows
        # ("--headers was unexpected at this time").
        & az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$apiObjectId" --headers "Content-Type=application/json" --body "@$tmpFile" 1>$null
    } finally {
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }
}

# Ensure a service principal exists for the API app.
& az ad sp show --id $apiAppId 1>$null 2>$null
if ($LASTEXITCODE -ne 0) { & az ad sp create --id $apiAppId 1>$null }

# ---------------------------------------------------------------------------
# 2. SPA app registration
# ---------------------------------------------------------------------------
$spaAppId = ConvertTo-TrimmedString (& az ad app list --display-name $spaName --query '[0].appId' -o tsv 2>$null)
if (-not $spaAppId) {
    Write-Log 'Creating SPA app registration (multi-tenant)'
    $spaAppId = ConvertTo-TrimmedString (& az ad app create `
        --display-name $spaName `
        --sign-in-audience AzureADMultipleOrgs `
        --query appId -o tsv)
} else {
    Write-Log "Reusing existing SPA app $spaAppId"
}

# Ensure the SPA is multi-tenant. Customer admins sign in against their own
# tenant during Lighthouse onboarding, so AzureADMyOrg would fail with
# AADSTS700016 "Application ... was not found in the directory".
& az ad app update --id $spaAppId --sign-in-audience AzureADMultipleOrgs 1>$null

# SPA platform: ensure localhost redirect is present without clobbering any
# prod redirects already added by postprovision on a prior run. Setting the
# array to localhost-only here causes AADSTS50011 if you re-run preprovision
# after the prod URL was registered.
Write-Log 'Ensuring SPA platform contains localhost redirect (preserving existing entries)'
$spaObjectId = ConvertTo-TrimmedString (& az ad app show --id $spaAppId --query id -o tsv)
$existingSpaJson = & az ad app show --id $spaAppId --query 'spa.redirectUris' -o json 2>$null
$existingSpa = @()
if ($existingSpaJson) {
    $parsed = $existingSpaJson | ConvertFrom-Json
    if ($parsed) { $existingSpa = @($parsed) }
}
$mergedSpa = @(@($existingSpa) + 'http://localhost:5173') | Select-Object -Unique
$spaRedirectBody = @{
    spa = @{ redirectUris = @($mergedSpa) }
    web = @{ redirectUris = @() }
} | ConvertTo-Json -Depth 4 -Compress
# PowerShell collapses single-element arrays to scalars in ConvertTo-Json.
# If we ended up with a string for redirectUris, rewrite it as a JSON array.
if ($spaRedirectBody -match '"redirectUris":"([^"]+)"') {
    $spaRedirectBody = $spaRedirectBody -replace '"redirectUris":"([^"]+)"', '"redirectUris":["$1"]'
}

$tmpSpa = [IO.Path]::GetTempFileName()
try {
    Set-Content -Path $tmpSpa -Value $spaRedirectBody -NoNewline -Encoding utf8
    & az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$spaObjectId" --headers "Content-Type=application/json" --body "@$tmpSpa" 1>$null
} finally {
    Remove-Item $tmpSpa -ErrorAction SilentlyContinue
}

# Grant the SPA delegated permission to the API's access_as_user scope.
Write-Log 'Granting SPA delegated permission on API scope'
& az ad app permission add --id $spaAppId `
    --api $apiAppId --api-permissions "$scopeId=Scope" 2>$null
$LASTEXITCODE = 0  # tolerate "permission already exists"

# Pre-authorize the SPA on the API so users see no consent prompt.
$preAuthBody = @{
    api = @{
        preAuthorizedApplications = @(@{
            appId                  = $spaAppId
            delegatedPermissionIds = @($scopeId)
        })
    }
} | ConvertTo-Json -Depth 6 -Compress

if (-not (Get-Variable -Name apiObjectId -Scope Local -ErrorAction SilentlyContinue) -or -not $apiObjectId) {
    $apiObjectId = ConvertTo-TrimmedString (& az ad app show --id $apiAppId --query id -o tsv)
}
$tmpPreAuth = [IO.Path]::GetTempFileName()
try {
    Set-Content -Path $tmpPreAuth -Value $preAuthBody -NoNewline -Encoding utf8
    & az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$apiObjectId" --headers "Content-Type=application/json" --body "@$tmpPreAuth" 1>$null
} finally {
    Remove-Item $tmpPreAuth -ErrorAction SilentlyContinue
}

& az ad sp show --id $spaAppId 1>$null 2>$null
if ($LASTEXITCODE -ne 0) { & az ad sp create --id $spaAppId 1>$null }

# ---------------------------------------------------------------------------
# 3. Management group + app role
# ---------------------------------------------------------------------------
# Single source of truth for "who can use the partner console". The API
# enforces a `roles` claim with this value on every request. Membership flows:
#   user (azd runner) ──┐
#   UAMI (postprovision)┼─► group AZURE-SMB-RF-MANAGEMENT ──► API app role
#                       │                                  └─► Lighthouse delegation
$securityGroupName = 'AZURE-SMB-RF-MANAGEMENT'
$mgmtRoleValue = 'AZURE-SMB-RF-MANAGEMENT'

# Look up by displayName first (idempotent — never recreates).
$securityGroupId = ConvertTo-TrimmedString (& az ad group list --display-name $securityGroupName --query '[0].id' -o tsv 2>$null)
if (-not $securityGroupId) {
    Write-Log "Creating Entra group $securityGroupName"
    $securityGroupId = ConvertTo-TrimmedString (& az ad group create `
        --display-name $securityGroupName `
        --mail-nickname $securityGroupName `
        --description 'Members can use the SMB-RF partner management console (granted via app role + Lighthouse delegation).' `
        --query id -o tsv)
} else {
    Write-Log "Reusing existing group $securityGroupName ($securityGroupId)"
}

# Add the signed-in azd user to the group (idempotent).
$currentUserId = ConvertTo-TrimmedString (& az ad signed-in-user show --query id -o tsv 2>$null)
if ($currentUserId) {
    $isMember = ConvertTo-TrimmedString (& az ad group member check --group $securityGroupId --member-id $currentUserId --query value -o tsv 2>$null)
    if ($isMember -ne 'true') {
        Write-Log "Adding current user ($currentUserId) to $securityGroupName"
        & az ad group member add --group $securityGroupId --member-id $currentUserId 2>$null
        $LASTEXITCODE = 0
    } else {
        Write-Log 'Current user already a member of management group'
    }
} else {
    Write-Log 'WARN: could not resolve signed-in user object id; skipping membership add'
}

# Ensure app role exists on API app reg (preserve any other roles).
$existingRolesJson = & az ad app show --id $apiAppId --query 'appRoles' -o json 2>$null
$existingRoles = @()
if ($existingRolesJson) {
    $parsed = $existingRolesJson | ConvertFrom-Json
    if ($parsed) { $existingRoles = @($parsed) }
}
$mgmtRole = $existingRoles | Where-Object { $_.value -eq $mgmtRoleValue } | Select-Object -First 1
if ($mgmtRole) {
    $mgmtRoleId = $mgmtRole.id
    Write-Log "Reusing app role $mgmtRoleValue ($mgmtRoleId)"
} else {
    $mgmtRoleId = [guid]::NewGuid().ToString()
    Write-Log "Adding app role $mgmtRoleValue ($mgmtRoleId)"
    $newRole = [pscustomobject]@{
        id                 = $mgmtRoleId
        allowedMemberTypes = @('User', 'Application')
        description        = 'Grants access to the SMB-RF partner management console.'
        displayName        = $mgmtRoleValue
        isEnabled          = $true
        value              = $mgmtRoleValue
    }
    $mergedRoles = @($existingRoles) + @($newRole)
    $rolesBody = @{ appRoles = $mergedRoles } | ConvertTo-Json -Depth 6 -Compress

    $tmpRoles = [IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmpRoles -Value $rolesBody -NoNewline -Encoding utf8
        & az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$apiObjectId" --headers "Content-Type=application/json" --body "@$tmpRoles" 1>$null
    } finally {
        Remove-Item $tmpRoles -ErrorAction SilentlyContinue
    }
}

# Assign the group to the app role on the API service principal (idempotent).
$apiSpId = ConvertTo-TrimmedString (& az ad sp show --id $apiAppId --query id -o tsv)
$existingAssignmentsJson = & az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apiSpId/appRoleAssignedTo" -o json 2>$null
$alreadyAssigned = $false
if ($existingAssignmentsJson) {
    $assignments = ($existingAssignmentsJson | ConvertFrom-Json).value
    foreach ($a in @($assignments)) {
        if ($a.principalId -eq $securityGroupId -and $a.appRoleId -eq $mgmtRoleId) { $alreadyAssigned = $true; break }
    }
}
if ($alreadyAssigned) {
    Write-Log 'Group already assigned to app role'
} else {
    Write-Log 'Assigning management group to API app role'
    $assignBody = @{
        principalId = $securityGroupId
        resourceId  = $apiSpId
        appRoleId   = $mgmtRoleId
    } | ConvertTo-Json -Compress
    $tmpAssign = [IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmpAssign -Value $assignBody -NoNewline -Encoding utf8
        & az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apiSpId/appRoleAssignedTo" --headers "Content-Type=application/json" --body "@$tmpAssign" 1>$null
        $LASTEXITCODE = 0
    } finally {
        Remove-Item $tmpAssign -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# 4. Feed values into azd env (consumed by main.parameters.json + Vite build)
# ---------------------------------------------------------------------------
& azd env set API_APP_CLIENT_ID         $apiAppId
& azd env set SPA_APP_CLIENT_ID         $spaAppId
& azd env set API_APP_SCOPE_ID          $scopeId
& azd env set AZURE_TENANT_ID           $tenantId
& azd env set SECURITY_GROUP_OBJECT_ID $securityGroupId
& azd env set MANAGEMENT_ROLE_NAME      $mgmtRoleValue

# Capture the signed-in az CLI user so the Cosmos AVM module grants them
# data-plane access (otherwise local `az cosmosdb sql ...` queries fail with
# "does not have required RBAC permissions ... readMetadata").
$deployerOid = ConvertTo-TrimmedString (& az ad signed-in-user show --query id -o tsv 2>$null)
if ($deployerOid) {
    & azd env set DEPLOYER_PRINCIPAL_ID $deployerOid
    Write-Log "Deployer principal: $deployerOid"
}

# ---------------------------------------------------------------------------
# 4b. Default REPO_URL / REPO_REF from local git origin so the worker pulls
#     the same fork+branch the operator is currently working on. Skipped if
#     the user has already set them explicitly via `azd env set`.
# ---------------------------------------------------------------------------
$existingRepoUrl = Get-AzdEnv 'REPO_URL'
$existingRepoRef = Get-AzdEnv 'REPO_REF'

if (-not $existingRepoUrl -and (Test-Cmd git)) {
    $originUrl = ConvertTo-TrimmedString (& git -C $PSScriptRoot config --get remote.origin.url 2>$null)
    if ($originUrl) {
        # Normalise SSH form (git@github.com:o/r.git) to https form.
        if ($originUrl -match '^git@([^:]+):(.+)$') {
            $originUrl = "https://$($Matches[1])/$($Matches[2])"
        }
        & azd env set REPO_URL $originUrl
        Write-Log "REPO_URL=$originUrl (from local git origin)"
    }
}

if (-not $existingRepoRef -and (Test-Cmd git)) {
    $branch = ConvertTo-TrimmedString (& git -C $PSScriptRoot rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch -and $branch -ne 'HEAD') {
        & azd env set REPO_REF $branch
        Write-Log "REPO_REF=$branch (from local git HEAD)"
    }
}

Write-Log "API_APP_CLIENT_ID=$apiAppId"
Write-Log "SPA_APP_CLIENT_ID=$spaAppId"
Write-Log "SECURITY_GROUP_OBJECT_ID=$securityGroupId"
Write-Log 'Done.'
