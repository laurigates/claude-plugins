---
name: attributes-collect
description: Collect codebase health attributes as structured JSON. Use when you need a structured assessment of project health before routing to specialized agents.
allowed-tools: Bash(test *), Bash(wc *), Read, Glob, Grep, TodoWrite
args: "[--output <path>] [--categories <list>]"
argument-hint: "[--output .claude/attributes.json]"
created: 2026-03-15
modified: 2026-03-15
reviewed: 2026-03-15
---

# /attributes:collect

Collect structured codebase health attributes with severity and remediation actions.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Need structured health assessment before routing | Quick health score only (use `/health:check`) |
| Want machine-readable attribute JSON | Human-readable report (use `/attributes:dashboard`) |
| Planning which agents to invoke | Already know what needs fixing |
| Comparing health across repos | Checking specific component only |

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--output <path>` | Write JSON to file (default: stdout) |
| `--categories <list>` | Comma-separated categories to check: docs,tests,security,quality,ci |

## Execution

Perform these checks and output structured JSON.

### Step 1: Documentation Attributes

Check for these files and emit attributes:

| Check | Attribute ID | Severity |
|-------|-------------|----------|
| README.md exists | `missing-readme` | high |
| README.md > 200 chars | `short-readme` | low |
| CLAUDE.md exists | `missing-claude-md` | medium |
| docs/ directory exists | `no-docs-directory` | low |
| LICENSE file exists | `missing-license` | low |

Score: Start at 0, add points per check (max 20).

### Step 2: Testing Attributes

| Check | Attribute ID | Severity |
|-------|-------------|----------|
| tests/ or test/ directory exists | `no-test-directory` | high |
| Test config file exists (vitest, jest, pytest, etc.) | `no-test-config` | medium |
| CI workflow runs tests | `no-ci-tests` | high |

Test configs to look for: `vitest.config.{ts,js}`, `jest.config.{js,ts}`, `pytest.ini`, `conftest.py`, `playwright.config.ts`

### Step 3: Security Attributes

| Check | Attribute ID | Severity |
|-------|-------------|----------|
| .gitignore exists | `missing-gitignore` | high |
| .env file NOT committed | `env-file-committed` | critical |
| Pre-commit hooks configured | `no-pre-commit-hooks` | medium |
| Security scanning in CI | `no-security-scanning` | high |
| Dependabot configured | `no-dependabot` | low |

### Step 4: Code Quality Attributes

| Check | Attribute ID | Severity |
|-------|-------------|----------|
| Linter configured (eslint, biome, ruff) | `no-linter-configured` | medium |
| Formatter configured (prettier, biome, ruff) | `no-formatter` | medium |
| Type checking (tsconfig, pyright, mypy) | `no-type-checking` | low |

### Step 5: CI/CD Attributes

| Check | Attribute ID | Severity |
|-------|-------------|----------|
| CI workflows exist | `no-ci-workflows` | high |
| Workflows dir has files | `empty-workflows-dir` | medium |

### Step 6: Output

Output JSON matching this schema:

```json
{
  "version": "1",
  "repo": "<path>",
  "timestamp": "<ISO 8601>",
  "attributes": [
    {
      "id": "missing-readme",
      "category": "docs",
      "severity": "high",
      "description": "Missing README.md",
      "source": "attributes-collect",
      "actions": [
        {"type": "agent", "target": "docs", "args": "create README.md", "auto_fixable": true}
      ]
    }
  ],
  "scores": {
    "overall": 72,
    "grade": "C",
    "max_score": 100,
    "categories": {"docs": 15, "tests": 12, "security": 8, "quality": 17, "ci": 20}
  }
}
```

If `--output` is specified, write the JSON to that file.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Full attribute collection | `/attributes:collect` |
| Save to file | `/attributes:collect --output .claude/attributes.json` |
| Specific categories | `/attributes:collect --categories security,tests` |
| Check README exists | `test -f README.md && echo exists \|\| echo missing` |
| Check test dir | `test -d tests \|\| test -d test && echo exists \|\| echo missing` |
| Count README chars | `wc -c < README.md 2>/dev/null \|\| echo 0` |
