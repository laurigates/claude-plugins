---
model: haiku
created: 2026-02-02
modified: 2026-02-11
reviewed: 2026-02-02
description: Install reusable GitHub Actions workflows for security, quality, and accessibility checks
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(mkdir *), Bash(ls *), AskUserQuestion, TodoWrite
argument-hint: "[--all] [--security] [--quality] [--a11y] [--list]"
name: configure-reusable-workflows
---

# /configure:reusable-workflows

Install Claude-powered reusable GitHub Actions workflows from claude-plugins into a project.

## Context

- Workflows dir: !`test -d .github/workflows && echo "EXISTS" || echo "MISSING"`
- Existing callers: !`find .github/workflows -maxdepth 1 -name 'claude-*' 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- TypeScript files: !`find . -maxdepth 2 -name '*.ts' -o -name '*.tsx' 2>/dev/null | head -3`
- Component files: !`find . -maxdepth 3 \( -name '*.jsx' -o -name '*.vue' -o -name '*.svelte' \) 2>/dev/null | head -3`

## Parameters

Parse from command arguments:

- `--all`: Install all workflows
- `--security`: Install security workflows only
- `--quality`: Install quality workflows only
- `--a11y`: Install accessibility workflows only
- `--list`: List available workflows without installing

## Available Workflows

### Security

| Workflow | Description | File |
|----------|-------------|------|
| secrets | Detect leaked secrets and credentials | `reusable-security-secrets.yml` |
| owasp | OWASP Top 10 vulnerability scanning | `reusable-security-owasp.yml` |
| deps | Dependency vulnerability audit | `reusable-security-deps.yml` |

### Quality

| Workflow | Description | File |
|----------|-------------|------|
| typescript | TypeScript strictness analysis | `reusable-quality-typescript.yml` |
| code-smell | Code smell detection | `reusable-quality-code-smell.yml` |
| async | Async/await pattern issues | `reusable-quality-async.yml` |

### Accessibility

| Workflow | Description | File |
|----------|-------------|------|
| wcag | WCAG 2.1 compliance checking | `reusable-a11y-wcag.yml` |
| aria | ARIA pattern validation | `reusable-a11y-aria.yml` |

## Execution

Execute this reusable workflow installation:

### Step 1: Detect current state

1. Check for `.github/workflows/` directory (create if missing)
2. List any existing Claude-powered workflow callers
3. Determine project type from files present

### Step 2: Select workflows

If no flags provided, ask the user which categories to install:

```
Available workflow categories:
  [1] Security (secrets, owasp, deps)
  [2] Quality (typescript, code-smell, async)
  [3] Accessibility (wcag, aria)
  [4] All workflows

Which categories? (comma-separated, e.g., 1,2):
```

If `--list` is set, print the Available Workflows tables above and stop.

### Step 3: Generate caller workflows

For each selected workflow, create a caller file in `.github/workflows/`.

**Naming convention**: `claude-<category>-<name>.yml`

Example: `claude-security-secrets.yml`

Use the caller workflow template:

```yaml
name: Claude <Category> - <Name>

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  check:
    uses: laurigates/claude-plugins/.github/workflows/reusable-<category>-<name>.yml@main
    with:
      # Default inputs - customize as needed
      max-turns: 5
    secrets: inherit
```

For complete caller workflow files per category, see [REFERENCE.md](REFERENCE.md).

### Step 4: Remind about secrets

After installation, print the required secret configuration:

```
Required secret: CLAUDE_CODE_OAUTH_TOKEN

To configure:
1. Go to repository Settings > Secrets and variables > Actions
2. Add secret: CLAUDE_CODE_OAUTH_TOKEN
3. Value: Your Claude Code OAuth token

Get token from: https://console.anthropic.com/
```

## Customization

After installation, users can customize:

| Input | Purpose | Example |
|-------|---------|---------|
| `file-patterns` | Files to scan | `'src/**/*.ts'` |
| `max-turns` | Claude analysis depth | `3` (quick) to `10` (thorough) |
| `fail-on-*` | Block merges on findings | `true` / `false` |
| `wcag-level` | Accessibility standard | `'A'`, `'AA'`, `'AAA'` |

## Post-Installation

1. **Configure secret**: Add `CLAUDE_CODE_OAUTH_TOKEN` to repository secrets
2. **Customize patterns**: Edit `file-patterns` to match project structure
3. **Adjust triggers**: Modify `paths` filters for relevant file types
4. **Test manually**: Use `workflow_dispatch` to test before PR triggers

## Flags

| Flag | Description |
|------|-------------|
| `--all` | Install all workflows |
| `--security` | Install security workflows only |
| `--quality` | Install quality workflows only |
| `--a11y` | Install accessibility workflows only |
| `--list` | List available workflows without installing |

## See Also

- `/configure:workflows` - Standard CI/CD workflows (container, release-please)
- `/configure:security` - Security tooling configuration
- `ci-workflows` skill - Workflow patterns
