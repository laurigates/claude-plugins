# Claude Code GitHub Workflows — Automation Pattern Templates

Complete workflow templates referenced from [SKILL.md](../SKILL.md). Each follows the display-name convention and the v1 gotchas described there.

## Automation Patterns

### Comprehensive PR Review
```yaml
name: "Claude: PR review"

on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v5
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          track_progress: true
          prompt: |
            Review this PR focusing on:
            1. Code Quality
            2. Security
            3. Performance
            4. Testing
            5. Documentation
```

### CI Failure Auto-Fix
```yaml
name: "Auto-fix: CI failures"

on:
  workflow_run:
    # The string here must match the target workflow's `name:` exactly.
    workflows: ["Test: Suite"]
    types: [completed]

jobs:
  auto-fix:
    if: github.event.workflow_run.conclusion == 'failure'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      actions: read
    steps:
      - uses: actions/checkout@v5
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            The CI workflow failed. Please:
            1. Analyze the failure logs
            2. Identify the root cause
            3. Implement a fix
            4. Create a PR with the fix
```

### Issue Triage and Labeling
```yaml
name: "Claude: Issue triage"

on:
  issues:
    types: [opened]

jobs:
  triage:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Analyze this issue and:
            1. Add appropriate labels (bug, feature, documentation, etc.)
            2. Suggest a priority level
            3. Recommend assignment if obvious
            4. Ask clarifying questions if needed
```

### Path-Filtered PR Review
```yaml
name: "Claude: Review backend changes"

on:
  pull_request:
    paths:
      - 'backend/**'
      - 'api/**'

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v5
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Review backend changes focusing on:
            - API design and RESTful principles
            - Database query optimization
            - Error handling and logging
            - Security vulnerabilities
```

### Custom Trigger Phrase
```yaml
name: "Claude: Custom trigger"

on:
  issue_comment:
    types: [created]

jobs:
  claude:
    if: contains(github.event.comment.body, '/claude-review')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
    steps:
      - uses: actions/checkout@v5
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          trigger_phrase: "/claude-review"
```

### External Contributor Handling

> **Security:** `pull_request_target` runs in the **base** repo context with
> access to secrets and a write-capable token, even for fork PRs. The job below
> checks out untrusted head code (`head.sha`) for review only — do **not** add
> build/test steps that execute that code, and treat the PR title/body/comments
> as untrusted input in the prompt. See `github-actions-auth-security` and
> `.claude/rules/github-actions-security.md`.

```yaml
name: "Claude: Review external contributions"

on:
  pull_request_target:
    types: [opened]

jobs:
  review:
    if: github.event.pull_request.author_association == 'FIRST_TIME_CONTRIBUTOR'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v5
        with:
          ref: ${{ github.event.pull_request.head.sha }}

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Welcome first-time contributor! Review this PR for:
            - Code quality and style compliance
            - Test coverage
            - Documentation updates
            - Security concerns

            Provide helpful, constructive feedback.
```
