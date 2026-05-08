# Dependency Update Skill

This skill automates the process of checking for outdated dependencies and creating pull requests to update them in the `openai-agents-python` project.

## Overview

The skill performs the following steps:

1. **Audit current dependencies** — Reads `pyproject.toml` and `requirements*.txt` files to inventory all declared dependencies.
2. **Check for updates** — Queries PyPI for the latest available versions of each dependency.
3. **Evaluate compatibility** — Runs the test suite against candidate updates to verify nothing breaks.
4. **Report results** — Outputs a structured summary of available updates, compatibility status, and recommended actions.

## Inputs

| Variable | Required | Default | Description |
|---|---|---|---|
| `TARGET_BRANCH` | No | `main` | Branch to compare against |
| `UPDATE_MODE` | No | `minor` | One of `patch`, `minor`, `major` |
| `DRY_RUN` | No | `true` | When `true`, report only — do not modify files |
| `PYTHON_VERSION` | No | `3.11` | Python version used for compatibility checks |

## Outputs

- `dependency-update-report.json` — Machine-readable report of all dependency statuses.
- `dependency-update-summary.md` — Human-readable summary suitable for a PR description.

## Usage

### Bash (Linux / macOS)

```bash
bash .agents/skills/dependency-update/scripts/run.sh
```

### PowerShell (Windows)

```powershell
.agents/skills/dependency-update/scripts/run.ps1
```

## Notes

- The skill respects version constraints defined in `pyproject.toml`. It will not suggest updates that violate declared specifiers unless `UPDATE_MODE=major` is set.
- Pre-release versions are ignored by default.
- The skill caches PyPI responses for 1 hour to avoid rate limiting during repeated runs.
