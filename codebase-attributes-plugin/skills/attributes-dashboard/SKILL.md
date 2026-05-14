---
name: attributes-dashboard
description: Codebase health dashboard with scores and severity for docs, testing, security, and CI/CD. Use when wanting a health overview or terminal-style summary with action suggestions.
allowed-tools: Bash(test *), Read, Glob, Grep
args: "[--format <type>]"
argument-hint: ""
created: 2026-03-15
modified: 2026-05-09
reviewed: 2026-03-15
---

# /attributes:dashboard

Compact text-based health dashboard with scores, bars, and findings.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Want quick visual health overview | Need machine-readable JSON (use `/attributes:collect`) |
| Reviewing health before a session | Want to fix issues (use `/attributes:route`) |
| Comparing categories at a glance | Need detailed diagnostics (use `/health:check`) |

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--format` | Output format: `compact` (default), `detailed` |

## Execution

### Step 1: Load Attribute Data

Read `.claude/attributes.json` if it exists. Otherwise, perform the same checks as `/attributes:collect` inline.

### Step 2: Render Dashboard

Output a compact terminal-style dashboard:

```
Health: 72/100 (C)  [██████████████░░░░░░]

  Documentation    15/20  [███████████████░░░░░]
  Testing          12/20  [████████████░░░░░░░░]
  Security          8/20  [████████░░░░░░░░░░░░]  2 critical/high
  Code Quality     17/20  [█████████████████░░░]
  CI/CD            20/20  [████████████████████]

  Critical: 2  High: 3  Medium: 5  Low: 8

  ⚠ Critical (2)
    security: .env file committed to repository
    security: No security scanning in CI
  ⚠ High (3)
    tests: No test directory or test files found
    tests: No CI workflow runs tests
    security: Missing .gitignore
  ▲ Medium (5)
    docs: Missing CLAUDE.md
    ...
```

### Step 3: Detailed Mode

If `--format detailed`, also show:
- Action suggestions for each finding
- Auto-fixable indicator
- Target agent for each finding

```
  ⚠ Critical (2)
    security: .env file committed → agent:security "fix .env exposure" (manual)
    security: No security scanning → agent:security "setup CI security scanning" [auto-fixable]
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick dashboard | `/attributes:dashboard` |
| Detailed with actions | `/attributes:dashboard --format detailed` |
| Check if data exists | `test -f .claude/attributes.json && echo cached \|\| echo fresh` |
