# Changelog Generator Skill

Automatically generates or updates the CHANGELOG.md file based on git commit history, pull request titles, and semantic versioning conventions.

## Overview

This skill analyzes the git log between the last tagged release and the current HEAD, categorizes commits by type (feat, fix, chore, docs, etc.), and produces a formatted changelog entry following the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.

## Trigger Conditions

This skill should be invoked when:
- A new release tag is being prepared
- A pull request is merged into the main branch
- Manually requested via workflow dispatch

## Inputs

| Variable | Description | Required | Default |
|---|---|---|---|
| `GITHUB_TOKEN` | GitHub token for API access | Yes | — |
| `FROM_TAG` | Starting git tag or commit SHA for changelog range | No | last tag |
| `TO_REF` | Ending git ref for changelog range | No | `HEAD` |
| `VERSION` | Version string for the new changelog entry | No | auto-detected |
| `DRY_RUN` | If `true`, print changelog without writing to file | No | `false` |

## Outputs

- Updates `CHANGELOG.md` in the repository root with a new versioned entry
- Commits and pushes the updated changelog (unless `DRY_RUN=true`)
- Prints the generated changelog section to stdout

## Commit Categories

Commits are grouped into the following changelog sections:

- **Added** — `feat:` commits
- **Fixed** — `fix:` commits
- **Changed** — `refactor:`, `perf:` commits
- **Deprecated** — `deprecate:` commits
- **Removed** — `remove:`, `revert:` commits
- **Security** — `security:` commits
- **Documentation** — `docs:` commits
- **Maintenance** — `chore:`, `ci:`, `build:`, `test:` commits

## Usage

```yaml
- uses: .agents/skills/changelog-generator
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    VERSION: "1.2.0"
```

## Notes

- Merge commits and commits with `[skip changelog]` in the message are excluded
- If no conventional commit prefix is found, the commit is placed under **Maintenance**
- The skill respects `.changelogrc` if present in the repository root for custom configuration
