# Changelog Generator Script (PowerShell)
# Generates a changelog based on git commits since the last tag or release

param(
    [string]$OutputFile = "CHANGELOG.md",
    [string]$RepoPath = ".",
    [string]$FromTag = "",
    [string]$ToRef = "HEAD",
    [switch]$DryRun = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Get-LastTag {
    try {
        $tag = git describe --tags --abbrev=0 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $tag.Trim()
        }
    } catch {
        # No tags found
    }
    return ""
}

function Get-CommitsSince {
    param([string]$Since, [string]$Until)

    $range = if ($Since) { "$Since..$Until" } else { $Until }
    $format = "%H|%s|%an|%ad"
    $commits = git log $range --pretty=format:$format --date=short 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to retrieve commits" "ERROR"
        return @()
    }

    $result = @()
    foreach ($line in $commits) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "\|", 4
        if ($parts.Count -eq 4) {
            $result += [PSCustomObject]@{
                Hash    = $parts[0].Substring(0, [Math]::Min(7, $parts[0].Length))
                Subject = $parts[1]
                Author  = $parts[2]
                Date    = $parts[3]
            }
        }
    }
    return $result
}

function Group-CommitsByType {
    param([array]$Commits)

    $groups = @{
        "feat"     = @()
        "fix"      = @()
        "docs"     = @()
        "chore"    = @()
        "refactor" = @()
        "test"     = @()
        "ci"       = @()
        "other"    = @()
    }

    foreach ($commit in $Commits) {
        $subject = $commit.Subject
        $matched = $false

        foreach ($type in @("feat", "fix", "docs", "chore", "refactor", "test", "ci")) {
            if ($subject -match "^$type(\(.+\))?(!)?:") {
                $groups[$type] += $commit
                $matched = $true
                break
            }
        }

        if (-not $matched) {
            $groups["other"] += $commit
        }
    }

    return $groups
}

function Format-ChangelogSection {
    param([string]$Title, [array]$Commits)

    if ($Commits.Count -eq 0) { return "" }

    $lines = @("### $Title", "")
    foreach ($c in $Commits) {
        $lines += "- $($c.Subject) ([``$($c.Hash)``]) by $($c.Author) on $($c.Date)"
    }
    $lines += ""
    return $lines -join "`n"
}

function Build-Changelog {
    param([hashtable]$Groups, [string]$Version, [string]$Date)

    $header = @(
        "## [$Version] - $Date",
        ""
    ) -join "`n"

    $sectionMap = @(
        @{ Key = "feat";     Title = "Features" },
        @{ Key = "fix";      Title = "Bug Fixes" },
        @{ Key = "docs";     Title = "Documentation" },
        @{ Key = "refactor"; Title = "Refactoring" },
        @{ Key = "test";     Title = "Tests" },
        @{ Key = "ci";       Title = "CI/CD" },
        @{ Key = "chore";    Title = "Chores" },
        @{ Key = "other";    Title = "Other Changes" }
    )

    $body = ""
    foreach ($section in $sectionMap) {
        $body += Format-ChangelogSection -Title $section.Title -Commits $Groups[$section.Key]
    }

    return $header + $body
}

# --- Main ---

Write-Log "Starting changelog generation"
Set-Location $RepoPath

$fromTag = if ($FromTag) { $FromTag } else { Get-LastTag }
if ($fromTag) {
    Write-Log "Generating changelog from tag: $fromTag to $ToRef"
} else {
    Write-Log "No previous tag found. Generating changelog for all commits up to $ToRef"
}

$commits = Get-CommitsSince -Since $fromTag -Until $ToRef
Write-Log "Found $($commits.Count) commit(s)"

if ($commits.Count -eq 0) {
    Write-Log "No commits to include in changelog. Exiting."
    exit 0
}

$groups   = Group-CommitsByType -Commits $commits
$version  = if ($fromTag) { "Unreleased" } else { "0.1.0" }
$date     = Get-Date -Format "yyyy-MM-dd"
$newEntry = Build-Changelog -Groups $groups -Version $version -Date $date

if ($DryRun) {
    Write-Log "[DRY RUN] Changelog entry:"
    Write-Host $newEntry
} else {
    $existingContent = ""
    if (Test-Path $OutputFile) {
        $existingContent = Get-Content $OutputFile -Raw
    }

    $fullContent = "# Changelog`n`nAll notable changes to this project will be documented in this file.`n`n" + $newEntry
    if ($existingContent -match "## \[") {
        # Append after header
        $fullContent = $existingContent -replace "(# Changelog.*?\n\n)", "`$1$newEntry"
    }

    Set-Content -Path $OutputFile -Value $fullContent -Encoding UTF8
    Write-Log "Changelog written to $OutputFile"
}

Write-Log "Changelog generation complete"
