#!/usr/bin/env bash
# Issue Triage Skill - Automatically analyzes and triages GitHub issues
# Adds labels, assigns priority, and generates initial response suggestions

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

REQUIRED_ENV_VARS=("GITHUB_TOKEN" "GITHUB_REPOSITORY" "ISSUE_NUMBER")

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[issue-triage] $*"; }
error() { echo "[issue-triage] ERROR: $*" >&2; }

check_dependencies() {
  local missing=()
  for cmd in gh jq curl; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required tools: ${missing[*]}"
    exit 1
  fi
}

check_env_vars() {
  local missing=()
  for var in "${REQUIRED_ENV_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required environment variables: ${missing[*]}"
    exit 1
  fi
}

# ─── Issue Fetching ───────────────────────────────────────────────────────────
fetch_issue() {
  log "Fetching issue #${ISSUE_NUMBER} from ${GITHUB_REPOSITORY}..."
  gh api \
    -H "Accept: application/vnd.github+json" \
    "/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}"
}

fetch_existing_labels() {
  log "Fetching existing repository labels..."
  gh api \
    -H "Accept: application/vnd.github+json" \
    "/repos/${GITHUB_REPOSITORY}/labels" \
    --paginate | jq -r '.[].name'
}

# ─── Label Classification ─────────────────────────────────────────────────────
classify_issue() {
  local title="$1"
  local body="$2"
  local labels=()

  local combined
  combined=$(echo "${title} ${body}" | tr '[:upper:]' '[:lower:]')

  # Type classification
  if echo "$combined" | grep -qE '\bbug\b|error|exception|crash|fail|broken|not working'; then
    labels+=("bug")
  fi
  if echo "$combined" | grep -qE '\bfeature\b|enhancement|request|add support|would be nice|suggestion'; then
    labels+=("enhancement")
  fi
  if echo "$combined" | grep -qE '\bdoc(s|umentation)?\b|readme|example|guide|tutorial'; then
    labels+=("documentation")
  fi
  if echo "$combined" | grep -qE '\bquestion\b|how to|how do i|\bhelp\b|confused|unclear'; then
    labels+=("question")
  fi

  # Priority classification
  if echo "$combined" | grep -qE 'critical|urgent|blocker|production|outage|security|vulnerability'; then
    labels+=("priority: high")
  elif echo "$combined" | grep -qE 'important|significant|major'; then
    labels+=("priority: medium")
  else
    labels+=("priority: low")
  fi

  # Area classification
  if echo "$combined" | grep -qE 'agent|runner|run loop'; then
    labels+=("area: agents")
  fi
  if echo "$combined" | grep -qE 'tool|function call|tool_call'; then
    labels+=("area: tools")
  fi
  if echo "$combined" | grep -qE 'stream|streaming|chunk'; then
    labels+=("area: streaming")
  fi
  if echo "$combined" | grep -qE 'tracing|trace|span|telemetry'; then
    labels+=("area: tracing")
  fi

  echo "${labels[@]:-}"
}

# ─── Label Application ────────────────────────────────────────────────────────
ensure_label_exists() {
  local label="$1"
  local existing_labels="$2"

  if ! echo "$existing_labels" | grep -qF "$label"; then
    log "Creating label: ${label}"
    gh api \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      "/repos/${GITHUB_REPOSITORY}/labels" \
      -f name="$label" \
      -f color="ededed" 2>/dev/null || true
  fi
}

apply_labels() {
  local labels_json="$1"
  log "Applying labels to issue #${ISSUE_NUMBER}..."
  gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}/labels" \
    --input - <<< "{\"labels\": ${labels_json}}"
}

# ─── Comment Generation ───────────────────────────────────────────────────────
post_triage_comment() {
  local issue_type="$1"
  local priority="$2"

  local comment
  comment=$(cat <<EOF
👋 Thank you for opening this issue! It has been automatically triaged.

**Classification:** ${issue_type}
**Priority:** ${priority}

A maintainer will review this shortly. In the meantime:
- For **bugs**, please ensure you've included steps to reproduce, expected vs actual behavior, and your environment details.
- For **feature requests**, please describe your use case and any alternatives you've considered.
- For **questions**, consider checking the [documentation](https://openai.github.io/openai-agents-python/) first.

_This comment was generated automatically by the issue triage workflow._
EOF
)

  gh issue comment "${ISSUE_NUMBER}" \
    --repo "${GITHUB_REPOSITORY}" \
    --body "$comment"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "Starting issue triage for #${ISSUE_NUMBER}..."

  check_dependencies
  check_env_vars

  local issue_json
  issue_json=$(fetch_issue)

  local title body
  title=$(echo "$issue_json" | jq -r '.title // ""')
  body=$(echo "$issue_json"  | jq -r '.body  // ""')

  log "Issue title: ${title}"

  local existing_labels
  existing_labels=$(fetch_existing_labels)

  # Classify and collect labels
  local raw_labels
  read -ra raw_labels <<< "$(classify_issue "$title" "$body")"

  if [[ ${#raw_labels[@]} -eq 0 ]]; then
    log "No labels determined; applying 'needs-triage'."
    raw_labels=("needs-triage")
  fi

  # Ensure every label exists in the repo
  for lbl in "${raw_labels[@]}"; do
    ensure_label_exists "$lbl" "$existing_labels"
  done

  # Build JSON array
  local labels_json
  labels_json=$(printf '%s\n' "${raw_labels[@]}" | jq -R . | jq -sc .)

  apply_labels "$labels_json"

  # Determine human-readable type and priority for the comment
  local issue_type="General"
  local priority="Low"
  for lbl in "${raw_labels[@]}"; do
    case "$lbl" in
      bug)          issue_type="Bug" ;;
      enhancement)  issue_type="Feature Request" ;;
      documentation) issue_type="Documentation" ;;
      question)     issue_type="Question" ;;
      "priority: high")   priority="High" ;;
      "priority: medium") priority="Medium" ;;
    esac
  done

  post_triage_comment "$issue_type" "$priority"

  log "Triage complete. Labels applied: ${raw_labels[*]}"
}

main "$@"
