---
name: code-dead-code
description: |
  Detect dead code, unused exports, unreachable branches, and orphaned files.
  Use when reducing maintenance burden, cleaning up after refactors, or auditing
  codebase health. Pairs with /configure:dead-code for tool setup.
args: "[PATH] [--tool <knip|vulture|machete>] [--fix]"
argument-hint: path or directory to scan for dead code
allowed-tools: Bash(npx knip *), Bash(vulture *), Bash(cargo machete *), Bash(npx ts-prune *), Read, Grep, Glob, TodoWrite
created: 2026-04-10
modified: 2026-04-10
reviewed: 2026-04-10
---

# /code:dead-code

Detect and report dead code across languages.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Cleaning up after a major refactor | Setting up dead code tooling → /configure:dead-code |
| Auditing codebase for unused exports | Looking for duplicated code → /code:dry-consolidation |
| Reducing bundle size by removing dead code | Looking for anti-patterns → /code:antipatterns |
| Pre-merge cleanup of feature branches | Need full code review → /code:review |

## Context

- Package files: !`find . -maxdepth 1 \( -name "package.json" -o -name "pyproject.toml" -o -name "Cargo.toml" \) -type f`
- Knip config: !`find . -maxdepth 1 \( -name "knip.json" -o -name "knip.jsonc" -o -name ".knip.json" \) -type f`

## Parameters

- `$1`: Path to scan (defaults to current directory)
- `--tool`: Force specific tool (knip, vulture, machete)
- `--fix`: Automatically remove detected dead code where safe

## Execution

Execute this dead code detection workflow:

### Step 1: Detect project type and available tools

Check which languages are present and which dead code tools are available:
- JavaScript/TypeScript: Check for knip or ts-prune
- Python: Check for vulture
- Rust: Check for cargo-machete

If no tool is available, report which tool to install and suggest `/configure:dead-code` to set up the project.

### Step 2: Run dead code detection

**JavaScript/TypeScript (Knip):**
```bash
npx knip --reporter compact
```

If Knip is not configured:
```bash
npx knip --reporter compact --include files,exports,dependencies
```

**Python (Vulture):**
```bash
vulture ${1:-.} --min-confidence 80
```

**Rust (cargo-machete):**
```bash
cargo machete
```

### Step 3: Categorize findings

Group results by severity:

| Category | Severity | Action |
|---|---|---|
| Unused dependencies | High | Remove from package manifest |
| Unused exports | Medium | Remove export, check downstream |
| Unused files | Medium | Delete after confirming no dynamic imports |
| Unused variables/functions | Low | Remove if truly dead |

### Step 4: Apply fixes (if --fix)

If `--fix` flag is set:
1. Remove unused dependencies: update package.json/pyproject.toml/Cargo.toml
2. Remove unused exports (only if no external consumers)
3. Delete orphaned files (confirm no dynamic imports/requires reference them)
4. Run project tests to verify nothing broke

If `--fix` is not set, present a summary report with actionable items.

### Step 5: Report results

Print summary:
```
Dead Code Report
================
Unused files: N
Unused exports: N
Unused dependencies: N
Total dead code: N items

Top items to remove:
- [file:export] reason
```

## Post-Actions

- If many unused dependencies found → suggest `npm prune` or equivalent
- If no dead code tool configured → suggest `/configure:dead-code`
- If fixes applied → suggest running tests with `/test:run`

## Agentic Optimizations

| Context | Command |
|---|---|
| Quick JS/TS scan | `npx knip --reporter compact --include files,exports` |
| Python scan | `vulture . --min-confidence 80` |
| Rust scan | `cargo machete` |
| CI mode | `npx knip --reporter json` |
| Exports only | `npx knip --include exports --reporter compact` |
