# PR Auto-Review Skill - PowerShell Runner
# Performs automated code review on pull requests using OpenAI agents

param(
    [Parameter(Mandatory=$false)]
    [string]$PrNumber = $env:PR_NUMBER,

    [Parameter(Mandatory=$false)]
    [string]$RepoOwner = $env:REPO_OWNER,

    [Parameter(Mandatory=$false)]
    [string]$RepoName = $env:REPO_NAME,

    [Parameter(Mandatory=$false)]
    [string]$GithubToken = $env:GITHUB_TOKEN,

    [Parameter(Mandatory=$false)]
    [string]$OpenAiApiKey = $env:OPENAI_API_KEY,

    [Parameter(Mandatory=$false)]
    [string]$ReviewStyle = "constructive",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Assert-EnvVar {
    param([string]$Name, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Log "Required environment variable '$Name' is not set." "ERROR"
        exit 1
    }
}

function Invoke-GhApi {
    param([string]$Endpoint, [string]$Method = "GET", [hashtable]$Body = $null)
    $headers = @{
        "Authorization" = "Bearer $GithubToken"
        "Accept"        = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $uri = "https://api.github.com$Endpoint"
    if ($Body) {
        $json = $Body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers `
            -Body $json -ContentType "application/json"
    }
    return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers
}

# ── Validation ────────────────────────────────────────────────────────────────

Assert-EnvVar "PR_NUMBER"     $PrNumber
Assert-EnvVar "REPO_OWNER"    $RepoOwner
Assert-EnvVar "REPO_NAME"     $RepoName
Assert-EnvVar "GITHUB_TOKEN"  $GithubToken
Assert-EnvVar "OPENAI_API_KEY" $OpenAiApiKey

Write-Log "Starting PR auto-review for $RepoOwner/$RepoName#$PrNumber"

# ── Fetch PR metadata ─────────────────────────────────────────────────────────

Write-Log "Fetching PR metadata..."
$pr = Invoke-GhApi "/repos/$RepoOwner/$RepoName/pulls/$PrNumber"
$prTitle  = $pr.title
$prBody   = $pr.body
$prAuthor = $pr.user.login
$baseSha  = $pr.base.sha
$headSha  = $pr.head.sha

Write-Log "PR: '$prTitle' by @$prAuthor  ($baseSha -> $headSha)"

# ── Fetch diff ────────────────────────────────────────────────────────────────

Write-Log "Fetching PR diff..."
$diffHeaders = @{
    "Authorization" = "Bearer $GithubToken"
    "Accept"        = "application/vnd.github.v3.diff"
}
$diffUri  = "https://api.github.com/repos/$RepoOwner/$RepoName/pulls/$PrNumber"
$diffText = Invoke-RestMethod -Uri $diffUri -Headers $diffHeaders

$diffLines = ($diffText -split "`n").Count
Write-Log "Diff fetched: $diffLines lines"

if ($diffLines -gt 4000) {
    Write-Log "Diff is large ($diffLines lines); truncating to first 4000 lines for review." "WARN"
    $diffText = ($diffText -split "`n" | Select-Object -First 4000) -join "`n"
}

# ── Build review prompt ───────────────────────────────────────────────────────

$systemPrompt = @"
You are an expert code reviewer for a Python SDK project called openai-agents-python.
Your reviews are $ReviewStyle, specific, and actionable.
Focus on: correctness, security, performance, test coverage, and documentation.
Always reference specific file paths and line numbers when possible.
Format your review in Markdown with clear sections.
"@

$userPrompt = @"
## Pull Request: $prTitle
**Author:** @$prAuthor

### Description
$prBody

### Diff
``````diff
$diffText
``````

Please provide a thorough code review covering:
1. Summary of changes
2. Potential bugs or correctness issues
3. Security concerns
4. Performance considerations
5. Code style and best practices
6. Test coverage gaps
7. Documentation completeness
8. Overall recommendation (Approve / Request Changes / Comment)
"@

# ── Call OpenAI API ───────────────────────────────────────────────────────────

Write-Log "Calling OpenAI API for review..."

$openAiBody = @{
    model    = "gpt-4o"
    messages = @(
        @{ role = "system"; content = $systemPrompt },
        @{ role = "user";   content = $userPrompt   }
    )
    max_tokens   = 2048
    temperature  = 0.2
}

$openAiHeaders = @{
    "Authorization" = "Bearer $OpenAiApiKey"
    "Content-Type"  = "application/json"
}

$openAiResponse = Invoke-RestMethod \
    -Uri "https://api.openai.com/v1/chat/completions" \
    -Method POST \
    -Headers $openAiHeaders \
    -Body ($openAiBody | ConvertTo-Json -Depth 10)

$reviewText = $openAiResponse.choices[0].message.content
Write-Log "Review generated ($(($reviewText -split "`n").Count) lines)."

# ── Post review comment ───────────────────────────────────────────────────────

$commentBody = @"
<!-- openai-agents-pr-auto-review -->
## 🤖 Automated PR Review

$reviewText

---
*Generated by the [pr-auto-review](.agents/skills/pr-auto-review) skill.*
"@

if ($DryRun) {
    Write-Log "DRY RUN — review comment (not posted):"
    Write-Host $commentBody
} else {
    Write-Log "Posting review comment to PR #$PrNumber..."
    Invoke-GhApi "/repos/$RepoOwner/$RepoName/issues/$PrNumber/comments" \
        -Method POST \
        -Body @{ body = $commentBody } | Out-Null
    Write-Log "Review comment posted successfully."
}

Write-Log "PR auto-review complete."
