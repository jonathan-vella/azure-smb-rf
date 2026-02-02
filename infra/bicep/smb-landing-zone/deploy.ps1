<#
.SYNOPSIS
    Deploys the SMB Landing Zone infrastructure to Azure.

.DESCRIPTION
    This script validates and deploys the SMB Landing Zone Bicep templates
    to an Azure subscription. It performs pre-flight checks, validates templates,
    runs what-if analysis, and deploys the infrastructure.

    When run without parameters, it enters interactive mode and prompts for
    configuration values with sensible defaults.

    DEPLOYMENT SCENARIOS:
    - baseline:   NAT Gateway only (~$48/mo) - cloud-native, no hybrid
    - firewall:   Azure Firewall + UDR (~$336/mo) - egress filtering
    - vpn:        VPN Gateway + Gateway Transit (~$187/mo) - hybrid connectivity
    - full:       Firewall + VPN + UDR (~$476/mo) - complete security

    RESILIENCE FEATURES:
    - Automatically cleans up stale budgets (Azure API limitation)
    - Detects and removes faulted firewall resources
    - Retry logic with exponential backoff for transient failures
    - Use -Force to clean up before deployment (for failed deployments)

.PARAMETER Scenario
    Deployment scenario preset. Valid values:
    - baseline:   NAT Gateway only (default)
    - firewall:   Azure Firewall with egress filtering
    - vpn:        VPN Gateway for hybrid connectivity
    - full:       Both Firewall and VPN Gateway

.PARAMETER Environment
    The target environment (dev, staging, prod). Default: prod

.PARAMETER Owner
    Owner email or team name for resource tagging. If not provided, uses
    the email from the current Azure CLI login.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral

.PARAMETER HubVnetAddressSpace
    Hub VNet CIDR address space. Default: 10.0.0.0/16

.PARAMETER SpokeVnetAddressSpace
    Spoke VNet CIDR address space. Default: 10.1.0.0/16

.PARAMETER OnPremisesAddressSpace
    On-premises CIDR for VPN routing (required for vpn/full scenarios).

.PARAMETER LogAnalyticsDailyCapGb
    Log Analytics daily ingestion cap in GB (decimal). Default: 0.5 (~500MB)

.PARAMETER BudgetAmount
    Monthly budget in USD. Default: 500

.PARAMETER NonInteractive
    Skip interactive prompts and use defaults/provided parameters.

.PARAMETER Force
    Clean up stale resources before deployment. Use when recovering from
    a failed deployment or redeploying to the same subscription.

.PARAMETER MaxRetries
    Maximum number of retry attempts for transient deployment failures.
    Default: 3

.EXAMPLE
    .\deploy.ps1
    # Interactive mode - prompts for configuration (defaults to baseline)

.EXAMPLE
    .\deploy.ps1 -Scenario firewall
    # Deploy with Azure Firewall for egress filtering

.EXAMPLE
    .\deploy.ps1 -Scenario vpn -OnPremisesAddressSpace "192.168.0.0/16"
    # Deploy with VPN Gateway for hybrid connectivity

.EXAMPLE
    .\deploy.ps1 -Scenario full -OnPremisesAddressSpace "192.168.0.0/16"
    # Deploy with both Firewall and VPN Gateway

.EXAMPLE
    .\deploy.ps1 -NonInteractive -Owner "partner-ops@contoso.com"
    # Non-interactive baseline deployment with explicit owner

.EXAMPLE
    .\deploy.ps1 -Force -Scenario full
    # Force cleanup before deploying full scenario

.NOTES
    Version: 0.5
    Author: Agentic InfraOps
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('baseline', 'firewall', 'vpn', 'full')]
    [string]$Scenario = 'baseline',

    [Parameter()]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'prod',

    [Parameter()]
    [string]$Owner,

    [Parameter()]
    [ValidateSet('swedencentral', 'germanywestcentral')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [string]$HubVnetAddressSpace = '10.0.0.0/23',

    [Parameter()]
    [string]$SpokeVnetAddressSpace = '10.0.2.0/23',

    [Parameter()]
    [string]$OnPremisesAddressSpace = '',

    [Parameter()]
    [string]$LogAnalyticsDailyCapGb = '0.5',

    [Parameter()]
    [ValidateRange(100, 10000)]
    [int]$BudgetAmount = 500,

    [Parameter()]
    [switch]$NonInteractive,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateRange(1, 5)]
    [int]$MaxRetries = 3
)

#region Helper Functions

function Write-Banner {
    $banner = @"

╔═══════════════════════════════════════════════════════════════════════════════╗
║   _____ __  __ ____    _                    _ _                 _____         ║
║  / ____|  \/  |  _ \  | |                  | (_)               |___  |        ║
║ | (___ | \  / | |_) | | |     __ _ _ __   __| |_ _ __   __ _     / /___  _ __  ║
║  \___ \| |\/| |  _ <  | |    / _\`| '_ \ / _\`| | '_ \ / _\` |   / // _ \| '_ \ ║
║  ____) | |  | | |_) | | |___| (_| | | | | (_| | | | | | (_| |  / /| (_) | | | |║
║ |_____/|_|  |_|____/  |______\__,_|_| |_|\__,_|_|_| |_|\__, | /_/  \___/|_| |_|║
║                                                         __/ |                  ║
║   Azure Infrastructure Deployment                      |___/   v0.5           ║
╚═══════════════════════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

# Scenario descriptions for display
function Get-ScenarioDescription {
    param([string]$ScenarioName)
    switch ($ScenarioName) {
        'baseline'   { return "NAT Gateway only (~`$48/mo)" }
        'firewall'   { return "Firewall + UDR (~`$336/mo)" }
        'vpn'        { return "VPN Gateway (~`$187/mo)" }
        'full'       { return "Firewall + VPN (~`$476/mo)" }
        default      { return $ScenarioName }
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "│  $($Title.PadRight(66))│" -ForegroundColor DarkGray
    Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Step {
    param(
        [string]$Step,
        [string]$Message
    )
    Write-Host "  [$Step] $Message" -ForegroundColor White
}

function Write-SubStep {
    param([string]$Message)
    Write-Host "      └─ $Message" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Label, [string]$Value)
    Write-Host "      • $($Label): " -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor White
}

function Read-HostWithDefault {
    param(
        [string]$Prompt,
        [string]$Default
    )
    $userInput = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($userInput)) { return $Default }
    return $userInput
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )
    $defaultText = if ($Default) { "Y/n" } else { "y/N" }
    $userInput = Read-Host "$Prompt [$defaultText]"
    if ([string]::IsNullOrWhiteSpace($userInput)) { return $Default }
    return $userInput -match '^[Yy](es)?$'
}

function Test-CidrOverlap {
    param(
        [string]$Cidr1,
        [string]$Cidr2
    )
    # Parse CIDR notation
    $parts1 = $Cidr1 -split '/'
    $parts2 = $Cidr2 -split '/'
    
    $ip1 = [System.Net.IPAddress]::Parse($parts1[0])
    $ip2 = [System.Net.IPAddress]::Parse($parts2[0])
    $prefix1 = [int]$parts1[1]
    $prefix2 = [int]$parts2[1]
    
    # Convert to integers
    $bytes1 = $ip1.GetAddressBytes()
    $bytes2 = $ip2.GetAddressBytes()
    [Array]::Reverse($bytes1)
    [Array]::Reverse($bytes2)
    $int1 = [BitConverter]::ToUInt32($bytes1, 0)
    $int2 = [BitConverter]::ToUInt32($bytes2, 0)
    
    # Calculate network masks
    $mask1 = [uint32]::MaxValue -shl (32 - $prefix1)
    $mask2 = [uint32]::MaxValue -shl (32 - $prefix2)
    
    # Get network addresses
    $net1 = $int1 -band $mask1
    $net2 = $int2 -band $mask2
    
    # Check overlap using the smaller mask (larger network)
    $smallerMask = if ($prefix1 -lt $prefix2) { $mask1 } else { $mask2 }
    
    return ($net1 -band $smallerMask) -eq ($net2 -band $smallerMask)
}

function Test-ValidCidr {
    param([string]$Cidr)
    if ($Cidr -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$') {
        return $false
    }
    try {
        $parts = $Cidr -split '/'
        [System.Net.IPAddress]::Parse($parts[0]) | Out-Null
        $prefix = [int]$parts[1]
        return $prefix -ge 16 -and $prefix -le 29
    } catch {
        return $false
    }
}

#endregion

#region Pre-Deployment Cleanup Functions

function Remove-StaleBudget {
    <#
    .SYNOPSIS
        Removes existing budget to avoid start date conflicts.
    .DESCRIPTION
        Azure Budgets API does not allow updating the start date after creation.
        This function deletes any existing budget so it can be recreated with
        the current month's start date.
    #>
    param([string]$BudgetName = 'budget-smb-lz-monthly')

    Write-Step "CLEANUP" "Checking for existing budget..."
    $budget = az consumption budget show --budget-name $BudgetName 2>$null
    if ($LASTEXITCODE -eq 0 -and $budget) {
        Write-SubStep "Found existing budget - deleting..."
        az consumption budget delete --budget-name $BudgetName 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-SubStep "Budget deleted (will be recreated with current month)"
        } else {
            Write-Warning "Failed to delete budget - deployment may fail"
        }
    } else {
        Write-SubStep "No existing budget found"
    }
}

function Remove-FaultedFirewall {
    <#
    .SYNOPSIS
        Removes firewall resources stuck in failed state.
    .DESCRIPTION
        If a previous deployment failed, the firewall may be in a faulted state
        that prevents redeployment. This function detects and cleans up such resources.
    #>
    param(
        [string]$ResourceGroupName,
        [string]$FirewallName,
        [string]$PolicyName
    )

    # Check if resource group exists
    $rgExists = az group exists --name $ResourceGroupName 2>$null
    if ($rgExists -ne 'true') {
        return
    }

    Write-Step "CLEANUP" "Checking for faulted firewall resources..."

    # Check firewall state
    $fwState = az network firewall show -g $ResourceGroupName -n $FirewallName `
        --query 'provisioningState' -o tsv 2>$null

    if ($fwState -eq 'Failed') {
        Write-SubStep "Faulted firewall detected - cleaning up..."

        # Delete firewall first
        az network firewall delete -g $ResourceGroupName -n $FirewallName 2>$null
        Write-SubStep "Firewall deleted"

        # Wait for firewall deletion to propagate
        Start-Sleep -Seconds 15

        # Delete firewall policy
        az network firewall policy delete -g $ResourceGroupName -n $PolicyName 2>$null
        Write-SubStep "Firewall policy deleted"

        Write-SubStep "Faulted resources cleaned up"
    } elseif ($fwState) {
        Write-SubStep "Firewall state: $fwState (OK)"
    } else {
        Write-SubStep "No existing firewall found"
    }
}

function Remove-FaultedVpnGateway {
    <#
    .SYNOPSIS
        Removes VPN Gateway resources stuck in failed state.
    .DESCRIPTION
        If a previous deployment failed, the VPN Gateway may be in a failed state
        that prevents redeployment. This function detects and cleans up such resources,
        including orphaned public IP addresses.
    #>
    param(
        [string]$ResourceGroupName,
        [string]$GatewayName,
        [string]$PublicIpName
    )

    # Check if resource group exists
    $rgExists = az group exists --name $ResourceGroupName 2>$null
    if ($rgExists -ne 'true') {
        return
    }

    Write-Step "CLEANUP" "Checking for faulted VPN Gateway resources..."

    # Check VPN Gateway state
    $vpnState = az network vnet-gateway show -g $ResourceGroupName -n $GatewayName `
        --query 'provisioningState' -o tsv 2>$null

    if ($vpnState -eq 'Failed') {
        Write-SubStep "Faulted VPN Gateway detected - cleaning up..."

        # Delete VPN Gateway first (long operation)
        az network vnet-gateway delete -g $ResourceGroupName -n $GatewayName --no-wait 2>$null
        Write-SubStep "VPN Gateway deletion initiated"

        # Wait for gateway deletion to start
        Start-Sleep -Seconds 15

        # Delete orphaned public IP if it exists
        $pipExists = az network public-ip show -g $ResourceGroupName -n $PublicIpName 2>$null
        if ($LASTEXITCODE -eq 0 -and $pipExists) {
            az network public-ip delete -g $ResourceGroupName -n $PublicIpName 2>$null
            Write-SubStep "Orphaned public IP deleted: $PublicIpName"
        }

        Write-SubStep "Faulted VPN Gateway resources cleaned up"
    } elseif ($vpnState) {
        Write-SubStep "VPN Gateway state: $vpnState (OK)"
    } else {
        Write-SubStep "No existing VPN Gateway found"
    }
}

function Remove-OrphanedRoleAssignments {
    <#
    .SYNOPSIS
        Removes role assignments for deleted service principals.
    .DESCRIPTION
        When policy assignments with managed identities are deleted, the role
        assignments may remain orphaned. This causes deployment failures when
        trying to recreate them with different principal IDs.
    #>
    param([string]$SubscriptionId)

    Write-Step "CLEANUP" "Checking for orphaned role assignments..."

    # Get backup-related role assignments
    $roleAssignments = az role assignment list --scope "/subscriptions/$SubscriptionId" `
        --query "[?contains(roleDefinitionName, 'Backup') || contains(roleDefinitionName, 'Contributor')].{name:name, principal:principalId}" `
        -o json 2>$null | ConvertFrom-Json

    $deletedCount = 0
    foreach ($ra in $roleAssignments) {
        if (-not $ra.principal) { continue }

        # Check if principal still exists
        $exists = az ad sp show --id $ra.principal 2>$null
        if (-not $exists -and $LASTEXITCODE -ne 0) {
            # Orphaned - delete it
            $raId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleAssignments/$($ra.name)"
            az role assignment delete --ids $raId 2>$null
            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
            }
        }
    }

    if ($deletedCount -gt 0) {
        Write-SubStep "Deleted $deletedCount orphaned role assignments"
    } else {
        Write-SubStep "No orphaned role assignments found"
    }
}

function Invoke-DeploymentWithRetry {
    <#
    .SYNOPSIS
        Executes deployment with exponential backoff retry.
    .DESCRIPTION
        Azure Firewall and VPN Gateway occasionally fail with transient errors,
        especially VNet update conflicts when deploying both simultaneously.
        This function retries the deployment with increasing delays.

        Retryable error patterns:
        - InternalServerError: Generic Azure RM backend failure
        - ServiceUnavailable: Azure service temporarily unavailable
        - TooManyRequests: Throttling
        - GatewayTimeout: Request timeout
        - AnotherOperationInProgress: VNet concurrent modification conflict
        - Conflict: Resource state conflict
    #>
    param(
        [array]$DeployParams,
        [int]$MaxRetries = 3,
        [int]$BaseDelaySeconds = 30
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++
        $delay = $BaseDelaySeconds * [math]::Pow(2, $attempt - 1)  # 30s, 60s, 120s

        if ($attempt -gt 1) {
            Write-Warning "Retry attempt $attempt of $MaxRetries (waiting $delay seconds)..."
            Start-Sleep -Seconds $delay
        }

        Write-Step "$attempt/$MaxRetries" "Deploying to Azure..."
        Write-Host ""

        # Run deployment
        $deployOutput = az @DeployParams 2>&1
        $deployText = $deployOutput -join "`n"

        # Check for success
        if ($deployText -match 'provisioningState.*Succeeded' -or $LASTEXITCODE -eq 0) {
            return @{
                Success = $true
                Output  = $deployOutput
                Text    = $deployText
                Attempt = $attempt
            }
        }

        # Check for retryable errors (including VNet conflict patterns)
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
        $isTransient = $deployText -match $patternRegex

        if (-not $isTransient) {
            # Non-retryable error
            return @{
                Success = $false
                Output  = $deployOutput
                Text    = $deployText
                Attempt = $attempt
                Error   = "Deployment failed with non-retryable error"
            }
        }

        $lastError = $deployText
        Write-Warning "Transient error detected (VNet conflict or Azure backend issue)..."
    }

    return @{
        Success = $false
        Output  = $null
        Text    = $lastError
        Attempt = $attempt
        Error   = "Deployment failed after $MaxRetries attempts"
    }
}

#endregion

#region Main Script

$ErrorActionPreference = 'Stop'
$scriptPath = $PSScriptRoot
$templateFile = Join-Path $scriptPath 'main.bicep'

Write-Banner

# Get Azure account info early (needed for owner detection)
Write-Host ""
Write-Host "  Checking Azure authentication..." -ForegroundColor Gray
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    $azureUser = az ad signed-in-user show --query "mail" -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($azureUser)) {
        $azureUser = az ad signed-in-user show --query "userPrincipalName" -o tsv 2>$null
    }
    Write-Host "  ✓ Logged in as: $azureUser" -ForegroundColor Green
    Write-Host "  ✓ Subscription: $($account.name)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Not authenticated. Run: az login" -ForegroundColor Red
    exit 1
}

# Set default owner from Azure login if not provided
if ([string]::IsNullOrWhiteSpace($Owner)) {
    $Owner = $azureUser
}

# Interactive configuration mode
if (-not $NonInteractive) {
    $scenarioDesc = Get-ScenarioDescription $Scenario
    Write-Host ""
    Write-Host "┌─────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│  DEPLOYMENT CONFIGURATION                                           │" -ForegroundColor Cyan
    Write-Host "├─────────────────────────────────────────────────────────────────────┤" -ForegroundColor Cyan
    Write-Host "│                                                                     │" -ForegroundColor Cyan
    Write-Host ("│  Scenario:    {0}│" -f $scenarioDesc.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Owner:       {0}│" -f $Owner.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Region:      {0}│" -f $Location.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Environment: {0}│" -f $Environment.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Hub VNet:    {0}│" -f $HubVnetAddressSpace.PadRight(53)) -ForegroundColor Cyan
    Write-Host ("│  Spoke VNet:  {0}│" -f $SpokeVnetAddressSpace.PadRight(53)) -ForegroundColor Cyan
    if ($Scenario -in @('vpn', 'full') -and -not [string]::IsNullOrWhiteSpace($OnPremisesAddressSpace)) {
        Write-Host ("│  On-Prem:     {0}│" -f $OnPremisesAddressSpace.PadRight(53)) -ForegroundColor Cyan
    }
    Write-Host ("│  Budget:      `${0}/month{1}│" -f $BudgetAmount, "".PadRight(43 - $BudgetAmount.ToString().Length)) -ForegroundColor Cyan
    Write-Host "│                                                                     │" -ForegroundColor Cyan
    Write-Host "└─────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""

    $acceptDefaults = Read-YesNo "  Accept these defaults?" $true

    if (-not $acceptDefaults) {
        Write-Host ""
        Write-Host "  ─── Configure Deployment ───" -ForegroundColor Yellow
        Write-Host ""

        # Owner
        $Owner = Read-HostWithDefault "  Owner email" $Owner

        # Region
        Write-Host "  Available regions: swedencentral, germanywestcentral" -ForegroundColor Gray
        $Location = Read-HostWithDefault "  Region" $Location
        while ($Location -notin @('swedencentral', 'germanywestcentral')) {
            Write-Host "  Invalid region. Choose: swedencentral or germanywestcentral" -ForegroundColor Red
            $Location = Read-HostWithDefault "  Region" 'swedencentral'
        }

        # Environment
        Write-Host "  Available environments: dev, staging, prod" -ForegroundColor Gray
        $Environment = Read-HostWithDefault "  Environment" $Environment
        while ($Environment -notin @('dev', 'staging', 'prod')) {
            Write-Host "  Invalid environment. Choose: dev, staging, or prod" -ForegroundColor Red
            $Environment = Read-HostWithDefault "  Environment" 'prod'
        }

        # IP Address Spaces
        Write-Host ""
        Write-Host "  ─── Network Configuration ───" -ForegroundColor Yellow
        Write-Host ""
        
        # Hub VNet CIDR with validation
        do {
            $HubVnetAddressSpace = Read-HostWithDefault "  Hub VNet CIDR" $HubVnetAddressSpace
            if (-not (Test-ValidCidr $HubVnetAddressSpace)) {
                Write-Host "  Invalid CIDR format. Use format: x.x.x.x/prefix (prefix 16-29)" -ForegroundColor Red
            }
        } while (-not (Test-ValidCidr $HubVnetAddressSpace))
        
        # Spoke VNet CIDR with validation and overlap check
        do {
            $SpokeVnetAddressSpace = Read-HostWithDefault "  Spoke VNet CIDR" $SpokeVnetAddressSpace
            if (-not (Test-ValidCidr $SpokeVnetAddressSpace)) {
                Write-Host "  Invalid CIDR format. Use format: x.x.x.x/prefix (prefix 16-29)" -ForegroundColor Red
                continue
            }
            if (Test-CidrOverlap $HubVnetAddressSpace $SpokeVnetAddressSpace) {
                Write-Host "  ✗ Spoke CIDR overlaps with Hub CIDR. Choose non-overlapping ranges." -ForegroundColor Red
                $SpokeVnetAddressSpace = ""
            }
        } while (-not (Test-ValidCidr $SpokeVnetAddressSpace) -or (Test-CidrOverlap $HubVnetAddressSpace $SpokeVnetAddressSpace))

        # Optional services - Scenario selection
        Write-Host ""
        Write-Host "  ─── Deployment Scenario ───" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Available scenarios:" -ForegroundColor Gray
        Write-Host "    baseline   - NAT Gateway only (~`$48/mo) - cloud-native" -ForegroundColor Gray
        Write-Host "    firewall   - Azure Firewall + UDR (~`$336/mo) - egress filtering" -ForegroundColor Gray
        Write-Host "    vpn        - VPN Gateway (~`$187/mo) - hybrid connectivity" -ForegroundColor Gray
        Write-Host "    full       - Firewall + VPN (~`$476/mo) - complete security" -ForegroundColor Gray
        Write-Host ""
        $Scenario = Read-HostWithDefault "  Scenario" $Scenario
        while ($Scenario -notin @('baseline', 'firewall', 'vpn', 'full')) {
            Write-Host "  Invalid scenario. Choose: baseline, firewall, vpn, or full" -ForegroundColor Red
            $Scenario = Read-HostWithDefault "  Scenario" 'baseline'
        }

        if ($Scenario -in @('vpn', 'full')) {
            # Prompt for on-premises CIDR when VPN is selected
            Write-Host ""
            Write-Host "  On-premises network CIDR is required for VPN routing." -ForegroundColor Gray
            Write-Host "  This configures firewall rules and route tables for hybrid connectivity." -ForegroundColor Gray
            do {
                $OnPremisesAddressSpace = Read-HostWithDefault "  On-premises CIDR (e.g., 192.168.0.0/16)" $OnPremisesAddressSpace
                if (-not [string]::IsNullOrWhiteSpace($OnPremisesAddressSpace) -and -not (Test-ValidCidr $OnPremisesAddressSpace)) {
                    Write-Host "  Invalid CIDR format. Use format: x.x.x.x/prefix (prefix 8-29)" -ForegroundColor Red
                    $OnPremisesAddressSpace = ''
                }
                # Check for overlap with hub and spoke
                if (-not [string]::IsNullOrWhiteSpace($OnPremisesAddressSpace)) {
                    if (Test-CidrOverlap $HubVnetAddressSpace $OnPremisesAddressSpace) {
                        Write-Host "  ✗ On-premises CIDR overlaps with Hub CIDR." -ForegroundColor Red
                        $OnPremisesAddressSpace = ''
                    } elseif (Test-CidrOverlap $SpokeVnetAddressSpace $OnPremisesAddressSpace) {
                        Write-Host "  ✗ On-premises CIDR overlaps with Spoke CIDR." -ForegroundColor Red
                        $OnPremisesAddressSpace = ''
                    }
                }
            } while ([string]::IsNullOrWhiteSpace($OnPremisesAddressSpace))
        }

        # Budget and alerts
        Write-Host ""
        Write-Host "  ─── Cost Controls ───" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Budget alerts will be sent to: $Owner" -ForegroundColor Gray
        $budgetInput = Read-HostWithDefault "  Monthly budget (USD)" $BudgetAmount.ToString()
        $BudgetAmount = [int]$budgetInput

        Write-Host ""
    }
}

# Validate CIDR ranges don't overlap (for non-interactive mode)
if (Test-CidrOverlap $HubVnetAddressSpace $SpokeVnetAddressSpace) {
    Write-Host "  ✗ Hub and Spoke CIDR ranges overlap. Choose non-overlapping ranges." -ForegroundColor Red
    exit 1
}

# Validate owner is set
if ([string]::IsNullOrWhiteSpace($Owner)) {
    Write-Host "  ✗ Owner is required. Provide via -Owner parameter or Azure login." -ForegroundColor Red
    exit 1
}

Write-Section "DEPLOYMENT CONFIGURATION"

$scenarioDesc = Get-ScenarioDescription $Scenario
Write-Info "Scenario" "$Scenario ($scenarioDesc)"
Write-Info "Environment" $Environment
Write-Info "Owner" $Owner
Write-Info "Location" $Location
Write-Info "Hub VNet" $HubVnetAddressSpace
Write-Info "Spoke VNet" $SpokeVnetAddressSpace
if ($Scenario -in @('vpn', 'full') -and -not [string]::IsNullOrWhiteSpace($OnPremisesAddressSpace)) {
    Write-Info "On-Prem CIDR" $OnPremisesAddressSpace
}
Write-Info "Log Cap" "$LogAnalyticsDailyCapGb GB/day"
Write-Info "Budget" "`$$BudgetAmount/month"

Write-Section "PRE-FLIGHT CHECKS"

# Check Azure CLI
Write-Step "1/6" "Checking Azure CLI..."
try {
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    Write-SubStep "Azure CLI: $($azVersion.'azure-cli')"
} catch {
    Write-Error "Azure CLI not found. Install from https://aka.ms/installazurecli"
    exit 1
}

# Check Bicep CLI
Write-Step "2/6" "Checking Bicep CLI..."
try {
    $bicepVersion = bicep --version 2>&1
    Write-SubStep "Bicep: $bicepVersion"
} catch {
    Write-Error "Bicep CLI not found. Run: az bicep install"
    exit 1
}

# Azure authentication already verified earlier
Write-Step "3/6" "Azure authentication..."
Write-SubStep "Subscription: $($account.name)"
Write-SubStep "Tenant: $($account.tenantId)"

# Check resource providers
Write-Step "4/6" "Checking resource providers..."
$requiredProviders = @(
    'Microsoft.Network',
    'Microsoft.Compute',
    'Microsoft.Storage',
    'Microsoft.OperationalInsights',
    'Microsoft.RecoveryServices',
    'Microsoft.Migrate',
    'Microsoft.Authorization',
    'Microsoft.Resources'
)
$allProvidersRegistered = $true
$unregisteredProviders = @()
foreach ($provider in $requiredProviders) {
    try {
        $state = (az provider show -n $provider --query "registrationState" -o tsv 2>$null)
        if ($LASTEXITCODE -ne 0 -or $state -ne 'Registered') {
            $unregisteredProviders += $provider
            $allProvidersRegistered = $false
        }
    } catch {
        $unregisteredProviders += $provider
        $allProvidersRegistered = $false
    }
}
if ($allProvidersRegistered) {
    Write-SubStep "All $($requiredProviders.Count) resource providers registered"
} else {
    foreach ($p in $unregisteredProviders) {
        Write-Warning "$p not registered"
    }
    Write-Error "Register missing providers with: az provider register -n <provider>"
    exit 1
}

# Check for existing resource groups
Write-Step "5/6" "Checking for existing resource groups..."
$regionAbbrev = @{ 'swedencentral' = 'swc'; 'germanywestcentral' = 'gwc' }[$Location]
$targetRgs = @(
    "rg-hub-slz-$regionAbbrev",
    "rg-spoke-$Environment-$regionAbbrev",
    "rg-monitor-slz-$regionAbbrev",
    "rg-backup-slz-$regionAbbrev",
    "rg-migrate-slz-$regionAbbrev"
)
$existingRgs = az group list --query "[].name" -o tsv 2>$null
$conflictingRgs = $targetRgs | Where-Object { $_ -in $existingRgs }
if ($conflictingRgs.Count -gt 0) {
    Write-Warning "Existing resource groups found: $($conflictingRgs -join ', ')"
    Write-SubStep "Deployment will update existing resources"
} else {
    Write-SubStep "No conflicting resource groups (clean deployment)"
}

# Check for existing policy assignments
$subId = $account.id
$existingPolicies = az policy assignment list --scope "/subscriptions/$subId" `
    --query "[?starts_with(name, 'smb-lz')].name" -o tsv 2>$null
if ($existingPolicies) {
    $policyCount = ($existingPolicies -split "`n").Count
    Write-Warning "$policyCount existing smb-lz-* policy assignments found"
    Write-SubStep "Deployment will update existing policies"
} else {
    Write-SubStep "No conflicting policy assignments"
}

# Validate template
Write-Step "6/6" "Validating Bicep templates..."
try {
    $buildOutput = bicep build $templateFile --stdout 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Bicep build failed"
        Write-Host $buildOutput -ForegroundColor Red
        exit 1
    }
    Write-SubStep "Template validation passed"

    $lintOutput = bicep lint $templateFile 2>&1
    if ($lintOutput -match "Warning") {
        Write-Warning "Lint warnings found (review recommended)"
    } else {
        Write-SubStep "Lint check passed"
    }
} catch {
    Write-Error "Template validation failed: $_"
    exit 1
}

Write-Success "All pre-flight checks passed"

# Pre-deployment cleanup (always for budget, conditional for firewall/vpn)
Write-Section "PRE-DEPLOYMENT CLEANUP"

# Always clean up budget (Azure API limitation - cannot update start date)
Remove-StaleBudget

# Clean up faulted firewall resources if deploying firewall scenarios
if ($Scenario -in @('firewall', 'full')) {
    $hubRg = "rg-hub-slz-$regionAbbrev"
    Remove-FaultedFirewall -ResourceGroupName $hubRg `
        -FirewallName "fw-hub-slz-$regionAbbrev" `
        -PolicyName "fwpol-hub-slz-$regionAbbrev"
}

# Clean up faulted VPN Gateway resources if deploying vpn scenarios
if ($Scenario -in @('vpn', 'full')) {
    $hubRg = "rg-hub-slz-$regionAbbrev"
    Remove-FaultedVpnGateway -ResourceGroupName $hubRg `
        -GatewayName "vpng-hub-slz-$regionAbbrev" `
        -PublicIpName "pip-vpn-slz-$regionAbbrev"
}

# Clean up orphaned role assignments (from deleted policy managed identities)
Remove-OrphanedRoleAssignments -SubscriptionId $subId

# If -Force specified, do additional cleanup
if ($Force) {
    Write-Step "FORCE" "Force mode enabled - additional cleanup..."

    # Delete backup policy assignment to avoid role assignment conflicts
    $backupPolicy = az policy assignment show --name 'smb-lz-backup-02' `
        --scope "/subscriptions/$subId" 2>$null
    if ($LASTEXITCODE -eq 0 -and $backupPolicy) {
        az policy assignment delete --name 'smb-lz-backup-02' `
            --scope "/subscriptions/$subId" 2>$null
        Write-SubStep "Deleted backup policy assignment (will be recreated)"
    }
}

Write-Success "Pre-deployment cleanup complete"

Write-Section "DEPLOYMENT PREVIEW (WHAT-IF)"

$deploymentName = "smb-lz-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$whatIfParams = @(
    'deployment', 'sub', 'what-if',
    '--location', $Location,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters', "scenario=$Scenario",
    '--parameters', "environment=$Environment",
    '--parameters', "owner=$Owner",
    '--parameters', "location=$Location",
    '--parameters', "hubVnetAddressSpace=$HubVnetAddressSpace",
    '--parameters', "spokeVnetAddressSpace=$SpokeVnetAddressSpace",
    '--parameters', "onPremisesAddressSpace=$OnPremisesAddressSpace",
    '--parameters', "logAnalyticsDailyCapGb=$LogAnalyticsDailyCapGb",
    '--parameters', "budgetAmount=$BudgetAmount"
)

Write-Step "1/2" "Running what-if analysis..."
Write-Host ""

# Run what-if and capture output
$whatIfOutput = az @whatIfParams 2>&1
$whatIfText = $whatIfOutput -join "`n"

# Display full what-if output only if -Verbose is specified
if ($VerbosePreference -eq 'Continue') {
    Write-Host $whatIfText -ForegroundColor Gray
} else {
    # Show condensed output - just scopes and resource types being created
    Write-Host "  Analyzing changes..." -ForegroundColor Gray
}

# Parse resource counts from the summary line "Resource changes: X to create."
$createCount = 0
$modifyCount = 0
$deleteCount = 0
$noChangeCount = 0

if ($whatIfText -match 'Resource changes:\s*(\d+)\s*to create') {
    $createCount = [int]$Matches[1]
}
if ($whatIfText -match '(\d+)\s*to modify') {
    $modifyCount = [int]$Matches[1]
}
if ($whatIfText -match '(\d+)\s*to delete') {
    $deleteCount = [int]$Matches[1]
}
if ($whatIfText -match '(\d+)\s*no change') {
    $noChangeCount = [int]$Matches[1]
}

Write-Host ""
Write-Host "┌─────────────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "│  CHANGE SUMMARY                         │" -ForegroundColor DarkGray
Write-Host "│  + Create: $($createCount.ToString().PadRight(3)) resources               │" -ForegroundColor Green
Write-Host "│  ~ Modify: $($modifyCount.ToString().PadRight(3)) resources               │" -ForegroundColor Yellow
Write-Host "│  - Delete: $($deleteCount.ToString().PadRight(3)) resources               │" -ForegroundColor Red
Write-Host "│  = NoChange: $($noChangeCount.ToString().PadRight(3)) resources            │" -ForegroundColor Gray
Write-Host "└─────────────────────────────────────────┘" -ForegroundColor DarkGray
Write-Host ""

# Confirmation
if ($WhatIfPreference) {
    Write-Warning "WhatIf mode - no changes will be made"
    exit 0
}

Write-Step "2/2" "Awaiting confirmation..."
Write-Host ""

# Show estimated deployment time based on scenario
$estimatedTime = switch ($Scenario) {
    'baseline'   { "5-10 minutes" }
    'firewall'   { "10-15 minutes (Firewall provisioning)" }
    'vpn'        { "30-45 minutes (VPN Gateway provisioning)" }
    'full'       { "40-55 minutes (Firewall + VPN Gateway sequentially)" }
}
Write-Host "  ⏱  Estimated deployment time: $estimatedTime" -ForegroundColor Cyan
if ($Scenario -eq 'full') {
    Write-Host "      Note: VPN Gateway waits for Firewall to complete (serialized)" -ForegroundColor Gray
}
Write-Host ""

$confirmation = Read-Host "  Deploy $createCount resources to Azure? (y/yes to confirm)"

if ($confirmation -notmatch '^[Yy](es)?$') {
    Write-Warning "Deployment cancelled by user"
    exit 0
}

Write-Section "DEPLOYING INFRASTRUCTURE"

$deployParams = @(
    'deployment', 'sub', 'create',
    '--location', $Location,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters', "scenario=$Scenario",
    '--parameters', "environment=$Environment",
    '--parameters', "owner=$Owner",
    '--parameters', "location=$Location",
    '--parameters', "hubVnetAddressSpace=$HubVnetAddressSpace",
    '--parameters', "spokeVnetAddressSpace=$SpokeVnetAddressSpace",
    '--parameters', "onPremisesAddressSpace=$OnPremisesAddressSpace",
    '--parameters', "logAnalyticsDailyCapGb=$LogAnalyticsDailyCapGb",
    '--parameters', "budgetAmount=$BudgetAmount"
)

$startTime = Get-Date

# Run deployment with retry logic for transient failures
$deployResult = Invoke-DeploymentWithRetry -DeployParams $deployParams `
    -MaxRetries $MaxRetries -BaseDelaySeconds 30

$duration = (Get-Date) - $startTime

if (-not $deployResult.Success) {
    Write-Error $deployResult.Error
    if ($deployResult.Text) {
        Write-Host $deployResult.Text -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  To retry with cleanup: .\deploy.ps1 -Force -Scenario $Scenario" -ForegroundColor Yellow
    exit 1
}

$deployOutput = $deployResult.Output
$deployText = $deployResult.Text

# Try to parse JSON from output
try {
    $jsonStart = $deployOutput | Where-Object { $_ -match '^\s*\{' } | Select-Object -First 1
    if ($jsonStart) {
        $jsonIndex = [array]::IndexOf($deployOutput, $jsonStart)
        $jsonContent = ($deployOutput[$jsonIndex..($deployOutput.Count - 1)]) -join "`n"
        $parsedResult = $jsonContent | ConvertFrom-Json
    } else {
        # Deployment succeeded but no JSON output
        $parsedResult = $null
    }
} catch {
    $parsedResult = $null
}

if ($parsedResult -and $parsedResult.properties.provisioningState -eq 'Succeeded') {
    Write-Host ""
    Write-Success "DEPLOYMENT SUCCESSFUL"
    Write-Host ""
    if ($deployResult.Attempt -gt 1) {
        Write-Info "Retries" "$($deployResult.Attempt - 1) retry(s) needed"
    }
    Write-Info "Duration" "$([math]::Round($duration.TotalMinutes, 1)) minutes"
    Write-Info "Deployment" $deploymentName

    Write-Section "DEPLOYED RESOURCES"

    $outputs = $parsedResult.properties.outputs

    Write-Info "Hub VNet" $outputs.hubVnetId.value.Split('/')[-1]
    Write-Info "Spoke VNet" $outputs.spokeVnetId.value.Split('/')[-1]
    if ($outputs.natGatewayPublicIp.value) {
        Write-Info "NAT Gateway IP" $outputs.natGatewayPublicIp.value
    }
    Write-Info "Log Analytics" $outputs.logAnalyticsWorkspaceId.value.Split('/')[-1]
    Write-Info "Recovery Vault" $outputs.recoveryServicesVaultId.value.Split('/')[-1]
    Write-Info "Migrate Project" $outputs.migrateProjectId.value.Split('/')[-1]

    # Show scenario-specific resources
    if ($Scenario -in @('firewall', 'full')) {
        Write-Info "Firewall IP" $outputs.firewallPrivateIp.value
    }
    if ($Scenario -in @('vpn', 'full')) {
        Write-Info "VPN Gateway IP" $outputs.vpnGatewayPublicIp.value
    }

    Write-Section "NEXT STEPS"

    Write-Host "  1. Configure VM backup policies in Recovery Services Vault" -ForegroundColor White
    Write-Host "  2. Set up Azure Migrate appliance for VMware discovery" -ForegroundColor White
    Write-Host "  3. Review budget alerts: Cost Management → Budgets" -ForegroundColor White
    Write-Host ""
} elseif ($parsedResult) {
    Write-Error "Deployment failed: $($parsedResult.properties.provisioningState)"
    if ($parsedResult.properties.error) {
        Write-Host $parsedResult.properties.error -ForegroundColor Red
    }
    exit 1
} else {
    # Check if deployment succeeded without JSON output
    if ($deployText -match 'provisioningState.*Succeeded') {
        Write-Success "DEPLOYMENT SUCCESSFUL"
        if ($deployResult.Attempt -gt 1) {
            Write-Info "Retries" "$($deployResult.Attempt - 1) retry(s) needed"
        }
        Write-Info "Duration" "$([math]::Round($duration.TotalMinutes, 1)) minutes"
        Write-Info "Deployment" $deploymentName
        Write-Host ""
        Write-Host "  Check the Azure Portal for deployed resources." -ForegroundColor White
    } else {
        Write-Error "Deployment status unknown. Check Azure Portal."
        exit 1
    }
}

#endregion
