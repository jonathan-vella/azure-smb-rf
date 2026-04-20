<#
.SYNOPSIS
    Shared hook helpers (PowerShell) — dot-sourced by hooks/*.ps1.
#>

function Write-HookStep {
    param([string]$Step, [string]$Message)
    Write-Host "  [$Step] $Message" -ForegroundColor White
}

function Write-HookSub {
    param([string]$Message)
    Write-Host "      - $Message" -ForegroundColor Gray
}

function Test-ValidCidr {
    param([string]$Cidr)
    if ($Cidr -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$') { return $false }
    try {
        $parts = $Cidr -split '/'
        [System.Net.IPAddress]::Parse($parts[0]) | Out-Null
        $prefix = [int]$parts[1]
        return $prefix -ge 16 -and $prefix -le 29
    } catch { return $false }
}

function Test-CidrOverlap {
    param([string]$Cidr1, [string]$Cidr2)
    $parts1 = $Cidr1 -split '/'
    $parts2 = $Cidr2 -split '/'
    $bytes1 = [System.Net.IPAddress]::Parse($parts1[0]).GetAddressBytes(); [Array]::Reverse($bytes1)
    $bytes2 = [System.Net.IPAddress]::Parse($parts2[0]).GetAddressBytes(); [Array]::Reverse($bytes2)
    $int1 = [BitConverter]::ToUInt32($bytes1, 0)
    $int2 = [BitConverter]::ToUInt32($bytes2, 0)
    $smaller = [Math]::Min([int]$parts1[1], [int]$parts2[1])
    $mask = [uint32]::MaxValue -shl (32 - $smaller)
    return ($int1 -band $mask) -eq ($int2 -band $mask)
}

function Resolve-ScenarioFlags {
    param([string]$Scenario = 'baseline')
    $fw = $false; $vpn = $false
    switch ($Scenario) {
        'firewall' { $fw = $true }
        'vpn'      { $vpn = $true }
        'full'     { $fw = $true; $vpn = $true }
        'baseline' { }
        default    { throw "Unknown SCENARIO '$Scenario' (allowed: baseline|firewall|vpn|full)" }
    }
    if ($env:DEPLOY_FIREWALL) { $fw  = [System.Convert]::ToBoolean($env:DEPLOY_FIREWALL) }
    if ($env:DEPLOY_VPN)      { $vpn = [System.Convert]::ToBoolean($env:DEPLOY_VPN) }
    return @{ Firewall = $fw; Vpn = $vpn }
}
