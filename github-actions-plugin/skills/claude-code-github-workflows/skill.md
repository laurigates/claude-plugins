---
name: Claude Code GitHub Workflows
description: Claude Code workflow design and automation patterns for PR reviews, issue triage, and CI/CD integration. Use when creating or modifying GitHub Actions workflows that integrate Claude Code.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, WebFetch, mcp__github
---

# Claude Code GitHub Workflows

Expert knowledge for designing GitHub Actions workflows that integrate Claude Code for automated code assistance, PR reviews, and issue triage.

## Core Expertise

**Workflow Design Patterns**
- Automated pull request reviews with inline comments
- Issue triage and automated responses
- CI failure auto-fix workflows
- Custom trigger configurations and event handling

**Trigger Configurations**
- Issue comment triggers (`@claude` mentions)
- Pull request events (opened, synchronize, ready_for_review)
- Workflow run triggers (CI failure handling)
- Path-filtered reviews for specific directories

## Essential Workflow Template

```yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'issues' && contains(github.event.issue.body, '@claude'))
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@v5
        with:
          fetch-depth: 1

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

## Automation Patterns

### Comprehensive PR Review
```yaml
name: Claude PR Review

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
name: Auto-Fix CI Failures

on:
  workflow_run:
    workflows: ["CI"]
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
name: Issue Triage

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
name: Review Backend Changes

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
name: Claude Custom Trigger

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
```yaml
name: Review External Contributions

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

## Performance Optimization

### Checkout Optimization
```yaml
# Fast checkout for large repos
- uses: actions/checkout@v5
  with:
    fetch-depth: 1          # Shallow clone
    sparse-checkout: |      # Only needed paths
      .github
      src
      tests
```

### Conversation Limits
```yaml
# Control execution time and cost
claude_args: |
  --max-turns 10  # Limit back-and-forth exchanges
```

### Conditional Execution
```yaml
# Skip unnecessary runs
jobs:
  claude:
    if: |
      contains(github.event.comment.body, '@claude') &&
      !contains(github.event.comment.body, 'ignore')
```

## Repository Configuration

### CLAUDE.md Example

Create `CLAUDE.md` in repository root to define coding standards:

```markdown
# Repository Guidelines for Claude Code

## Code Standards
- Use TypeScript strict mode
- Follow Airbnb style guide
- Maintain 90%+ test coverage
- Document all public APIs

## Development Workflow
- Run tests before committing: `npm test`
- Format with Prettier: `npm run format`
- Lint with ESLint: `npm run lint`

## Commit Messages
Follow Conventional Commits:
- feat: New features
- fix: Bug fixes
- docs: Documentation changes
- refactor: Code refactoring

## Testing Requirements
- Unit tests for all functions
- Integration tests for APIs
- E2E tests for critical flows

## Security
- Never commit secrets
- Validate all user inputs
- Use parameterized queries
- Follow OWASP guidelines
```

## Quick Setup

1. **Install Claude GitHub App**: https://github.com/apps/claude
2. **Add API Key**: Repository Settings → Secrets → `ANTHROPIC_API_KEY`
3. **Create Workflow**: `.github/workflows/claude.yml` (use template above)
4. **Test**: Create issue and comment `@claude Hello!`
5. **(Optional)** Add `CLAUDE.md` in repo root for project standards

## Troubleshooting

### Workflow Not Triggering
- Check trigger conditions in `if:` clause
- Verify permissions (contents, pull-requests, issues)
- Check GitHub App installation

### Permission Denied
- Ensure proper permissions in workflow
- Check branch protection rules
- Verify repository access

For advanced configuration including MCP servers, tool permissions, and authentication methods, see the github-actions-mcp-config and github-actions-auth-security skills.
