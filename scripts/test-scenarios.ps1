<#
.SYNOPSIS
    SMB Ready Foundations (Bicep) — Automated Scenario Test Runner.
.DESCRIPTION
    PowerShell parallel of scripts/test-scenarios.sh.
    Runs: teardown (baseline) -> firewall -> vpn -> full
    Each scenario: configure -> deploy -> validate -> teardown -> next.
    Tears down every scenario including the final full scenario so the
    subscription is left clean. MG + MG policies persist across scenarios;
    only RGs + budget are torn down between runs.
.PARAMETER Scenarios
    Override which scenarios to run. Defaults to firewall,vpn,full.
.PARAMETER SkipBaselineTeardown
    Skip the initial baseline teardown (use when resuming a partial run
    where the previous teardown already completed).
.PARAMETER ResumeFromTeardown
    For the FIRST scenario in -Scenarios, skip configure+deploy+validate and
    jump straight to teardown. Use when that scenario is already deployed
    and validated from a prior run.
.PARAMETER NoTruncateLog
    Append to the log file instead of truncating it on start.
#>
param(
    [string[]]$Scenarios = @('firewall', 'vpn', 'full'),
    [switch]$SkipBaselineTeardown,
    [switch]$ResumeFromTeardown,
    [switch]$NoTruncateLog
)

$ErrorActionPreference = 'Stop'

$RepoRoot       = Split-Path -Parent $PSScriptRoot
$ProjDir        = Join-Path $RepoRoot 'infra/bicep/smb-ready-foundation'
$LogFile        = Join-Path $RepoRoot 'logs/test-scenarios.log'
$Owner          = 'jonathan@lordofthecloud.eu'
$Location       = 'swedencentral'
$SubscriptionId = if ($env:AZURE_SUBSCRIPTION_ID) {
    $env:AZURE_SUBSCRIPTION_ID
} else {
    (az account show --query id -o tsv 2>$null)
}
# Resolve tenant for the target subscription so azd doesn't fall back to the
# user's home tenant when the sub lives in a different (guest) tenant.
$TenantId = if ($env:AZURE_TENANT_ID) {
    $env:AZURE_TENANT_ID
} elseif (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    (az account show --subscription $SubscriptionId --query tenantId -o tsv 2>$null)
} else { '' }
$HubCidr     = '10.0.0.0/23'
$SpokeCidr   = '10.0.2.0/23'
$OnPremCidr  = '192.168.0.0/16'
$MgId        = 'smb-rf'

# Region abbreviation
$RegionAbbr = 'swc'

# Resource groups to tear down between scenarios
$Rgs = @(
    "rg-hub-smb-$RegionAbbr"
    "rg-spoke-prod-$RegionAbbr"
    "rg-monitor-smb-$RegionAbbr"
    "rg-backup-smb-$RegionAbbr"
    "rg-migrate-smb-$RegionAbbr"
    "rg-security-smb-$RegionAbbr"
)

function Get-Ts { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Ts)] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Write-Hr {
    $line = '============================================================'
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

# Run a command and tee its combined stdout/stderr into the log; returns exit code.
function Invoke-Tee {
    param([scriptblock]$ScriptBlock)
    $output = & $ScriptBlock 2>&1
    $exit = $LASTEXITCODE
    foreach ($line in $output) {
        $text = if ($line -is [System.Management.Automation.ErrorRecord]) { $line.ToString() } else { "$line" }
        Write-Host $text
        Add-Content -Path $LogFile -Value $text
    }
    return $exit
}

# ---- Teardown ----------------------------------------------------------------
# Remove the MG-scoped baseline initiative assignment + policy set definition.
# Bicep deploys these as a single Policy Set (`smb-baseline`) plus one
# assignment of the same name; tear them down as the initiative, not as the
# 30+ individual policies that used to be assigned in the legacy layout.
function Remove-MgInitiative {
    param([string]$Scenario)

    $mgScope = "/providers/Microsoft.Management/managementGroups/$MgId"

    Write-Log "TEARDOWN [$Scenario]: Deleting MG initiative assignment 'smb-baseline'..."
    az policy assignment delete --name 'smb-baseline' --scope $mgScope 2>$null | Out-Null

    Write-Log "TEARDOWN [$Scenario]: Deleting MG policy set definition 'smb-baseline'..."
    az policy set-definition delete --name 'smb-baseline' --management-group $MgId 2>$null | Out-Null
}

# Ensure the target management group exists and the test subscription is
# associated with it. Phase 0 normally creates this once per tenant; doing it
# here makes the script self-bootstrapping for fresh subscriptions.
function Confirm-ManagementGroup {
    $existing = az account management-group show --name $MgId --query name -o tsv 2>$null
    if ($existing -eq $MgId) {
        Write-Log "MG '$MgId' exists."
    } else {
        Write-Log "MG '$MgId' not found — creating..."
        az account management-group create --name $MgId --display-name 'SMB Ready Foundations' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: failed to create MG '$MgId'. Run scripts/Setup-ManagementGroupPermissions.ps1 first to grant tenant-root permissions."
            exit 1
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $assoc = az account management-group subscription show --name $MgId --subscription $SubscriptionId --query id -o tsv 2>$null
        if (-not $assoc) {
            Write-Log "Adding subscription $SubscriptionId to MG '$MgId'..."
            az account management-group subscription add --name $MgId --subscription $SubscriptionId 2>$null | Out-Null
        }
    }
}

function Invoke-Teardown {
    param([string]$Scenario)

    Write-Log "TEARDOWN [$Scenario]: Deleting resource groups..."
    foreach ($rg in $Rgs) {
        az group delete --name $rg --yes --no-wait 2>$null | Out-Null
    }

    Write-Log "TEARDOWN [$Scenario]: Waiting for RG deletions..."
    foreach ($rg in $Rgs) {
        az group wait --name $rg --deleted 2>$null | Out-Null
    }

    # Delete budget
    az consumption budget delete --budget-name budget-smb-monthly 2>$null | Out-Null

    # MG-scope cleanup: remove the baseline initiative (assignment + set def)
    Remove-MgInitiative -Scenario $Scenario

    # Verify cleanup
    $remaining = az group list --query "[?starts_with(name,'rg-') && (contains(name,'smb') || contains(name,'spoke'))].name" -o tsv 2>$null
    $remainingCount = if ([string]::IsNullOrWhiteSpace($remaining)) { 0 } else { @($remaining -split "`n" | Where-Object { $_ }).Count }
    if ($remainingCount -eq 0) {
        Write-Log "TEARDOWN [$Scenario]: CLEAN — no smb/spoke RGs remain"
    } else {
        Write-Log "TEARDOWN [$Scenario]: WARNING — $remainingCount RGs still exist"
        $remaining | ForEach-Object { Write-Log $_ }
    }
}

# ---- Configure azd env -------------------------------------------------------
function Invoke-ConfigureEnv {
    param([string]$Scenario)

    Set-Location $ProjDir
    $envName = "smb-rf-$Scenario"

    azd env select $envName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        azd env new $envName --no-prompt --location $Location --subscription $SubscriptionId | Out-Null
        azd env select $envName 2>$null | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        azd env set AZURE_SUBSCRIPTION_ID $SubscriptionId | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
        azd env set AZURE_TENANT_ID $TenantId | Out-Null
    }
    azd env set SCENARIO $Scenario | Out-Null
    azd env set OWNER $Owner | Out-Null
    azd env set AZURE_LOCATION $Location | Out-Null
    azd env set ENVIRONMENT prod | Out-Null
    azd env set HUB_VNET_ADDRESS_SPACE $HubCidr | Out-Null
    azd env set SPOKE_VNET_ADDRESS_SPACE $SpokeCidr | Out-Null
    azd env set LOG_ANALYTICS_DAILY_CAP_GB '0.5' | Out-Null
    azd env set MANAGEMENT_GROUP_ID $MgId | Out-Null

    # vpn and full need ON_PREMISES_ADDRESS_SPACE
    if ($Scenario -in @('vpn', 'full')) {
        azd env set ON_PREMISES_ADDRESS_SPACE $OnPremCidr | Out-Null
    }

    Write-Log "CONFIGURE [$Scenario]: azd env set complete"
    Invoke-Tee { azd env get-values } | Out-Null
}

# ---- Deploy ------------------------------------------------------------------
function Invoke-Deploy {
    param([string]$Scenario)

    Set-Location $ProjDir
    $start = Get-Date
    Write-Log "DEPLOY [$Scenario]: Starting azd up..."

    $exitCode = Invoke-Tee { azd up --no-prompt }
    $duration = [int]((Get-Date) - $start).TotalSeconds

    if ($exitCode -eq 0) {
        Write-Log "DEPLOY [$Scenario]: SUCCESS (${duration}s)"
        return $true
    }

    Write-Log "DEPLOY [$Scenario]: FAILED exit=$exitCode (${duration}s) — retrying once..."
    Start-Sleep -Seconds 60
    $start = Get-Date
    $exitCode = Invoke-Tee { azd up --no-prompt }
    $duration = [int]((Get-Date) - $start).TotalSeconds
    if ($exitCode -eq 0) {
        Write-Log "DEPLOY [$Scenario]: RETRY SUCCESS (${duration}s)"
        return $true
    }
    Write-Log "DEPLOY [$Scenario]: RETRY FAILED exit=$exitCode (${duration}s) — STOPPING"
    return $false
}

# ---- Validate ----------------------------------------------------------------
# Some shells/transcripts inject prompt or trace text into captured native-cmd
# stdout. Sanitize az output by keeping only the last non-empty line that
# matches a tsv-like value (digits, GUID, or simple name) — and discard any
# echoed prompts like 'F:\path>' or python invocations.
function Get-AzTsv {
    # Plain function (no advanced binding) so -o, -g etc. pass through
    # unambiguously to az without colliding with PowerShell common parameters.
    # On Windows, az.cmd is a batch wrapper — cmd.exe re-parses unquoted (), [],
    # &, | as syntax. We auto-wrap the value following --query in literal double
    # quotes so JMESPath expressions like length(@) survive.
    # Returns ALL sanitized non-empty lines joined by newline.
    $cleaned = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $args.Count; $i++) {
        $tok = $args[$i]
        $cleaned.Add($tok)
        if ($tok -eq '--query' -and ($i + 1) -lt $args.Count) {
            $val = "$($args[$i + 1])"
            if ($val -notmatch '^".*"$') { $val = '"' + $val + '"' }
            $cleaned.Add($val)
            $i++
        }
    }
    $raw = & az $cleaned.ToArray() 2>$null
    if (-not $raw) { return '' }
    $lines = ($raw -split "`r?`n") |
        Where-Object { $_ -and ($_ -notmatch '^[A-Za-z]:\\.*>') -and ($_ -notmatch 'python\.exe') -and ($_ -notmatch '^\s*"') } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
    if (-not $lines -or $lines.Count -eq 0) { return '' }
    return ($lines -join "`n")
}

function ConvertTo-IntSafe {
    param($Value)
    if ($null -eq $Value) { return 0 }
    $s = "$Value".Trim()
    if ($s -match '^\d+$') { return [int]$s }
    return 0
}

function Invoke-Validate {
    param([string]$Scenario)
    $failures = 0

    Write-Log "VALIDATE [$Scenario]: Starting..."

    # 1. Check 6 RGs
    $rgList = Get-AzTsv group list --query "[?starts_with(name,'rg-') && (contains(name,'smb') || contains(name,'spoke'))].name" -o tsv
    $rgCount = if ([string]::IsNullOrWhiteSpace($rgList)) { 0 } else { @($rgList -split "`n" | Where-Object { $_ }).Count }
    if ($rgCount -ge 6) {
        Write-Log "VALIDATE [$Scenario]: OK $rgCount resource groups"
    } else {
        Write-Log "VALIDATE [$Scenario]: FAIL Only $rgCount resource groups (expected 6)"
        $failures++
    }

    # 2. MG initiative (policy set) assignment — consolidated from 30+ separate assignments
    $policyCount = Get-AzTsv policy assignment list --scope "/providers/Microsoft.Management/managementGroups/$MgId" --query "length([?name=='smb-baseline'])" -o tsv
    if ((ConvertTo-IntSafe $policyCount) -eq 1) {
        Write-Log "VALIDATE [$Scenario]: OK smb-baseline initiative assigned"
    } else {
        Write-Log "VALIDATE [$Scenario]: FAIL smb-baseline initiative missing (expected 1, got $policyCount)"
        $failures++
    }

    # 3. Budget
    $budget = Get-AzTsv consumption budget list --query "[?starts_with(name,'budget')].amount" -o tsv
    if (-not [string]::IsNullOrWhiteSpace($budget)) {
        Write-Log "VALIDATE [$Scenario]: OK Budget `$$budget"
    } else {
        Write-Log "VALIDATE [$Scenario]: FAIL No budget found"
        $failures++
    }

    # 4. NAT Gateway (baseline only — firewall/vpn/full use FW or GW transit)
    $natCount = ConvertTo-IntSafe (Get-AzTsv network nat-gateway list -g "rg-spoke-prod-$RegionAbbr" --query "length(@)" -o tsv)
    if ($Scenario -eq 'baseline') {
        if ($natCount -ge 1) {
            Write-Log "VALIDATE [$Scenario]: OK NAT Gateway present"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL NAT Gateway missing (expected for baseline)"
            $failures++
        }
    }

    # 5. Firewall (firewall/full only)
    $fwCount = ConvertTo-IntSafe (Get-AzTsv network firewall list -g "rg-hub-smb-$RegionAbbr" --query "length(@)" -o tsv)
    if ($Scenario -in @('firewall', 'full')) {
        if ($fwCount -ge 1) {
            Write-Log "VALIDATE [$Scenario]: OK Azure Firewall present"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL Firewall missing"
            $failures++
        }
    } else {
        if ($fwCount -eq 0) {
            Write-Log "VALIDATE [$Scenario]: OK No Firewall (correct for $Scenario)"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL Unexpected Firewall found"
            $failures++
        }
    }

    # 6. VPN Gateway (vpn/full only)
    $vpnCount = ConvertTo-IntSafe (Get-AzTsv network vnet-gateway list -g "rg-hub-smb-$RegionAbbr" --query "length(@)" -o tsv)
    if ($Scenario -in @('vpn', 'full')) {
        if ($vpnCount -ge 1) {
            Write-Log "VALIDATE [$Scenario]: OK VPN Gateway present"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL VPN Gateway missing"
            $failures++
        }
    } else {
        if ($vpnCount -eq 0) {
            Write-Log "VALIDATE [$Scenario]: OK No VPN Gateway (correct for $Scenario)"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL Unexpected VPN Gateway"
            $failures++
        }
    }

    # 7. VNet peering (firewall/vpn/full)
    $peeringCount = ConvertTo-IntSafe (Get-AzTsv network vnet peering list -g "rg-hub-smb-$RegionAbbr" --vnet-name "vnet-hub-smb-$RegionAbbr" --query "length(@)" -o tsv)
    if ($Scenario -ne 'baseline') {
        if ($peeringCount -ge 1) {
            Write-Log "VALIDATE [$Scenario]: OK VNet peering established"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL VNet peering missing"
            $failures++
        }
    } else {
        if ([int]$peeringCount -eq 0) {
            Write-Log "VALIDATE [$Scenario]: OK No peering (correct for baseline)"
        }
    }

    # 8. Route tables (firewall/full only — deployed to hub RG by design)
    if ($Scenario -in @('firewall', 'full')) {
        $rtCount = ConvertTo-IntSafe (Get-AzTsv network route-table list -g "rg-hub-smb-$RegionAbbr" --query "length(@)" -o tsv)
        if ($rtCount -ge 1) {
            Write-Log "VALIDATE [$Scenario]: OK Route tables present"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL Route tables missing"
            $failures++
        }
    }

    if ($failures -eq 0) {
        Write-Log "VALIDATE [$Scenario]: ALL CHECKS PASSED"
    } else {
        Write-Log "VALIDATE [$Scenario]: $failures CHECKS FAILED"
    }
    return $failures
}

# ============================================================================
# MAIN
# ============================================================================

# Allow this script to be dot-sourced for testing individual functions
# without running the full deploy/validate/teardown loop.
if ($env:SMB_LOAD_ONLY -eq '1') { return }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogFile) | Out-Null
if (-not $NoTruncateLog) { Set-Content -Path $LogFile -Value '' }
Write-Hr
Write-Log 'SMB Ready Foundations (Bicep) — Scenario Test Runner'
Write-Log "Scenarios: $($Scenarios -join ' ')"
if ($SkipBaselineTeardown) { Write-Log 'Resume mode: skipping initial baseline teardown' }
if ($ResumeFromTeardown)   { Write-Log "Resume mode: first scenario ($($Scenarios[0])) will start at teardown" }
Write-Hr

# Phase 0: ensure MG exists and sub is associated
Confirm-ManagementGroup

# First: tear down baseline
if (-not $SkipBaselineTeardown) {
    Write-Log 'Starting with baseline teardown...'
    Invoke-Teardown -Scenario 'baseline'
    Write-Hr
}

$first = $true
foreach ($scenario in $Scenarios) {
    Write-Hr
    Write-Log "=== SCENARIO: $scenario ==="
    Write-Hr

    if ($first -and $ResumeFromTeardown) {
        Write-Log "RESUME [$scenario]: skipping configure/deploy/validate — going straight to teardown"
    }
    else {
        Invoke-ConfigureEnv -Scenario $scenario

        if (-not (Invoke-Deploy -Scenario $scenario)) {
            Write-Log "FATAL: $scenario deploy failed after retry — stopping"
            exit 1
        }

        $valFailures = Invoke-Validate -Scenario $scenario
        if ($valFailures -gt 0) {
            Write-Log "WARNING: $scenario validation had failures — continuing to teardown"
        }
    }

    # Teardown after every scenario including the final 'full' run so the
    # subscription is left clean.
    Invoke-Teardown -Scenario $scenario

    Write-Hr
    $first = $false
}

Write-Log '=== ALL SCENARIOS COMPLETE ==='
