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
#>

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
$HubCidr     = '10.0.0.0/23'
$SpokeCidr   = '10.0.2.0/23'
$OnPremCidr  = '192.168.0.0/16'
$MgId        = 'smb-rf'

# Scenarios to test (baseline already done)
$Scenarios = @('firewall', 'vpn', 'full')

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
function Invoke-Validate {
    param([string]$Scenario)
    $failures = 0

    Write-Log "VALIDATE [$Scenario]: Starting..."

    # 1. Check 6 RGs
    $rgList = az group list --query "[?starts_with(name,'rg-') && (contains(name,'smb') || contains(name,'spoke'))].name" -o tsv 2>$null
    $rgCount = if ([string]::IsNullOrWhiteSpace($rgList)) { 0 } else { @($rgList -split "`n" | Where-Object { $_ }).Count }
    if ($rgCount -ge 6) {
        Write-Log "VALIDATE [$Scenario]: OK $rgCount resource groups"
    } else {
        Write-Log "VALIDATE [$Scenario]: FAIL Only $rgCount resource groups (expected 6)"
        $failures++
    }

    # 2. MG policies (Bicep deploys ~30 individual assignments)
    $policyCount = az policy assignment list --scope "/providers/Microsoft.Management/managementGroups/$MgId" --query "length(@)" -o tsv 2>$null
    $policyCountInt = 0
    if (-not [string]::IsNullOrWhiteSpace($policyCount)) { [int]::TryParse($policyCount, [ref]$policyCountInt) | Out-Null }
    if ($policyCountInt -ge 30) {
        Write-Log "VALIDATE [$Scenario]: OK $policyCountInt MG policies"
    } else {
        Write-Log "VALIDATE [$Scenario]: FAIL Only $policyCountInt MG policies (expected >=30)"
        $failures++
    }

    # 3. Budget
    $budget = az consumption budget list --query "[?starts_with(name,'budget')].amount" -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($budget)) {
        Write-Log "VALIDATE [$Scenario]: OK Budget `$$budget"
    } else {
        Write-Log "VALIDATE [$Scenario]: FAIL No budget found"
        $failures++
    }

    # 4. NAT Gateway (baseline only — firewall/vpn/full use FW or GW transit)
    $natCount = az network nat-gateway list -g "rg-spoke-prod-$RegionAbbr" --query "length(@)" -o tsv 2>$null
    if (-not $natCount) { $natCount = 0 }
    if ($Scenario -eq 'baseline') {
        if ([int]$natCount -ge 1) {
            Write-Log "VALIDATE [$Scenario]: OK NAT Gateway present"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL NAT Gateway missing (expected for baseline)"
            $failures++
        }
    }

    # 5. Firewall (firewall/full only)
    $fwCount = az network firewall list -g "rg-hub-smb-$RegionAbbr" --query "length(@)" -o tsv 2>$null
    if (-not $fwCount) { $fwCount = 0 }
    if ($Scenario -in @('firewall', 'full')) {
        if ([int]$fwCount -ge 1) {
            Write-Log "VALIDATE [$Scenario]: OK Azure Firewall present"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL Firewall missing"
            $failures++
        }
    } else {
        if ([int]$fwCount -eq 0) {
            Write-Log "VALIDATE [$Scenario]: OK No Firewall (correct for $Scenario)"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL Unexpected Firewall found"
            $failures++
        }
    }

    # 6. VPN Gateway (vpn/full only)
    $vpnCount = az network vnet-gateway list -g "rg-hub-smb-$RegionAbbr" --query "length(@)" -o tsv 2>$null
    if (-not $vpnCount) { $vpnCount = 0 }
    if ($Scenario -in @('vpn', 'full')) {
        if ([int]$vpnCount -ge 1) {
            Write-Log "VALIDATE [$Scenario]: OK VPN Gateway present"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL VPN Gateway missing"
            $failures++
        }
    } else {
        if ([int]$vpnCount -eq 0) {
            Write-Log "VALIDATE [$Scenario]: OK No VPN Gateway (correct for $Scenario)"
        } else {
            Write-Log "VALIDATE [$Scenario]: FAIL Unexpected VPN Gateway"
            $failures++
        }
    }

    # 7. VNet peering (firewall/vpn/full)
    $peeringCount = az network vnet peering list -g "rg-hub-smb-$RegionAbbr" --vnet-name "vnet-hub-smb-$RegionAbbr" --query "length(@)" -o tsv 2>$null
    if (-not $peeringCount) { $peeringCount = 0 }
    if ($Scenario -ne 'baseline') {
        if ([int]$peeringCount -ge 1) {
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
        $rtCount = az network route-table list -g "rg-hub-smb-$RegionAbbr" --query "length(@)" -o tsv 2>$null
        if (-not $rtCount) { $rtCount = 0 }
        if ([int]$rtCount -ge 1) {
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

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogFile) | Out-Null
Set-Content -Path $LogFile -Value ''
Write-Hr
Write-Log 'SMB Ready Foundations (Bicep) — Scenario Test Runner'
Write-Log "Scenarios: $($Scenarios -join ' ')"
Write-Hr

# First: tear down baseline
Write-Log 'Starting with baseline teardown...'
Invoke-Teardown -Scenario 'baseline'
Write-Hr

foreach ($scenario in $Scenarios) {
    Write-Hr
    Write-Log "=== SCENARIO: $scenario ==="
    Write-Hr

    Invoke-ConfigureEnv -Scenario $scenario

    if (-not (Invoke-Deploy -Scenario $scenario)) {
        Write-Log "FATAL: $scenario deploy failed after retry — stopping"
        exit 1
    }

    $valFailures = Invoke-Validate -Scenario $scenario
    if ($valFailures -gt 0) {
        Write-Log "WARNING: $scenario validation had failures — continuing to teardown"
    }

    # Teardown after every scenario including the final 'full' run so the
    # subscription is left clean.
    Invoke-Teardown -Scenario $scenario

    Write-Hr
}

Write-Log '=== ALL SCENARIOS COMPLETE ==='
