#!/usr/bin/env bash
# examples-auto-run/scripts/run.sh
# Automatically discovers and runs all examples in the repository,
# capturing output and reporting pass/fail status.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
EXAMPLES_DIR="${REPO_ROOT}/examples"
LOG_DIR="${REPO_ROOT}/.agents/skills/examples-auto-run/logs"
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-60}
PYTHON=${PYTHON:-python3}
PASSED=0
FAILED=0
SKIPPED=0
FAILED_EXAMPLES=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[examples-auto-run] $*"; }
warn() { echo "[examples-auto-run] WARN: $*" >&2; }
err()  { echo "[examples-auto-run] ERROR: $*" >&2; }

require_command() {
  if ! command -v "$1" &>/dev/null; then
    err "Required command not found: $1"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
require_command "$PYTHON"
require_command timeout

mkdir -p "$LOG_DIR"

if [[ ! -d "$EXAMPLES_DIR" ]]; then
  err "Examples directory not found: $EXAMPLES_DIR"
  exit 1
fi

# ---------------------------------------------------------------------------
# Discover examples
# Supports:
#   - Single-file examples: examples/**/*.py
#   - Package examples:     examples/**/main.py  (preferred entry point)
# ---------------------------------------------------------------------------
mapfile -t EXAMPLE_FILES < <(
  find "$EXAMPLES_DIR" -type f -name '*.py' \
    | grep -v '__pycache__' \
    | grep -v 'conftest.py' \
    | sort
)

if [[ ${#EXAMPLE_FILES[@]} -eq 0 ]]; then
  warn "No example files found under $EXAMPLES_DIR"
  exit 0
fi

log "Discovered ${#EXAMPLE_FILES[@]} example file(s) under $EXAMPLES_DIR"
log "Timeout per example: ${TIMEOUT_SECONDS}s"
log "Log directory: $LOG_DIR"
echo ""

# ---------------------------------------------------------------------------
# Run each example
# ---------------------------------------------------------------------------
for example in "${EXAMPLE_FILES[@]}"; do
  relative="${example#"${REPO_ROOT}/"}"
  safe_name="$(echo "$relative" | tr '/' '_' | tr ' ' '_')"
  log_file="${LOG_DIR}/${safe_name%.py}.log"

  # Check for explicit skip marker inside the file
  if grep -q 'SKIP_AUTO_RUN' "$example" 2>/dev/null; then
    log "SKIP  $relative  (SKIP_AUTO_RUN marker found)"
    (( SKIPPED++ )) || true
    continue
  fi

  # Check for required environment variables declared in the file
  # Convention: # REQUIRES_ENV: VAR1 VAR2
  required_vars=$(grep -oP '(?<=# REQUIRES_ENV: ).*' "$example" || true)
  missing_vars=""
  for var in $required_vars; do
    if [[ -z "${!var:-}" ]]; then
      missing_vars+="$var "
    fi
  done
  if [[ -n "$missing_vars" ]]; then
    log "SKIP  $relative  (missing env vars: $missing_vars)"
    (( SKIPPED++ )) || true
    continue
  fi

  log "RUN   $relative"

  set +e
  timeout "$TIMEOUT_SECONDS" \
    "$PYTHON" "$example" \
    > "$log_file" 2>&1
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 ]]; then
    log "PASS  $relative"
    (( PASSED++ )) || true
  elif [[ $exit_code -eq 124 ]]; then
    err "TIMEOUT $relative (exceeded ${TIMEOUT_SECONDS}s)"
    echo "--- timeout after ${TIMEOUT_SECONDS}s ---" >> "$log_file"
    FAILED_EXAMPLES+=("$relative (timeout)")
    (( FAILED++ )) || true
  else
    err "FAIL  $relative  (exit code $exit_code)"
    err "      Log: $log_file"
    FAILED_EXAMPLES+=("$relative (exit $exit_code)")
    (( FAILED++ )) || true
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
log "========================================"
log "Results: PASSED=$PASSED  FAILED=$FAILED  SKIPPED=$SKIPPED"
log "========================================"

if [[ ${#FAILED_EXAMPLES[@]} -gt 0 ]]; then
  err "Failed examples:"
  for fe in "${FAILED_EXAMPLES[@]}"; do
    err "  - $fe"
  done
  exit 1
fi

log "All examples passed."
exit 0
