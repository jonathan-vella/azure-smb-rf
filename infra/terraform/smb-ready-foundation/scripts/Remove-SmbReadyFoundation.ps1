<#
.SYNOPSIS
    Teardown SMB Ready Foundation Terraform deployment.
.DESCRIPTION
    Runs terraform destroy, then optionally deletes the management group
    and/or the state backend storage account.
.PARAMETER Yes
    Skip confirmation prompt.
.PARAMETER DeleteMg
    Also delete the smb-rf management group after destroy.
.PARAMETER DeleteBackend
    Also delete the tfstate storage account + RG.
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$DeleteMg,
    [switch]$DeleteBackend
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$iacDir    = Split-Path -Parent $scriptDir

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  SMB Ready Foundation — Teardown' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

$subId = az account show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($subId)) { throw 'Not authenticated.' }
$subName = az account show --query name -o tsv
Write-Host "  Subscription: $subName ($subId)"
Write-Host ''

if (-not $Yes) {
    Write-Host '  This will DESTROY all SMB Ready Foundation resources managed by Terraform.' -ForegroundColor Yellow
    $confirm = Read-Host '  Type the subscription id to confirm'
    if ($confirm -ne $subId) { Write-Host '  Aborted.'; exit 1 }
}

Push-Location $iacDir
try {
    # Pre-destroy: drop stale budget.
    az consumption budget delete --budget-name 'budget-smb-monthly' 2>$null | Out-Null

    Write-Host ''
    Write-Host '==> terraform destroy' -ForegroundColor Cyan
    if ($Yes) {
        terraform destroy -auto-approve -input=false
    } else {
        terraform destroy -input=false
    }

    if ($DeleteMg) {
        Write-Host ''
        Write-Host '==> Deleting management group smb-rf' -ForegroundColor Cyan
        az account management-group delete --name smb-rf 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host '    (MG delete failed — ensure no child subscriptions remain)' -ForegroundColor Yellow
        }
    }

    if ($DeleteBackend) {
        $location = if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION } else { 'swedencentral' }
        $regionShort = switch ($location) {
            'swedencentral'      { 'swc' }
            'germanywestcentral' { 'gwc' }
            default              { $location.Substring(0, 3) }
        }
        $backendRg = "rg-tfstate-smb-$regionShort"
        Write-Host ''
        Write-Host "==> Deleting state backend RG $backendRg" -ForegroundColor Cyan
        az group delete --name $backendRg --yes --no-wait 2>$null | Out-Null
    }
} finally { Pop-Location }

Write-Host ''
Write-Host '==> Teardown complete.' -ForegroundColor Green
Write-Host ''
