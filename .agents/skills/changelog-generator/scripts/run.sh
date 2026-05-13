#!/usr/bin/env bash
# Changelog Generator Skill
# Automatically generates or updates CHANGELOG.md based on git history
# and conventional commit messages since the last release tag.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}"
REPO_URL="${REPO_URL:-}"
MAX_COMMITS="${MAX_COMMITS:-200}"
UNRELEASED_HEADER="## [Unreleased]"

# Conventional commit type → section heading mapping
declare -A TYPE_HEADINGS=(
  [feat]="### Features"
  [fix]="### Bug Fixes"
  [perf]="### Performance Improvements"
  [refactor]="### Refactoring"
  [docs]="### Documentation"
  [test]="### Tests"
  [chore]="### Chores"
  [ci]="### CI / Build"
  [build]="### CI / Build"
  [revert]="### Reverts"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[changelog-generator] $*"; }
err()  { echo "[changelog-generator] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || err "Required command not found: $1"
}

# Return the most recent git tag, or empty string if none exist.
latest_tag() {
  git describe --tags --abbrev=0 2>/dev/null || true
}

# Emit a markdown link to a commit if REPO_URL is set, otherwise plain hash.
commit_link() {
  local hash="$1"
  local short="${hash:0:7}"
  if [[ -n "$REPO_URL" ]]; then
    echo "([\`${short}\`](${REPO_URL}/commit/${hash}))"
  else
    echo "(\`${short}\`)"
  fi
}

# ---------------------------------------------------------------------------
# Parse commits between $1 (exclusive) and HEAD
# If $1 is empty, parse all commits up to MAX_COMMITS.
# ---------------------------------------------------------------------------
parse_commits() {
  local since_tag="$1"
  local range

  if [[ -n "$since_tag" ]]; then
    range="${since_tag}..HEAD"
  else
    range="HEAD"
  fi

  # Output: <hash> <full subject line>
  git log "$range" --max-count="$MAX_COMMITS" \
    --pretty=format:"%H %s" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Build the [Unreleased] section text
# ---------------------------------------------------------------------------
build_unreleased_section() {
  local since_tag="$1"
  local -A sections
  local breaking_notes=""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local hash subject
    hash="$(echo "$line" | awk '{print $1}')"
    subject="$(echo "$line" | cut -d' ' -f2-)"

    # Detect breaking change marker
    local is_breaking=false
    if echo "$subject" | grep -qE '^[a-z]+!:'; then
      is_breaking=true
    fi

    # Extract type and description
    local type description scope
    if echo "$subject" | grep -qE '^[a-z]+[!(:]'; then
      type="$(echo "$subject" | sed -E 's/^([a-z]+)[!(].*/\1/')"
      description="$(echo "$subject" | sed -E 's/^[^:]+: ?//')"
      scope="$(echo "$subject" | sed -nE 's/^[a-z]+\(([^)]+)\).*/\1/p')"
    else
      type="chore"
      description="$subject"
      scope=""
    fi

    local heading="${TYPE_HEADINGS[$type]:-}"
    [[ -z "$heading" ]] && heading="### Other Changes"

    local entry
    if [[ -n "$scope" ]]; then
      entry="- **${scope}**: ${description} $(commit_link "$hash")"
    else
      entry="- ${description} $(commit_link "$hash")"
    fi

    if $is_breaking; then
      breaking_notes+="- ⚠️  BREAKING: ${description} $(commit_link "$hash")\n"
    fi

    sections["$heading"]+="${entry}\n"
  done < <(parse_commits "$since_tag")

  # Render section
  local output="$UNRELEASED_HEADER\n\n"

  if [[ -n "$breaking_notes" ]]; then
    output+="### ⚠️  Breaking Changes\n\n${breaking_notes}\n"
  fi

  for type_key in feat fix perf refactor docs test chore ci build revert; do
    local heading="${TYPE_HEADINGS[$type_key]:-}"
    [[ -z "${sections[$heading]:-}" ]] && continue
    output+="${heading}\n\n${sections[$heading]}\n"
  done

  # Append any "Other Changes" bucket
  local other="${sections["### Other Changes"]:-}"
  if [[ -n "$other" ]]; then
    output+="### Other Changes\n\n${other}\n"
  fi

  echo -e "$output"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  require_cmd git

  log "Starting changelog generation…"

  local tag
  tag="$(latest_tag)"

  if [[ -n "$tag" ]]; then
    log "Latest tag: $tag — collecting commits since then."
  else
    log "No tags found — collecting all commits (max ${MAX_COMMITS})."
  fi

  local unreleased
  unreleased="$(build_unreleased_section "$tag")"

  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    log "Creating new ${CHANGELOG_FILE}."
    {
      echo "# Changelog"
      echo ""
      echo "All notable changes to this project will be documented in this file."
      echo "Format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)."
      echo ""
      echo "$unreleased"
    } > "$CHANGELOG_FILE"
  else
    log "Updating existing ${CHANGELOG_FILE}."
    # Replace or prepend the [Unreleased] block
    if grep -q "$UNRELEASED_HEADER" "$CHANGELOG_FILE"; then
      # Remove old Unreleased section (up to next ## heading or EOF)
      local tmp
      tmp="$(mktemp)"
      awk '/^## \[Unreleased\]/{skip=1} skip && /^## \[/ && !/^## \[Unreleased\]/{skip=0} !skip' \
        "$CHANGELOG_FILE" > "$tmp"
      # Prepend new section after the header lines
      local header_lines
      header_lines="$(head -n 4 "$CHANGELOG_FILE")"
      { echo "$header_lines"; echo ""; echo "$unreleased"; tail -n +5 "$tmp"; } > "$CHANGELOG_FILE"
      rm -f "$tmp"
    else
      local tmp
      tmp="$(mktemp)"
      { head -n 4 "$CHANGELOG_FILE"; echo ""; echo "$unreleased"; tail -n +5 "$CHANGELOG_FILE"; } > "$tmp"
      mv "$tmp" "$CHANGELOG_FILE"
    fi
  fi

  log "Done. ${CHANGELOG_FILE} updated."
}

main "$@"
