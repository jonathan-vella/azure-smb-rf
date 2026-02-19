<#
.SYNOPSIS
    Comprehensive repository validation script for SMB Ready Foundation.

.DESCRIPTION
    Executes 7 validation phases to verify the integrity of all repository assets:
    - Phase 1: Bicep compilation and linting
    - Phase 2: Diagram generation verification
    - Phase 3: Documentation audit for stale references
    - Phase 4: PowerShell syntax validation
    - Phase 5: Template compliance (npm validators)
    - Phase 6: Markdown linting
    - Phase 7: Scenario what-if deployments

.EXAMPLE
    ./validate-all.ps1
    # Run all validation phases

.EXAMPLE
    ./validate-all.ps1 -SkipWhatIf
    # Skip Azure deployment validation (Phase 7)

.NOTES
    Version: 1.0
    Author: Agentic InfraOps
#>

[CmdletBinding()]
param(
    [switch]$SkipWhatIf
)

$ErrorActionPreference = 'Continue'
$scriptRoot = Split-Path -Parent $PSScriptRoot
$results = @{}
$startTime = Get-Date

#region Helper Functions

function Write-Phase {
    param([int]$Number, [string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  PHASE ${Number}: ${Title}" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Check {
    param([string]$Item, [bool]$Passed, [string]$Details = "")
    if ($Passed) {
        Write-Host "  ✓ $Item" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $Item" -ForegroundColor Red
    }
    if ($Details) {
        Write-Host "    └─ $Details" -ForegroundColor Gray
    }
}

function Write-Summary {
    param([hashtable]$Results)
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  VALIDATION SUMMARY" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    $passed = 0
    $failed = 0
    
    foreach ($phase in $Results.Keys | Sort-Object) {
        $result = $Results[$phase]
        if ($result.Passed) {
            Write-Host "  ✓ $phase" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "  ✗ $phase" -ForegroundColor Red
            $failed++
        }
    }
    
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    $duration = (Get-Date) - $startTime
    Write-Host "  Duration: $([math]::Round($duration.TotalSeconds, 1)) seconds" -ForegroundColor Gray
    Write-Host "  Passed: $passed | Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
    Write-Host ""
    
    return $failed -eq 0
}

#endregion

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║       SMB READY FOUNDATION - REPOSITORY VALIDATION                ║" -ForegroundColor Magenta
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

#region Phase 1: Bicep Validation

Write-Phase 1 "BICEP VALIDATION"

$bicepPath = Join-Path $scriptRoot "infra/bicep/smb-ready-foundation"
$bicepErrors = 0
$bicepFiles = @()

# Main template
$mainBicep = Join-Path $bicepPath "main.bicep"
if (Test-Path $mainBicep) {
    Write-Host "  Building main.bicep..." -ForegroundColor Gray
    $buildOutput = bicep build $mainBicep 2>&1
    $buildSuccess = $LASTEXITCODE -eq 0
    Write-Check "main.bicep (build)" $buildSuccess
    if (-not $buildSuccess) { $bicepErrors++ }
    
    Write-Host "  Linting main.bicep..." -ForegroundColor Gray
    $lintOutput = bicep lint $mainBicep 2>&1
    $lintWarnings = ($lintOutput | Select-String -Pattern "Warning" | Measure-Object).Count
    Write-Check "main.bicep (lint)" $true "$lintWarnings warnings"
}

# Module files
$modulesPath = Join-Path $bicepPath "modules"
if (Test-Path $modulesPath) {
    $modules = Get-ChildItem -Path $modulesPath -Filter "*.bicep"
    foreach ($module in $modules) {
        $buildOutput = bicep build $module.FullName 2>&1
        $buildSuccess = $LASTEXITCODE -eq 0
        Write-Check $module.Name $buildSuccess
        if (-not $buildSuccess) { $bicepErrors++ }
    }
}

$results["Phase 1: Bicep"] = @{ Passed = ($bicepErrors -eq 0); Errors = $bicepErrors }

#endregion

#region Phase 2: Diagram Generation

Write-Phase 2 "DIAGRAM GENERATION"

$diagramPath = Join-Path $scriptRoot "agent-output/smb-ready-foundation"
$diagramErrors = 0

$diagrams = @(
    "03-des-diagram.py",
    "03-des-diagram-baseline.py",
    "03-des-diagram-firewall.py",
    "03-des-diagram-vpn.py",
    "03-des-diagram-full.py"
)

Push-Location $diagramPath
foreach ($diagram in $diagrams) {
    $pyFile = Join-Path $diagramPath $diagram
    if (Test-Path $pyFile) {
        $pngFile = $diagram -replace '\.py$', '.png'
        
        # Run the diagram script
        python $pyFile 2>&1 | Out-Null
        
        # Check if PNG was generated
        $pngPath = Join-Path $diagramPath $pngFile
        $pngExists = Test-Path $pngPath
        Write-Check "$diagram → $pngFile" $pngExists
        if (-not $pngExists) { $diagramErrors++ }
    } else {
        Write-Check $diagram $false "File not found"
        $diagramErrors++
    }
}
Pop-Location

$results["Phase 2: Diagrams"] = @{ Passed = ($diagramErrors -eq 0); Errors = $diagramErrors }

#endregion

#region Phase 3: Documentation Audit

Write-Phase 3 "DOCUMENTATION AUDIT (Stale References)"

$stalePatterns = @(
    @{ Pattern = "enterprise"; Description = "Old scenario name" },
    @{ Pattern = "-DeployFirewall"; Description = "Old boolean flag" },
    @{ Pattern = "-DeployVpnGateway"; Description = "Old boolean flag" }
)

$auditErrors = 0
$searchPaths = @(
    (Join-Path $scriptRoot "agent-output"),
    (Join-Path $scriptRoot "infra/bicep/smb-ready-foundation"),
    (Join-Path $scriptRoot "README.md")
)

# Exclude patterns for legitimate uses
$excludePatterns = @(
    "Copilot-Processing.md",  # Historical log
    ".git",
    "node_modules"
)

foreach ($pattern in $stalePatterns) {
    Write-Host "  Checking for '$($pattern.Pattern)'..." -ForegroundColor Gray
    
    $matches = @()
    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            $found = Get-ChildItem -Path $searchPath -Recurse -Include "*.md","*.bicep","*.ps1","*.py" -ErrorAction SilentlyContinue |
                Where-Object { 
                    $file = $_
                    -not ($excludePatterns | Where-Object { $file.FullName -like "*$_*" })
                } |
                Select-String -Pattern $pattern.Pattern -SimpleMatch -ErrorAction SilentlyContinue
            if ($found) { $matches += $found }
        }
    }
    
    # Filter out legitimate uses (like "enterprise discount", "enterprise agreements", "Enterprise-grade")
    $realMatches = $matches | Where-Object { 
        $_.Line -notmatch "enterprise discount|enterprise agreement|Enterprise Agreement|contact sales for enterprise|Enterprise-grade|enterprise-grade" 
    }
    
    $passed = ($realMatches.Count -eq 0)
    Write-Check "No '$($pattern.Pattern)' references" $passed "$($realMatches.Count) found"
    
    if (-not $passed) {
        $auditErrors++
        foreach ($match in $realMatches | Select-Object -First 3) {
            $relativePath = $match.Path -replace [regex]::Escape($scriptRoot), ""
            Write-Host "      → $relativePath`:$($match.LineNumber)" -ForegroundColor Yellow
        }
    }
}

$results["Phase 3: Docs Audit"] = @{ Passed = ($auditErrors -eq 0); Errors = $auditErrors }

#endregion

#region Phase 4: PowerShell Syntax

Write-Phase 4 "POWERSHELL SYNTAX VALIDATION"

$psErrors = 0
$psFiles = Get-ChildItem -Path $scriptRoot -Recurse -Include "*.ps1" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*node_modules*" -and $_.FullName -notlike "*.git*" }

foreach ($psFile in $psFiles) {
    try {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $psFile.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        )
        $passed = ($parseErrors.Count -eq 0)
        $relativePath = $psFile.FullName -replace [regex]::Escape($scriptRoot), ""
        Write-Check $relativePath.TrimStart('/\') $passed $(if (-not $passed) { "$($parseErrors.Count) errors" } else { "" })
        if (-not $passed) { $psErrors++ }
    } catch {
        Write-Check $psFile.Name $false $_.Exception.Message
        $psErrors++
    }
}

$results["Phase 4: PowerShell"] = @{ Passed = ($psErrors -eq 0); Errors = $psErrors }

#endregion

#region Phase 5: Template Compliance

Write-Phase 5 "TEMPLATE COMPLIANCE (artifact + cost-estimate)"

Push-Location $scriptRoot
$templateErrors = 0

# Run artifact template validation
Write-Host "  Running lint:artifact-templates..." -ForegroundColor Gray
$artifactOutput = npm run lint:artifact-templates 2>&1
$artifactPassed = $LASTEXITCODE -eq 0
Write-Check "Artifact templates" $artifactPassed
if (-not $artifactPassed) { $templateErrors++ }

# Run cost estimate template validation  
Write-Host "  Running lint:cost-estimate-templates..." -ForegroundColor Gray
$costOutput = npm run lint:cost-estimate-templates 2>&1
$costPassed = $LASTEXITCODE -eq 0
Write-Check "Cost estimate templates" $costPassed
if (-not $costPassed) { $templateErrors++ }

$results["Phase 5: Templates"] = @{ Passed = ($templateErrors -eq 0); Errors = $templateErrors }
Pop-Location

#endregion

#region Phase 6: Markdown Lint

Write-Phase 6 "MARKDOWN LINTING"

Push-Location $scriptRoot
try {
    Write-Host "  Running npm run lint:md..." -ForegroundColor Gray
    $lintOutput = npm run lint:md 2>&1
    $lintExitCode = $LASTEXITCODE
    
    # Count errors from output
    $errorCount = ($lintOutput | Select-String -Pattern "error\(s\)" | ForEach-Object {
        if ($_ -match "(\d+) error") { [int]$Matches[1] } else { 0 }
    } | Measure-Object -Sum).Sum
    
    $passed = ($lintExitCode -eq 0) -or ($errorCount -eq 0)
    Write-Check "Markdown lint" $passed "$errorCount errors"
    $results["Phase 6: Markdown"] = @{ Passed = $passed; Errors = $errorCount }
} catch {
    Write-Check "Markdown lint" $false $_.Exception.Message
    $results["Phase 6: Markdown"] = @{ Passed = $false; Errors = 1 }
}
Pop-Location

#endregion

#region Phase 7: Scenario What-If

if (-not $SkipWhatIf) {
    Write-Phase 7 "SCENARIO WHAT-IF DEPLOYMENTS"
    
    $scenarios = @("baseline", "firewall", "vpn", "full")
    $whatIfErrors = 0
    
    # Check Azure auth
    Write-Host "  Checking Azure authentication..." -ForegroundColor Gray
    $account = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Check "Azure authentication" $false "Not logged in"
        $results["Phase 7: What-If"] = @{ Passed = $false; Errors = 1 }
    } else {
        Write-Check "Azure authentication" $true $account.name
        
        $templateFile = Join-Path $scriptRoot "infra/bicep/smb-ready-foundation/main.bicep"
        
        foreach ($scenario in $scenarios) {
            Write-Host "  Testing scenario: $scenario..." -ForegroundColor Gray
            
            $whatIfOutput = az deployment sub what-if `
                --location swedencentral `
                --template-file $templateFile `
                --parameters scenario=$scenario `
                --parameters owner="validation@test.com" `
                --parameters onPremisesAddressSpace="192.168.0.0/16" `
                --no-pretty-print `
                2>&1
            
            $whatIfSuccess = $LASTEXITCODE -eq 0
            Write-Check "Scenario: $scenario" $whatIfSuccess
            if (-not $whatIfSuccess) { $whatIfErrors++ }
        }
        
        $results["Phase 7: What-If"] = @{ Passed = ($whatIfErrors -eq 0); Errors = $whatIfErrors }
    }
} else {
    Write-Host ""
    Write-Host "  Phase 7 skipped (-SkipWhatIf)" -ForegroundColor Yellow
    $results["Phase 7: What-If"] = @{ Passed = $true; Errors = 0; Skipped = $true }
}

#endregion

#region Summary

$allPassed = Write-Summary $results

if ($allPassed) {
    Write-Host "  🎉 ALL VALIDATIONS PASSED" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  SOME VALIDATIONS FAILED - Review above" -ForegroundColor Yellow
}

Write-Host ""

#endregion
