---
model: haiku
created: 2026-02-02
modified: 2026-02-02
reviewed: 2026-02-02
description: Install reusable GitHub Actions workflows for security, quality, and accessibility checks
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(mkdir *), Bash(ls *), AskUserQuestion, TodoWrite
argument-hint: "[--all] [--security] [--quality] [--a11y] [--list]"
name: configure-reusable-workflows
---

# /configure:reusable-workflows

Install Claude-powered reusable GitHub Actions workflows from claude-plugins into a project.

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

## Workflow

### Phase 1: Detection

1. Check for `.github/workflows/` directory (create if missing)
2. List any existing Claude-powered workflow callers
3. Determine project type from files present

### Phase 2: Selection

If no flags provided, ask user which categories to install:

```
Available workflow categories:
  [1] Security (secrets, owasp, deps)
  [2] Quality (typescript, code-smell, async)
  [3] Accessibility (wcag, aria)
  [4] All workflows

Which categories? (comma-separated, e.g., 1,2):
```

### Phase 3: Generate Caller Workflows

For each selected workflow, create a caller file in `.github/workflows/`.

**Naming convention**: `claude-<category>-<name>.yml`

Example: `claude-security-secrets.yml`

### Caller Workflow Template

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

### Phase 4: Secret Reminder

After installation, remind user:

```
Required secret: CLAUDE_CODE_OAUTH_TOKEN

To configure:
1. Go to repository Settings > Secrets and variables > Actions
2. Add secret: CLAUDE_CODE_OAUTH_TOKEN
3. Value: Your Claude Code OAuth token

Get token from: https://console.anthropic.com/
```

## Generated Files

### Security Workflows

**`.github/workflows/claude-security-secrets.yml`**

```yaml
name: Claude Security - Secrets Detection

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-secrets.yml@main
    with:
      file-patterns: '**/*'
      max-turns: 5
    secrets: inherit
```

**`.github/workflows/claude-security-owasp.yml`**

```yaml
name: Claude Security - OWASP

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    with:
      file-patterns: '**/*.{js,ts,jsx,tsx,py}'
      max-turns: 6
      fail-on-critical: true
    secrets: inherit
```

**`.github/workflows/claude-security-deps.yml`**

```yaml
name: Claude Security - Dependencies

on:
  pull_request:
    branches: [main]
    paths:
      - 'package*.json'
      - 'requirements*.txt'
      - 'Pipfile*'
      - 'poetry.lock'
      - 'go.sum'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  audit:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-deps.yml@main
    with:
      package-manager: 'auto'
      max-turns: 5
      fail-on-high: true
    secrets: inherit
```

### Quality Workflows

**`.github/workflows/claude-quality-typescript.yml`**

```yaml
name: Claude Quality - TypeScript

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.ts'
      - '**/*.tsx'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  analyze:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-typescript.yml@main
    with:
      file-patterns: '**/*.{ts,tsx}'
      max-turns: 6
      strict-mode: true
    secrets: inherit
```

**`.github/workflows/claude-quality-code-smell.yml`**

```yaml
name: Claude Quality - Code Smell

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  analyze:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-code-smell.yml@main
    with:
      file-patterns: '**/*.{js,ts,jsx,tsx,py}'
      max-turns: 5
      severity-threshold: 'medium'
    secrets: inherit
```

**`.github/workflows/claude-quality-async.yml`**

```yaml
name: Claude Quality - Async Patterns

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.ts'
      - '**/*.tsx'
      - '**/*.js'
      - '**/*.jsx'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  analyze:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-async.yml@main
    with:
      file-patterns: '**/*.{js,ts,jsx,tsx}'
      max-turns: 5
    secrets: inherit
```

### Accessibility Workflows

**`.github/workflows/claude-a11y-wcag.yml`**

```yaml
name: Claude A11y - WCAG

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.tsx'
      - '**/*.jsx'
      - '**/*.vue'
      - '**/*.svelte'
      - '**/*.html'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  check:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-wcag.yml@main
    with:
      file-patterns: '**/*.{tsx,jsx,vue,svelte,html}'
      max-turns: 6
      wcag-level: 'AA'
    secrets: inherit
```

**`.github/workflows/claude-a11y-aria.yml`**

```yaml
name: Claude A11y - ARIA

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.tsx'
      - '**/*.jsx'
      - '**/*.vue'
      - '**/*.svelte'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  check:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-aria.yml@main
    with:
      file-patterns: '**/*.{tsx,jsx,vue,svelte}'
      max-turns: 5
    secrets: inherit
```

## Flags

| Flag | Description |
|------|-------------|
| `--all` | Install all workflows |
| `--security` | Install security workflows only |
| `--quality` | Install quality workflows only |
| `--a11y` | Install accessibility workflows only |
| `--list` | List available workflows without installing |

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

## See Also

- `/configure:workflows` - Standard CI/CD workflows (container, release-please)
- `/configure:security` - Security tooling configuration
- `ci-workflows` skill - Workflow patterns
