---
model: opus
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Run all infrastructure standards checks and configure compliance
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, SlashCommand
argument-hint: "[--check-only] [--fix] [--type <frontend|infrastructure|python>]"
name: configure-all
---

# /configure:all

Run all infrastructure standards compliance checks.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Performing comprehensive infrastructure audit | Checking single component (use specific `/configure:X` skill) |
| Setting up new project with all standards | Project already has all standards configured |
| CI/CD compliance validation | Need detailed status only (use `/configure:status`) |
| Running initial configuration | Interactive component selection needed (use `/configure:select`) |
| Batch-fixing all compliance issues with `--fix` | Manual review of each component preferred |

## Context

- Project standards: !`find . -maxdepth 1 -name \'.project-standards.yaml\' 2>/dev/null`
- Project type indicators: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name '*.tf' \) 2>/dev/null`
- Infrastructure dirs: !`find . -maxdepth 1 -type d \( -name 'terraform' -o -name 'helm' -o -name 'argocd' \) 2>/dev/null`
- Current standards version: !`grep -m1 "^standards_version:" .project-standards.yaml 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report status without offering fixes (CI/CD mode)
- `--fix`: Apply all fixes automatically without prompting
- `--type <type>`: Override auto-detected project type (frontend, infrastructure, python)

## Execution

Execute this comprehensive infrastructure standards compliance check:

### Step 1: Detect project type

1. Read `.project-standards.yaml` if it exists
2. Auto-detect project type from file indicators:
   - **infrastructure**: Has `terraform/`, `helm/`, `argocd/`, or `*.tf` files
   - **frontend**: Has `package.json` with vue/react dependencies
   - **python**: Has `pyproject.toml` or `requirements.txt`
3. Apply `--type` override if provided
4. Report detected vs tracked type if different

### Step 2: Run all checks

Execute each configure command in check-only mode using the SlashCommand tool:

```
/configure:makefile --check-only
/configure:pre-commit --check-only
/configure:release-please --check-only
/configure:dockerfile --check-only
/configure:container --check-only
/configure:skaffold --check-only
/configure:workflows --check-only
/configure:sentry --check-only
/configure:docs --check-only
/configure:github-pages --check-only
/configure:cache-busting --check-only
/configure:tests --check-only
/configure:coverage --check-only
/configure:memory-profiling --check-only
/configure:linting --check-only
/configure:formatting --check-only
/configure:dead-code --check-only
/configure:editor --check-only
/configure:security --check-only
```

Skip components that do not apply to the detected project type. For component applicability by project type, see [REFERENCE.md](REFERENCE.md).

Collect results from each check.

### Step 3: Generate compliance report

Print a summary table with each component's status (PASS/WARN/FAIL), overall counts, and a list of issues to fix. For report format template, see [REFERENCE.md](REFERENCE.md).

### Step 4: Apply fixes (if requested)

If `--fix` flag is set or user confirms:

1. Run each failing configure command with `--fix`
2. Report what was fixed and what requires manual intervention

### Step 5: Update standards tracking

Create or update `.project-standards.yaml` with the current standards version, project type, timestamp, and component versions. For template, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check (all components) | `/configure:all --check-only` |
| Auto-fix all issues | `/configure:all --fix` |
| Check standards file validity | `test -f .project-standards.yaml && cat .project-standards.yaml \| head -10` |
| List project type indicators | `find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) -exec basename {} \;` |
| Count missing components | `grep -c "status: missing" compliance-report.txt 2>/dev/null` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically |
| `--type <type>` | Override project type (frontend, infrastructure, python) |

## Exit Codes (for CI)

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | Warnings found (non-blocking) |
| 2 | Failures found (blocking) |

## Agent Teams (Optional)

For faster compliance checks on large projects, spawn teammates for parallel configuration checks:

| Teammate | Focus | Checks |
|----------|-------|--------|
| Linting teammate | Code quality configs | linting, formatting, dead-code, editor |
| Security teammate | Security configs | security, pre-commit, container |
| Testing teammate | Test infrastructure | tests, coverage, memory-profiling |
| CI teammate | Deployment configs | workflows, release-please, dockerfile, skaffold |

This is optional -- the skill works sequentially without agent teams.

## See Also

- `/configure:select` - Interactively select which components to configure
- `/configure:status` - Quick read-only status overview
- `/configure:pre-commit` - Pre-commit specific checks
- `/configure:release-please` - Release automation checks
- `/configure:dockerfile` - Dockerfile configuration checks
- `/configure:container` - Comprehensive container infrastructure
- `/configure:skaffold` - Kubernetes development checks
- `/configure:workflows` - GitHub Actions checks
- `/configure:sentry` - Sentry error tracking checks
- `/configure:docs` - Documentation standards and generators
- `/configure:github-pages` - GitHub Pages deployment
- `/configure:cache-busting` - Cache-busting strategies
- `/configure:tests` - Testing framework setup
- `/configure:coverage` - Code coverage configuration
- `/configure:memory-profiling` - Memory profiling with pytest-memray
- `/configure:linting` - Linter configuration
- `/configure:formatting` - Code formatter setup
- `/configure:dead-code` - Dead code detection
- `/configure:editor` - Editor/IDE configuration
- `/configure:security` - Security scanning
