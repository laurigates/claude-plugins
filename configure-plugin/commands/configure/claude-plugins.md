---
model: opus
created: 2026-01-23
modified: 2026-01-23
reviewed: 2026-01-23
description: Configure .claude/settings.json and GitHub Actions workflows to use the laurigates/claude-plugins marketplace
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(mkdir:*), AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--plugins <plugin1,plugin2,...>]"
---

# /configure:claude-plugins

Configure a project to use the `laurigates/claude-plugins` Claude Code plugin marketplace. Sets up `.claude/settings.json` permissions and GitHub Actions workflows (`claude.yml`, `claude-code-review.yml`) with the marketplace pre-configured.

## Context

- Settings file: !`cat .claude/settings.json 2>/dev/null || echo "not found"`
- Workflows dir: !`ls .github/workflows/claude*.yml 2>/dev/null || echo "none"`
- Git remote: !`git remote get-url origin 2>/dev/null || echo "unknown"`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report current configuration status without changes |
| `--fix` | Apply configuration automatically |
| `--plugins` | Comma-separated list of plugins to install (default: all recommended) |

### Available Plugins

| Plugin | Category | Description |
|--------|----------|-------------|
| `git-plugin` | Version Control | Commits, branches, PRs, repository management |
| `configure-plugin` | Infrastructure | Pre-commit, CI/CD, Docker, testing configuration |
| `testing-plugin` | Testing | Test execution, TDD workflow, coverage |
| `code-quality-plugin` | Quality | Code review, refactoring, linting |
| `typescript-plugin` | Language | TypeScript, ESLint, Biome |
| `python-plugin` | Language | uv, ruff, pytest, packaging |
| `tools-plugin` | Utilities | fd, rg, jq, shell utilities |
| `project-plugin` | Development | Project initialization and management |
| `documentation-plugin` | Documentation | API docs, README generation |
| `github-actions-plugin` | CI/CD | GitHub Actions workflows |
| `container-plugin` | Infrastructure | Docker, registry, Skaffold |
| `agent-patterns-plugin` | AI | Multi-agent coordination |
| `blueprint-plugin` | Development | PRD/PRP workflow |

## Workflow

### Phase 1: Detection

1. Check for existing `.claude/settings.json`
2. Check for existing `.github/workflows/claude.yml`
3. Check for existing `.github/workflows/claude-code-review.yml`
4. Detect project type (language, framework)

### Phase 2: Configure .claude/settings.json

Create or merge into `.claude/settings.json` the following structure:

```json
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git branch:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(git remote:*)",
      "Bash(git checkout:*)",
      "Bash(git fetch:*)",
      "Bash(gh pr:*)",
      "Bash(gh run:*)",
      "Bash(gh issue:*)",
      "Bash(pre-commit:*)",
      "Bash(detect-secrets:*)"
    ]
  }
}
```

**Important:** If `.claude/settings.json` already exists, MERGE the `permissions.allow` array without duplicating entries. Preserve any existing `hooks`, `env`, or other fields.

### Phase 3: Configure .github/workflows/claude.yml

Create `.github/workflows/claude.yml` with the Claude Code action configured to use the plugin marketplace:

```yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'issues' && contains(github.event.issue.body, '@claude'))
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            PLUGINS_LIST
```

Replace `PLUGINS_LIST` with the selected plugins in the format:
```
plugin-name@laurigates-plugins
```

One plugin per line. For example with default recommended plugins:
```yaml
          plugins: |
            git-plugin@laurigates-plugins
            code-quality-plugin@laurigates-plugins
            testing-plugin@laurigates-plugins
```

### Phase 4: Configure .github/workflows/claude-code-review.yml

Create `.github/workflows/claude-code-review.yml` for automatic PR reviews:

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Claude Code Review
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          prompt: |
            Review this pull request. Focus on:
            - Code quality and best practices
            - Potential bugs or security issues
            - Test coverage gaps
            - Documentation needs
          claude_args: "--max-turns 5"
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            code-quality-plugin@laurigates-plugins
            testing-plugin@laurigates-plugins
```

### Phase 5: Report

Generate a status report:

```
Claude Plugins Configuration Report
=====================================
Repository: <repo-name>

.claude/settings.json:
  Status:          <CREATED|UPDATED|EXISTS>
  Permissions:     <N> allowed patterns configured

.github/workflows/claude.yml:
  Status:          <CREATED|UPDATED|EXISTS>
  Marketplace:     laurigates/claude-plugins
  Plugins:         <list>

.github/workflows/claude-code-review.yml:
  Status:          <CREATED|UPDATED|EXISTS>
  Trigger:         PR opened/synchronize/reopened
  Plugins:         <list>

Next Steps:
  1. Add CLAUDE_CODE_OAUTH_TOKEN to repository secrets
     Settings > Secrets and variables > Actions > New repository secret
  2. Commit and push the new workflow files
  3. Test by mentioning @claude in a PR comment
```

## Plugin Selection Logic

If `--plugins` is not specified, select recommended plugins based on project type:

| Project Indicator | Recommended Plugins |
|-------------------|---------------------|
| `package.json` | `git-plugin`, `typescript-plugin`, `testing-plugin`, `code-quality-plugin` |
| `pyproject.toml` / `setup.py` | `git-plugin`, `python-plugin`, `testing-plugin`, `code-quality-plugin` |
| `Cargo.toml` | `git-plugin`, `rust-plugin`, `testing-plugin`, `code-quality-plugin` |
| `Dockerfile` | Above + `container-plugin` |
| `.github/workflows/` | Above + `github-actions-plugin` |
| Default (any) | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `tools-plugin` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report current status without making changes |
| `--fix` | Apply all configuration automatically |
| `--plugins` | Override automatic plugin selection |

## Important Notes

- The `CLAUDE_CODE_OAUTH_TOKEN` secret must be added manually to the repository
- If using AWS Bedrock or Google Vertex AI, adjust the authentication section accordingly
- The plugin marketplace URL uses HTTPS Git format: `https://github.com/laurigates/claude-plugins.git`
- Plugins are referenced as `<plugin-name>@laurigates-plugins` (marketplace name from marketplace.json)

## See Also

- `/configure:workflows` - General GitHub Actions workflow configuration
- `/configure:all` - Run all compliance checks
- `claude-security-settings` skill - Claude Code security settings
