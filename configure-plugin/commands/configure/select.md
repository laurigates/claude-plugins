---
model: haiku
created: 2025-12-22
modified: 2025-12-22
reviewed: 2025-12-22
description: Interactively select which infrastructure standards to configure
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, SlashCommand
argument-hint: "[--check-only] [--fix]"
---

# /configure:select

Interactively select which infrastructure standards checks to run.

## Context

Unlike `/configure:all` which runs everything, this command presents a multi-select interface to choose specific components. Useful when you want to configure a subset without running all 20+ checks.

## Workflow

### Phase 1: Project Detection

1. Read `.project-standards.yaml` if exists
2. Auto-detect project type:
   - **infrastructure**: Has `terraform/`, `helm/`, `argocd/`, or `*.tf` files
   - **frontend**: Has `package.json` with vue/react dependencies
   - **python**: Has `pyproject.toml` or `requirements.txt`
   - **rust**: Has `Cargo.toml`
3. Report detected type to user

### Phase 2: Component Selection

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

### Phase 3: Build Command List

Map selections to configure commands:

```
Selection Mapping:
┌────────────────────────┬────────────────────────────────────────────┐
│ Selection              │ Commands                                   │
├────────────────────────┼────────────────────────────────────────────┤
│ Pre-commit hooks       │ /configure:pre-commit                      │
│ Release automation     │ /configure:release-please                  │
│ GitHub Actions         │ /configure:workflows                       │
│ All CI/CD              │ pre-commit, release-please, workflows,     │
│                        │ github-pages, makefile                     │
├────────────────────────┼────────────────────────────────────────────┤
│ Dockerfile             │ /configure:dockerfile                      │
│ Container infra        │ /configure:container                       │
│ Skaffold               │ /configure:skaffold                        │
│ All container          │ dockerfile, container, skaffold, sentry,   │
│                        │ justfile                                   │
├────────────────────────┼────────────────────────────────────────────┤
│ Test framework         │ /configure:tests                           │
│ Code coverage          │ /configure:coverage                        │
│ API testing            │ /configure:api-tests                       │
│ All testing            │ tests, coverage, api-tests, integration-   │
│                        │ tests, load-tests, ux-testing,             │
│                        │ memory-profiling                           │
├────────────────────────┼────────────────────────────────────────────┤
│ Linting & Formatting   │ /configure:linting, /configure:formatting  │
│ Security scanning      │ /configure:security                        │
│ Documentation          │ /configure:docs                            │
│ All quality            │ linting, formatting, dead-code, docs,      │
│                        │ security, editor, package-management       │
└────────────────────────┴────────────────────────────────────────────┘
```

### Phase 4: Execute Selected Checks

Run each selected command with appropriate flags:

- Default: Run with `--check-only` first, then offer `--fix`
- If `--check-only` flag: Only audit, no fixes offered
- If `--fix` flag: Apply fixes automatically

Report results as each check completes.

### Phase 5: Generate Summary Report

Same format as `/configure:all` but only for selected components:

```
Selected Components Summary:
┌─────────────────┬──────────┬─────────────────────────────────┐
│ Component       │ Status   │ Notes                           │
├─────────────────┼──────────┼─────────────────────────────────┤
│ Pre-commit      │ ⚠️ WARN  │ 2 outdated hooks                │
│ Linting         │ ✅ PASS  │ Biome configured                │
│ Formatting      │ ✅ PASS  │ Biome configured                │
└─────────────────┴──────────┴─────────────────────────────────┘
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically to all selected |

## Examples

```bash
# Interactive selection with audit first
/configure:select

# Check-only mode (CI-friendly)
/configure:select --check-only

# Auto-fix selected components
/configure:select --fix
```

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
