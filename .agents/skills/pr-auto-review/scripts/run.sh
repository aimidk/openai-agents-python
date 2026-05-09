#!/usr/bin/env bash
# PR Auto-Review Skill Script
# Automatically reviews pull requests using OpenAI agents to check code quality,
# consistency, test coverage, and adherence to project standards.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"

# Required environment variables
REQUIRED_VARS=("OPENAI_API_KEY")

# Optional configuration with defaults
MODEL="${REVIEW_MODEL:-gpt-4o}"
MAX_FILES="${MAX_FILES_TO_REVIEW:-50}"
BASE_BRANCH="${BASE_BRANCH:-main}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
PR_NUMBER="${PR_NUMBER:-}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-markdown}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[pr-auto-review] $*"; }
err()  { echo "[pr-auto-review] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

check_required_vars() {
  for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      die "Required environment variable '$var' is not set."
    fi
  done
}

check_dependencies() {
  local missing=()
  for cmd in git python3 curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# Gather PR diff
# ---------------------------------------------------------------------------
get_pr_diff() {
  local diff_output
  if [[ -n "$PR_NUMBER" && -n "$GITHUB_TOKEN" ]]; then
    log "Fetching diff for PR #$PR_NUMBER via GitHub API..."
    local repo
    repo="$(git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')"
    diff_output="$(curl -sSf \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3.diff" \
      "https://api.github.com/repos/${repo}/pulls/${PR_NUMBER}")"
  else
    log "No PR_NUMBER/GITHUB_TOKEN — diffing against '$BASE_BRANCH' locally..."
    diff_output="$(git diff "${BASE_BRANCH}...HEAD" -- . \
      ':(exclude)*.lock' ':(exclude)*.sum' ':(exclude)node_modules/' 2>/dev/null || true)"
  fi

  if [[ -z "$diff_output" ]]; then
    log "No diff found. Nothing to review."
    exit 0
  fi

  echo "$diff_output"
}

# ---------------------------------------------------------------------------
# Build review prompt
# ---------------------------------------------------------------------------
build_review_prompt() {
  local diff="$1"
  cat <<PROMPT
You are an expert code reviewer for the openai-agents-python project.
Review the following git diff and provide structured feedback.

Focus on:
1. Correctness and potential bugs
2. Consistency with existing code style and patterns
3. Test coverage (are new features tested?)
4. Documentation completeness
5. Security concerns
6. Performance implications
7. Breaking changes

Format your response as ${OUTPUT_FORMAT}.
Be concise but thorough. Group findings by severity: CRITICAL, WARNING, SUGGESTION.

--- DIFF START ---
${diff:0:40000}
--- DIFF END ---
PROMPT
}

# ---------------------------------------------------------------------------
# Run review via OpenAI API
# ---------------------------------------------------------------------------
run_review() {
  local prompt="$1"
  local payload
  payload="$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "$prompt" \
    '{ model: $model, messages: [{ role: "user", content: $prompt }], temperature: 0.2 }')"

  log "Sending diff to OpenAI model '$MODEL' for review..."
  local response
  response="$(curl -sSf https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")"

  echo "$response" | jq -r '.choices[0].message.content // "No review content returned."'
}

# ---------------------------------------------------------------------------
# Post review comment to GitHub PR
# ---------------------------------------------------------------------------
post_github_comment() {
  local review_text="$1"
  if [[ -z "$PR_NUMBER" || -z "$GITHUB_TOKEN" ]]; then
    log "Skipping GitHub comment (PR_NUMBER or GITHUB_TOKEN not set)."
    return
  fi

  local repo
  repo="$(git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')"
  local body
  body="$(jq -n --arg body "## 🤖 Automated PR Review\n\n${review_text}" '{body: $body}')"

  log "Posting review comment to PR #$PR_NUMBER..."
  curl -sSf -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${repo}/issues/${PR_NUMBER}/comments" \
    -d "$body" > /dev/null
  log "Comment posted successfully."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  log "Starting PR auto-review skill..."
  check_required_vars
  check_dependencies

  local diff
  diff="$(get_pr_diff)"

  local prompt
  prompt="$(build_review_prompt "$diff")"

  local review
  review="$(run_review "$prompt")"

  echo ""
  echo "=============================="
  echo "  PR REVIEW RESULTS"
  echo "=============================="
  echo "$review"
  echo "=============================="
  echo ""

  post_github_comment "$review"
  log "PR auto-review complete."
}

main "$@"
