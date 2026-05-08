# PR Auto Review Skill

Automatically reviews pull requests for code quality, consistency, and potential issues in the `openai-agents-python` repository.

## Overview

This skill performs automated code review on pull requests by analyzing:
- Code style and formatting consistency
- Type annotation completeness
- Docstring presence and quality
- Breaking changes in public APIs
- Test coverage for new functionality
- Dependency changes

## Trigger

This skill is triggered when:
- A new pull request is opened
- A pull request is updated with new commits
- Manually invoked via workflow dispatch

## Inputs

| Input | Description | Required |
|-------|-------------|----------|
| `pr_number` | The pull request number to review | Yes |
| `repo` | Repository in `owner/repo` format | Yes |
| `github_token` | GitHub token with PR read/write access | Yes |
| `openai_api_key` | OpenAI API key for AI-assisted review | No |

## Outputs

The skill posts a structured review comment on the pull request containing:
- **Summary**: High-level overview of changes
- **Issues**: List of potential problems found
- **Suggestions**: Improvement recommendations
- **Checklist**: Automated checks with pass/fail status

## Checklist Items

- [ ] All new public functions/classes have docstrings
- [ ] Type annotations present on function signatures
- [ ] New features have corresponding tests
- [ ] No unused imports introduced
- [ ] `CHANGELOG` or release notes updated (for significant changes)
- [ ] Examples updated if public API changed
- [ ] No hardcoded secrets or credentials

## Configuration

The skill can be configured via `.agents/skills/pr-auto-review/config.yaml`:

```yaml
review:
  min_test_coverage_delta: -2  # Allow up to 2% coverage drop
  require_docstrings: true
  require_type_hints: true
  check_changelog: false        # Set true for release branches
  ai_review_enabled: true
```

## Usage

```yaml
- uses: .agents/skills/pr-auto-review
  with:
    pr_number: ${{ github.event.pull_request.number }}
    repo: ${{ github.repository }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    openai_api_key: ${{ secrets.OPENAI_API_KEY }}
```

## Notes

- The skill will not block merging; it only posts informational review comments.
- AI-assisted review requires a valid `OPENAI_API_KEY`; if absent, only static checks run.
- Review comments are updated in-place on subsequent pushes to avoid comment spam.
