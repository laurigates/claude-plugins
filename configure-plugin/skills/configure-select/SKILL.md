---
model: haiku
created: 2025-12-22
modified: 2026-02-10
reviewed: 2025-12-22
description: Interactively select which infrastructure standards to configure
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, SlashCommand
argument-hint: "[--check-only] [--fix]"
name: configure-select
---

# /configure:select

Interactively select which infrastructure standards checks to run.

## Context

- Project standards: !`test -f .project-standards.yaml && echo "EXISTS" || echo "MISSING"`
- Project type: !`head -20 .project-standards.yaml 2>/dev/null | grep -m1 "^project_type:" | sed 's/^[^:]*:[[:space:]]*//'`
- Has terraform: !`find . -maxdepth 2 \( -name '*.tf' -o -type d -name 'terraform' \) 2>/dev/null | head -1`
- Has package.json: !`test -f package.json && echo "EXISTS" || echo "MISSING"`
- Has pyproject.toml: !`test -f pyproject.toml && echo "EXISTS" || echo "MISSING"`
- Has Cargo.toml: !`test -f Cargo.toml && echo "EXISTS" || echo "MISSING"`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report status without offering fixes (CI/CD mode)
- `--fix`: Apply fixes automatically to all selected components

## Execution

Execute this interactive component selection workflow:

### Step 1: Detect project type

1. Read `.project-standards.yaml` if it exists (check `project_type` field)
2. Auto-detect from file structure:
   - **infrastructure**: Has `terraform/`, `helm/`, `argocd/`, or `*.tf` files
   - **frontend**: Has `package.json` with vue/react dependencies
   - **python**: Has `pyproject.toml` or `requirements.txt`
   - **rust**: Has `Cargo.toml`
3. Report detected type to user

### Step 2: Present component selection

Use AskUserQuestion with multiSelect to present four category-based questions:

**Question 1: CI/CD & Version Control**

| Option | Description |
|--------|-------------|
| Pre-commit hooks | Git hooks for linting, formatting, commit messages |
| Release automation | release-please workflow and changelog generation |
| GitHub Actions | CI/CD workflows for testing and deployment |
| All CI/CD | Includes: pre-commit, release-please, workflows, github-pages, makefile |

**Question 2: Container & Deployment**

| Option | Description |
|--------|-------------|
| Dockerfile | Alpine/slim base, non-root user, multi-stage builds |
| Container infra | Registry, scanning, devcontainer setup |
| Skaffold | Kubernetes development configuration |
| All container | Includes: dockerfile, container, skaffold, sentry, justfile |

**Question 3: Testing**

| Option | Description |
|--------|-------------|
| Test framework | Vitest, Jest, pytest, or cargo-nextest setup |
| Code coverage | Coverage thresholds and reporting |
| API testing | Pact contracts, OpenAPI validation |
| All testing | Includes: tests, coverage, api-tests, integration-tests, load-tests, ux-testing, memory-profiling |

**Question 4: Code Quality**

| Option | Description |
|--------|-------------|
| Linting & Formatting | Biome, Ruff, Clippy configuration |
| Security scanning | Dependency audits, SAST, secrets detection |
| Documentation | TSDoc, JSDoc, pydoc, rustdoc generators |
| All quality | Includes: linting, formatting, dead-code, docs, security, editor, package-management |

### Step 3: Map selections to commands

| Selection | Commands |
|-----------|----------|
| Pre-commit hooks | `/configure:pre-commit` |
| Release automation | `/configure:release-please` |
| GitHub Actions | `/configure:workflows` |
| All CI/CD | pre-commit, release-please, workflows, github-pages, makefile |
| Dockerfile | `/configure:dockerfile` |
| Container infra | `/configure:container` |
| Skaffold | `/configure:skaffold` |
| All container | dockerfile, container, skaffold, sentry, justfile |
| Test framework | `/configure:tests` |
| Code coverage | `/configure:coverage` |
| API testing | `/configure:api-tests` |
| All testing | tests, coverage, api-tests, integration-tests, load-tests, ux-testing, memory-profiling |
| Linting & Formatting | `/configure:linting`, `/configure:formatting` |
| Security scanning | `/configure:security` |
| Documentation | `/configure:docs` |
| All quality | linting, formatting, dead-code, docs, security, editor, package-management |

### Step 4: Execute selected checks

Run each selected command with appropriate flags:

- Default: Run with `--check-only` first, then offer `--fix`
- If `--check-only` flag: Only audit, no fixes offered
- If `--fix` flag: Apply fixes automatically

Report results as each check completes.

### Step 5: Generate summary report

Print a summary for selected components only:

```
Selected Components Summary:
+-----------------+----------+---------------------------------+
| Component       | Status   | Notes                           |
+-----------------+----------+---------------------------------+
| Pre-commit      | WARN     | 2 outdated hooks                |
| Linting         | PASS     | Biome configured                |
| Formatting      | PASS     | Biome configured                |
+-----------------+----------+---------------------------------+
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically to all selected |

## Comparison with Other Commands

| Command | Use Case |
|---------|----------|
| `/configure:all` | Run everything (CI, full audit) |
| `/configure:select` | Choose specific components interactively |
| `/configure:status` | Quick read-only overview |
| `/configure:<component>` | Single component only |

## See Also

- `/configure:all` - Run all checks
- `/configure:status` - Read-only status overview
