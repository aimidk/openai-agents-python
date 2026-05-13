# Dependency Update Skill - PowerShell Script
# Updates project dependencies and creates a summary of changes

param(
    [string]$WorkingDir = $PSScriptRoot,
    [string]$OutputFile = "dependency-update-report.md",
    [switch]$DryRun = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Navigate to repo root
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
Set-Location $RepoRoot

Write-Host "=== Dependency Update Skill ==="
Write-Host "Working directory: $RepoRoot"
Write-Host "Dry run: $DryRun"

# Check for required tools
function Test-Command {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

if (-not (Test-Command "python")) {
    Write-Error "Python is required but not found in PATH"
    exit 1
}

if (-not (Test-Command "pip")) {
    Write-Error "pip is required but not found in PATH"
    exit 1
}

# Capture current dependency state
Write-Host "`nCapturing current dependency versions..."
$BeforeState = pip list --format=json 2>$null | ConvertFrom-Json

# Check if pyproject.toml exists
$PyProjectPath = Join-Path $RepoRoot "pyproject.toml"
if (-not (Test-Path $PyProjectPath)) {
    Write-Error "pyproject.toml not found at $PyProjectPath"
    exit 1
}

# Run dependency update
if ($DryRun) {
    Write-Host "`n[DRY RUN] Would update dependencies..."
    $UpdateOutput = "Dry run - no changes made"
} else {
    Write-Host "`nUpdating dependencies..."
    try {
        if (Test-Command "uv") {
            Write-Host "Using uv for dependency update"
            $UpdateOutput = uv pip install --upgrade -e ".[dev]" 2>&1
        } else {
            Write-Host "Using pip for dependency update"
            $UpdateOutput = pip install --upgrade -e ".[dev]" 2>&1
        }
        Write-Host "Update complete."
    } catch {
        Write-Warning "Dependency update encountered issues: $_"
        $UpdateOutput = $_.ToString()
    }
}

# Capture new dependency state
Write-Host "`nCapturing updated dependency versions..."
$AfterState = pip list --format=json 2>$null | ConvertFrom-Json

# Compare states to find changes
$BeforeMap = @{}
foreach ($pkg in $BeforeState) {
    $BeforeMap[$pkg.name.ToLower()] = $pkg.version
}

$AfterMap = @{}
foreach ($pkg in $AfterState) {
    $AfterMap[$pkg.name.ToLower()] = $pkg.version
}

$Updated = @()
$Added = @()
$Removed = @()

foreach ($key in $AfterMap.Keys) {
    if ($BeforeMap.ContainsKey($key)) {
        if ($BeforeMap[$key] -ne $AfterMap[$key]) {
            $Updated += [PSCustomObject]@{
                Name    = $key
                Before  = $BeforeMap[$key]
                After   = $AfterMap[$key]
            }
        }
    } else {
        $Added += [PSCustomObject]@{
            Name    = $key
            Version = $AfterMap[$key]
        }
    }
}

foreach ($key in $BeforeMap.Keys) {
    if (-not $AfterMap.ContainsKey($key)) {
        $Removed += [PSCustomObject]@{
            Name    = $key
            Version = $BeforeMap[$key]
        }
    }
}

# Generate report
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Report = @"
# Dependency Update Report

Generated: $Timestamp
Dry Run: $DryRun

## Summary

- **Updated packages**: $($Updated.Count)
- **Added packages**: $($Added.Count)
- **Removed packages**: $($Removed.Count)

"@

if ($Updated.Count -gt 0) {
    $Report += "`n## Updated Packages`n`n| Package | Before | After |`n|---------|--------|-------|`n"
    foreach ($pkg in $Updated | Sort-Object Name) {
        $Report += "| $($pkg.Name) | $($pkg.Before) | $($pkg.After) |`n"
    }
}

if ($Added.Count -gt 0) {
    $Report += "`n## Added Packages`n`n| Package | Version |`n|---------|---------|`n"
    foreach ($pkg in $Added | Sort-Object Name) {
        $Report += "| $($pkg.Name) | $($pkg.Version) |`n"
    }
}

if ($Removed.Count -gt 0) {
    $Report += "`n## Removed Packages`n`n| Package | Version |`n|---------|---------|`n"
    foreach ($pkg in $Removed | Sort-Object Name) {
        $Report += "| $($pkg.Name) | $($pkg.Version) |`n"
    }
}

if ($Updated.Count -eq 0 -and $Added.Count -eq 0 -and $Removed.Count -eq 0) {
    $Report += "`n> All dependencies are already up to date.`n"
}

# Write report
$ReportPath = Join-Path $RepoRoot $OutputFile
$Report | Set-Content -Path $ReportPath -Encoding UTF8
Write-Host "`nReport written to: $ReportPath"

# Print summary to console
Write-Host "`n=== Update Summary ==="
Write-Host "Updated : $($Updated.Count) package(s)"
Write-Host "Added   : $($Added.Count) package(s)"
Write-Host "Removed : $($Removed.Count) package(s)"

if ($Updated.Count -gt 0) {
    Write-Host "`nUpdated packages:"
    foreach ($pkg in $Updated | Sort-Object Name) {
        Write-Host "  $($pkg.Name): $($pkg.Before) -> $($pkg.After)"
    }
}

Write-Host "`nDone."
exit 0
