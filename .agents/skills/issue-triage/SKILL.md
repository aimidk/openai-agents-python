# Issue Triage Skill

Automatically triages new GitHub issues by analyzing content, applying labels, assigning priority, and routing to appropriate team members.

## Overview

This skill monitors newly opened issues and performs intelligent triage by:
- Analyzing issue content to determine type (bug, feature request, question, documentation)
- Applying appropriate labels based on content classification
- Assigning priority levels (critical, high, medium, low)
- Identifying affected components or modules
- Suggesting assignees based on file ownership and expertise
- Adding a structured triage comment summarizing findings

## Trigger

This skill runs when:
- A new issue is opened
- An issue is reopened
- Manually triggered via workflow dispatch

## Inputs

| Input | Description | Required |
|-------|-------------|----------|
| `issue_number` | The GitHub issue number to triage | Yes |
| `repo` | Repository in `owner/repo` format | Yes |
| `github_token` | GitHub token with issues write permission | Yes |
| `openai_api_key` | OpenAI API key for content analysis | Yes |

## Outputs

| Output | Description |
|--------|-------------|
| `labels_applied` | Comma-separated list of labels applied |
| `priority` | Determined priority level |
| `issue_type` | Classified issue type |
| `triage_comment_id` | ID of the posted triage comment |

## Labels Applied

### Type Labels
- `bug` — Confirmed or suspected defect
- `enhancement` — New feature or improvement request
- `question` — Usage question or clarification needed
- `documentation` — Documentation gap or error
- `performance` — Performance-related issue

### Priority Labels
- `priority: critical` — Service outage or data loss
- `priority: high` — Major functionality broken
- `priority: medium` — Feature degraded, workaround exists
- `priority: low` — Minor issue or cosmetic

### Component Labels
- `component: agents` — Core agent runtime
- `component: tools` — Tool definitions and execution
- `component: tracing` — Tracing and observability
- `component: models` — Model providers and adapters
- `component: streaming` — Streaming response handling

## Configuration

Create `.agents/skills/issue-triage/config.yaml` to customize triage behavior:

```yaml
priority_keywords:
  critical: ["crash", "data loss", "security", "outage"]
  high: ["broken", "fails", "error", "exception"]
  medium: ["slow", "unexpected", "incorrect"]
  low: ["typo", "cosmetic", "minor"]

auto_assign: true
post_comment: true
```

## Usage

```bash
bash .agents/skills/issue-triage/scripts/run.sh \
  --issue-number 42 \
  --repo owner/repo
```
