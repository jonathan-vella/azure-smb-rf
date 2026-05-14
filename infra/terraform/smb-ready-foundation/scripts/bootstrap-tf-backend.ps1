<#
.SYNOPSIS
    Bootstrap the Terraform remote state backend for smb-ready-foundation.
.DESCRIPTION
    Idempotent. Creates (if missing):
      - Resource group            rg-tfstate-smb-<region_short>
      - Storage account           sttfstatesmb<hash>   (globally unique)
      - Blob container            tfstate
    Writes backend values to <iac_path>/.azure/<env>/backend.hcl.
#>
[CmdletBinding()]
param(
  [string]$Location = $(if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION } else { 'swedencentral' }),
  [string]$EnvName  = $(if ($env:AZURE_ENV_NAME) { $env:AZURE_ENV_NAME } else { 'smb-ready-foundation' })
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$iacPath   = Split-Path -Parent $scriptDir

$regionShort = switch ($Location) {
  'swedencentral'      { 'swc' }
  'germanywestcentral' { 'gwc' }
  default              { $Location.Substring(0, 3) }
}

$rgName        = "rg-tfstate-smb-$regionShort"
$containerName = 'tfstate'

$subId = az account show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($subId)) { throw 'Not authenticated. Run az login.' }

$sha = [System.Security.Cryptography.SHA1]::Create()
$hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($subId))
$hash = (($hashBytes | ForEach-Object ToString x2) -join '').Substring(0, 12)
$saName = "sttfstatesmb$hash"

$backendDir  = Join-Path $iacPath ".azure/$EnvName"
$backendFile = Join-Path $backendDir 'backend.hcl'

Write-Host "==> Bootstrapping Terraform state backend"
Write-Host "    RG:        $rgName"
Write-Host "    Storage:   $saName"
Write-Host "    Container: $containerName"
Write-Host "    Backend:   $backendFile"

# Resource group
$rgExists = az group exists -n $rgName
if ($rgExists -ne 'true') {
  az group create -n $rgName -l $Location `
    --tags Environment=smb Owner=platform Project=smb-ready-foundation ManagedBy=Terraform | Out-Null
  Write-Host '    + resource group created'
} else {
  Write-Host '    . resource group exists'
}

# Storage account — tenant policy forbids shared-key auth, use Entra ID throughout.
$saShow = az storage account show -n $saName -g $rgName 2>$null
if ($LASTEXITCODE -ne 0 -or -not $saShow) {
  az storage account create `
    -n $saName -g $rgName -l $Location `
    --sku Standard_LRS --kind StorageV2 `
    --https-only true `
    --allow-blob-public-access false `
    --allow-shared-key-access false `
    --min-tls-version TLS1_2 `
    --tags Environment=smb Owner=platform Project=smb-ready-foundation ManagedBy=Terraform Purpose=tfstate | Out-Null
  Write-Host '    + storage account created (shared-key disabled)'
} else {
  az storage account update -n $saName -g $rgName --allow-shared-key-access false 2>$null | Out-Null
  Write-Host '    . storage account exists'
}

# RBAC: Storage Blob Data Contributor for current principal (required for use_azuread_auth)
$saId = az storage account show -n $saName -g $rgName --query id -o tsv
$principalId = az ad signed-in-user show --query id -o tsv 2>$null
if (-not [string]::IsNullOrWhiteSpace($principalId)) {
  $existing = az role assignment list --assignee $principalId --scope $saId --role 'Storage Blob Data Contributor' --query '[0].id' -o tsv 2>$null
  if ([string]::IsNullOrWhiteSpace($existing)) {
    az role assignment create --assignee-object-id $principalId --assignee-principal-type User `
      --role 'Storage Blob Data Contributor' --scope $saId | Out-Null
    Write-Host '    + granted Storage Blob Data Contributor to current user (propagation: ~30s)'
    Start-Sleep -Seconds 30
  } else {
    Write-Host '    . Storage Blob Data Contributor already assigned'
  }
}

$containerShow = az storage container show --name $containerName --account-name $saName --auth-mode login 2>$null
if ($LASTEXITCODE -ne 0 -or -not $containerShow) {
  az storage container create --name $containerName --account-name $saName --auth-mode login | Out-Null
  Write-Host '    + container created'
} else {
  Write-Host '    . container exists'
}

# Write backend.hcl (use_azuread_auth=true so Terraform uses Entra ID, not keys)
New-Item -ItemType Directory -Force -Path $backendDir | Out-Null
$backendContent = @"
resource_group_name  = "$rgName"
storage_account_name = "$saName"
container_name       = "$containerName"
key                  = "smb-ready-foundation.tfstate"
use_azuread_auth     = true
"@
Set-Content -Path $backendFile -Value $backendContent -Encoding UTF8
Write-Host "    + wrote $backendFile"

Write-Host "==> Done. Run: terraform init -backend-config=$backendFile"
