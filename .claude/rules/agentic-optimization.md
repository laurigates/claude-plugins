---
created: 2025-12-20
modified: 2025-12-20
reviewed: 2025-12-20
paths:
  - "**/skills/**"
  - "**/SKILL.md"
---

# Agentic Optimization

When creating skills for CLI tools, optimize for AI agent consumption.

## Core Principles

1. **Minimize output** - Less context usage, faster processing
2. **Fail fast** - Stop early on errors
3. **Machine-readable** - JSON/structured output when available
4. **Actionable** - Include file:line references

## Compact Output Patterns

### Test Runners

| Tool | Compact Flag | Description |
|------|--------------|-------------|
| Bun | `--dots` | `.` pass, `F` fail |
| Vitest | `--reporter=dot` | Minimal dots |
| Playwright | `--reporter=line` | One line per test |
| Jest | `--silent` | Suppress console |

### Linters

| Tool | Compact Flag | Description |
|------|--------------|-------------|
| Biome | `--reporter=github` | file:line format |
| ESLint | `--format=unix` | One line per issue |
| Ruff | `--output-format=github` | GitHub annotations |

### General

| Pattern | Example |
|---------|---------|
| Limit output | `--max-diagnostics=10` |
| Errors only | `--diagnostic-level=error` |
| JSON output | `--reporter=json`, `-c` (compact) |
| Raw strings | `-r` (jq) |

## Fail-Fast Patterns

| Tool | Flag | Behavior |
|------|------|----------|
| Bun test | `--bail` or `--bail=N` | Stop after N failures |
| Vitest | `--bail=1` | Stop on first failure |
| pytest | `-x` | Exit on first error |
| npm test | `--bail` | Stop on failure |

## CI-Friendly Reporters

| Tool | CI Flag | Output |
|------|---------|--------|
| Bun test | `--reporter=junit` | XML for CI systems |
| Vitest | `--reporter=github-actions` | GH annotations |
| Biome | `--reporter=github` | GH annotations |
| Playwright | `--reporter=github` | GH annotations |

## Output Limiting

```bash
# Limit lines
command | head -N

# Context around matches (grep-like)
-A 5  # 5 lines after
-B 3  # 3 lines before
-C 2  # 2 lines around

# Max results
--max-results=10
--max-filesize=1M
```

## Structured Output

When available, prefer JSON for parsing:

```bash
# Compact JSON
jq -c '.'

# Raw output (no quotes)
jq -r '.field'

# Tool-specific
bun pm ls --json
npm ls --json
```

## Skill Documentation Pattern

Always include an "Agentic Optimizations" table:

```markdown
## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick test | `bun test --dots --bail=1` |
| CI test | `bun test --reporter=junit` |
| Errors only | `biome check --diagnostic-level=error` |
```

## Command Default Behaviors

When creating commands, default to agentic-optimized flags:

```markdown
## Execution

**Quick feedback (default for agentic use):**
\`\`\`bash
bun test --dots --bail=1 $PATTERN
\`\`\`
```

## Environment Detection

Switch modes on the CI environment with a **lookup table the agent reads**, not a
template conditional. Claude Code renders nothing in a `SKILL.md` body — a
`{{ if CI }}…{{ endif }}` block reaches the agent verbatim, so every branch
arrives at once and the selection is left as an exercise (issue #2265).

| Environment | Install | Test reporter |
|---|---|---|
| CI (`$CI` is set) | `bun install --frozen-lockfile` | `bun test --reporter=junit` |
| Local | `bun install` | `bun test --dots` |

Detect it once, then run the matching row. A real shell conditional is fine when
the command genuinely runs in a shell:

```bash
[ -n "${CI:-}" ] && bun install --frozen-lockfile || bun install
```
