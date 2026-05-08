#!/usr/bin/env bash
# Dependency Update Skill - run.sh
# Automatically checks for outdated dependencies and creates update PRs

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

PYPROJECT_TOML="${REPO_ROOT}/pyproject.toml"
LOG_PREFIX="[dependency-update]"

# Branch naming
DATE_STAMP="$(date +%Y%m%d)"
BRANCH_NAME="chore/dependency-update-${DATE_STAMP}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARNING: $*" >&2; }
err()  { echo "${LOG_PREFIX} ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || err "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
require_cmd python3
require_cmd pip
require_cmd git

[[ -f "${PYPROJECT_TOML}" ]] || err "pyproject.toml not found at ${PYPROJECT_TOML}"

log "Starting dependency update check in ${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Step 1: Capture outdated packages
# ---------------------------------------------------------------------------
log "Checking for outdated packages..."

cd "${REPO_ROOT}"

# Install pip-tools if not present (used for resolving pinned deps)
if ! command -v pip-compile &>/dev/null; then
  log "Installing pip-tools..."
  pip install --quiet pip-tools
fi

# Collect outdated packages as JSON
OUTDATED_JSON="$(pip list --outdated --format=json 2>/dev/null || echo '[]')"

if [[ "${OUTDATED_JSON}" == "[]" ]]; then
  log "All dependencies are up to date. Nothing to do."
  exit 0
fi

log "Outdated packages found:"
echo "${OUTDATED_JSON}" | python3 -c "
import json, sys
pkgs = json.load(sys.stdin)
for p in pkgs:
    print(f\"  {p['name']}: {p['version']} -> {p['latest_version']}\")
"

# ---------------------------------------------------------------------------
# Step 2: Create / switch to update branch
# ---------------------------------------------------------------------------
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
  log "Branch '${BRANCH_NAME}' already exists — switching to it."
  git checkout "${BRANCH_NAME}"
else
  log "Creating branch '${BRANCH_NAME}' from '${CURRENT_BRANCH}'."
  git checkout -b "${BRANCH_NAME}"
fi

# ---------------------------------------------------------------------------
# Step 3: Upgrade packages
# ---------------------------------------------------------------------------
log "Upgrading outdated packages..."

UPGRADED_PACKAGES=()

while IFS= read -r pkg_name; do
  log "  Upgrading ${pkg_name}..."
  if pip install --quiet --upgrade "${pkg_name}"; then
    UPGRADED_PACKAGES+=("${pkg_name}")
  else
    warn "Failed to upgrade ${pkg_name} — skipping."
  fi
done < <(echo "${OUTDATED_JSON}" | python3 -c "
import json, sys
for p in json.load(sys.stdin):
    print(p['name'])
")

if [[ ${#UPGRADED_PACKAGES[@]} -eq 0 ]]; then
  log "No packages were successfully upgraded."
  git checkout "${CURRENT_BRANCH}"
  git branch -D "${BRANCH_NAME}" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 4: Re-compile requirements if requirements files exist
# ---------------------------------------------------------------------------
for REQ_IN in "${REPO_ROOT}"/*.in "${REPO_ROOT}"/requirements/*.in; do
  [[ -f "${REQ_IN}" ]] || continue
  REQ_OUT="${REQ_IN%.in}.txt"
  log "Re-compiling ${REQ_IN} -> ${REQ_OUT}"
  pip-compile --quiet --upgrade "${REQ_IN}" -o "${REQ_OUT}" || warn "pip-compile failed for ${REQ_IN}"
done

# ---------------------------------------------------------------------------
# Step 5: Run tests to verify nothing is broken
# ---------------------------------------------------------------------------
if command -v pytest &>/dev/null; then
  log "Running test suite to verify upgrades..."
  if ! pytest --tb=short -q 2>&1 | tail -20; then
    warn "Tests failed after upgrade. Aborting and restoring original branch."
    git checkout "${CURRENT_BRANCH}"
    git branch -D "${BRANCH_NAME}" 2>/dev/null || true
    err "Dependency upgrade aborted due to test failures."
  fi
  log "Tests passed."
else
  warn "pytest not found — skipping test verification."
fi

# ---------------------------------------------------------------------------
# Step 6: Commit changes
# ---------------------------------------------------------------------------
if git diff --quiet && git diff --cached --quiet; then
  log "No file changes detected after upgrade — nothing to commit."
else
  COMMIT_MSG="chore: bump dependencies (${DATE_STAMP})

Automatically upgraded the following packages:
$(printf '  - %s\n' "${UPGRADED_PACKAGES[@]}")"

  git add -A
  git commit -m "${COMMIT_MSG}"
  log "Changes committed to branch '${BRANCH_NAME}'."
fi

# ---------------------------------------------------------------------------
# Step 7: Push branch (optional — requires GH_TOKEN or SSH access)
# ---------------------------------------------------------------------------
if [[ "${AUTO_PUSH:-false}" == "true" ]]; then
  log "Pushing branch '${BRANCH_NAME}' to origin..."
  git push --set-upstream origin "${BRANCH_NAME}"
  log "Branch pushed. Open a PR at:"
  log "  https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]//;s/\.git$//')/compare/${BRANCH_NAME}"
else
  log "AUTO_PUSH is not set. To push manually:"
  log "  git push --set-upstream origin ${BRANCH_NAME}"
fi

log "Dependency update complete. Upgraded: ${UPGRADED_PACKAGES[*]:-none}"
