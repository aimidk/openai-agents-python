# Examples Auto-Run Skill - PowerShell Script
# Automatically discovers and runs Python examples in the repository,
# capturing output and reporting success/failure for each example.

param(
    [string]$ExamplesDir = "examples",
    [int]$TimeoutSeconds = 60,
    [switch]$FailFast,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0
$script:Results = @()

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
}

function Write-Result {
    param(
        [string]$Status,
        [string]$ExamplePath,
        [string]$Detail = ""
    )
    switch ($Status) {
        "PASS" { Write-Host "  [PASS] $ExamplePath" -ForegroundColor Green }
        "FAIL" { Write-Host "  [FAIL] $ExamplePath" -ForegroundColor Red }
        "SKIP" { Write-Host "  [SKIP] $ExamplePath" -ForegroundColor Yellow }
    }
    if ($Detail -and $Verbose) {
        Write-Host "         $Detail" -ForegroundColor Gray
    }
}

function Test-RequiresApiKey {
    param([string]$FilePath)
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if ($content -match "OPENAI_API_KEY" -or $content -match "openai\.OpenAI" -or $content -match "AsyncOpenAI") {
        return $true
    }
    return $false
}

function Test-HasSyntaxErrors {
    param([string]$FilePath)
    $result = & python -m py_compile $FilePath 2>&1
    return $LASTEXITCODE -ne 0
}

function Invoke-Example {
    param([string]$FilePath)

    $relativePath = $FilePath.Replace((Get-Location).Path + [System.IO.Path]::DirectorySeparatorChar, "")

    # Skip files that require live API keys unless explicitly set
    if ((Test-RequiresApiKey -FilePath $FilePath) -and -not $env:OPENAI_API_KEY) {
        $script:SkipCount++
        $script:Results += [PSCustomObject]@{ Status = "SKIP"; Path = $relativePath; Reason = "Requires OPENAI_API_KEY" }
        Write-Result -Status "SKIP" -ExamplePath $relativePath -Detail "Requires OPENAI_API_KEY"
        return
    }

    # Check syntax before running
    if (Test-HasSyntaxErrors -FilePath $FilePath) {
        $script:FailCount++
        $script:Results += [PSCustomObject]@{ Status = "FAIL"; Path = $relativePath; Reason = "Syntax error" }
        Write-Result -Status "FAIL" -ExamplePath $relativePath -Detail "Syntax error detected"
        if ($FailFast) { exit 1 }
        return
    }

    try {
        $proc = Start-Process -FilePath "python" -ArgumentList $FilePath `
            -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\example_stdout.txt" `
            -RedirectStandardError "$env:TEMP\example_stderr.txt"

        $completed = $proc.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            $proc.Kill()
            $script:FailCount++
            $script:Results += [PSCustomObject]@{ Status = "FAIL"; Path = $relativePath; Reason = "Timeout after ${TimeoutSeconds}s" }
            Write-Result -Status "FAIL" -ExamplePath $relativePath -Detail "Timed out after ${TimeoutSeconds}s"
            if ($FailFast) { exit 1 }
            return
        }

        if ($proc.ExitCode -eq 0) {
            $script:PassCount++
            $script:Results += [PSCustomObject]@{ Status = "PASS"; Path = $relativePath; Reason = "" }
            Write-Result -Status "PASS" -ExamplePath $relativePath
        } else {
            $stderr = Get-Content "$env:TEMP\example_stderr.txt" -Raw -ErrorAction SilentlyContinue
            $script:FailCount++
            $script:Results += [PSCustomObject]@{ Status = "FAIL"; Path = $relativePath; Reason = $stderr.Trim() }
            Write-Result -Status "FAIL" -ExamplePath $relativePath -Detail ($stderr.Trim() -replace "`n", " ")
            if ($FailFast) { exit 1 }
        }
    } catch {
        $script:FailCount++
        $script:Results += [PSCustomObject]@{ Status = "FAIL"; Path = $relativePath; Reason = $_.Exception.Message }
        Write-Result -Status "FAIL" -ExamplePath $relativePath -Detail $_.Exception.Message
        if ($FailFast) { exit 1 }
    }
}

# --- Main ---
Write-Header "Examples Auto-Run"

if (-not (Test-Path $ExamplesDir)) {
    Write-Host "Examples directory '$ExamplesDir' not found." -ForegroundColor Red
    exit 1
}

$exampleFiles = Get-ChildItem -Path $ExamplesDir -Recurse -Filter "*.py" |
    Where-Object { $_.Name -notmatch "^_" } |
    Sort-Object FullName

Write-Host "Found $($exampleFiles.Count) example file(s) in '$ExamplesDir'`n"

foreach ($file in $exampleFiles) {
    Invoke-Example -FilePath $file.FullName
}

Write-Header "Summary"
Write-Host "  Passed : $script:PassCount" -ForegroundColor Green
Write-Host "  Failed : $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Skipped: $script:SkipCount" -ForegroundColor Yellow
Write-Host ""

if ($script:FailCount -gt 0) {
    Write-Host "Some examples failed. See details above." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All runnable examples passed." -ForegroundColor Green
    exit 0
}
