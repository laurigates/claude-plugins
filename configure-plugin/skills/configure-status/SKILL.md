---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Show infrastructure standards compliance status (read-only)
allowed-tools: Glob, Grep, Read, TodoWrite
argument-hint: "[--verbose]"
name: configure-status
---

# /configure:status

Display infrastructure standards compliance status without making changes.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Checking overall compliance status | Running full compliance checks with fixes (use `/configure:all --fix`) |
| Generating compliance reports | Need to fix issues found (use `/configure:all`) |
| Quick project health check | Checking specific component (use `/configure:X --check-only`) |
| CI/CD status validation | Running interactive selection (use `/configure:select`) |
| Reviewing current configuration state | Need detailed component analysis |

## Context

- Project standards: !`find . -maxdepth 1 -name \'.project-standards.yaml\' 2>/dev/null`
- Project type: !`grep -m1 "^project_type:" .project-standards.yaml 2>/dev/null`
- Standards version: !`grep -m1 "^standards_version:" .project-standards.yaml 2>/dev/null`
- Last configured: !`grep -m1 "^last_configured:" .project-standards.yaml 2>/dev/null`
- Pre-commit config: !`find . -maxdepth 1 -name \'.pre-commit-config.yaml\' 2>/dev/null`
- Workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' 2>/dev/null`
- Has Dockerfile: !`find . -maxdepth 1 -name 'Dockerfile*' 2>/dev/null -print -quit`
- Has skaffold: !`find . -maxdepth 1 -name \'skaffold.yaml\' 2>/dev/null`
- Has helm: !`find . -maxdepth 2 -type d -name 'helm' 2>/dev/null -print -quit`
- Test configs: !`find . -maxdepth 1 \( -name 'vitest.config.*' -o -name 'jest.config.*' -o -name 'pytest.ini' \) 2>/dev/null`
- Linting config: !`find . -maxdepth 1 \( -name 'biome.json' -o -name '.eslintrc*' \) 2>/dev/null`
- Editor config: !`find . -maxdepth 1 -name \'.editorconfig\' 2>/dev/null`
- Gitleaks config: !`find . -maxdepth 1 -name \'.gitleaks.toml\' 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--verbose`: Show detailed compliance information for each component

## Execution

Execute this read-only compliance status check:

### Step 1: Detect project type

1. Read `.project-standards.yaml` if it exists (shows tracked version and last configured date)
2. Auto-detect project type from file structure
3. Report discrepancy if detected type differs from tracked type

### Step 2: Scan configuration files

Check for presence and validity of each configuration:

| Component | Files Checked |
|-----------|---------------|
| Pre-commit | `.pre-commit-config.yaml` |
| Release-please | `release-please-config.json`, `.release-please-manifest.json`, `.github/workflows/release-please.yml` |
| Dockerfile | `Dockerfile`, `Dockerfile.*` |
| Skaffold | `skaffold.yaml` |
| CI Workflows | `.github/workflows/*.yml` |
| Helm | `helm/*/Chart.yaml` |
| Documentation | `tsdoc.json`, `typedoc.json`, `mkdocs.yml`, `docs/conf.py`, `pyproject.toml [tool.ruff.lint.pydocstyle]` |
| GitHub Pages | `.github/workflows/docs.yml`, `.github/workflows/*pages*.yml` |
| Cache Busting | `next.config.*`, `vite.config.*`, `vercel.json`, `_headers` |
| Tests | `vitest.config.*`, `jest.config.*`, `pytest.ini`, `pyproject.toml [tool.pytest]`, `.cargo/config.toml` |
| Coverage | `vitest.config.* [coverage]`, `pyproject.toml [tool.coverage]`, `.coveragerc` |
| Linting | `biome.json`, `pyproject.toml [tool.ruff]`, `clippy.toml` |
| Formatting | `.prettierrc*`, `biome.json`, `pyproject.toml [tool.ruff.format]`, `rustfmt.toml` |
| Dead Code | `knip.json`, `knip.ts`, `pyproject.toml [tool.vulture]` |
| Editor | `.editorconfig`, `.vscode/settings.json`, `.vscode/extensions.json` |
| Security | `.github/workflows/*security*`, `.gitleaks.toml`, `pyproject.toml [tool.bandit]` |

### Step 3: Determine compliance status

For each component, assign a status:

| Status | Meaning |
|--------|---------|
| PASS | Fully compliant with project standards |
| WARN | Present but outdated or incomplete |
| FAIL | Missing required configuration |
| SKIP | Not applicable for project type |

### Step 4: Print compliance report

```
Infrastructure Standards Status
====================================
Repository: [name]
Project Type: [type] ([detected])
Standards Version: [version] (tracked: [tracked])
Last Configured: [date]

Component Status:
  Pre-commit      PASS   v5.0.0 hooks, conventional commits
  Release-please  PASS   Node workspace plugin
  Dockerfile      WARN   Missing healthcheck
  Skaffold        PASS   3 profiles configured
  CI Workflows    WARN   Missing test workflow
  Helm            SKIP   No helm/ directory
  Tests           PASS   Vitest configured
  Coverage        WARN   72% (below 80% threshold)
  Linting         PASS   Biome configured
  Formatting      PASS   Biome configured
  Dead Code       WARN   Knip found 3 unused exports
  Editor          PASS   .editorconfig present
  Security        PASS   gitleaks + npm audit

Summary: [N] warnings, [N] failures
Run /configure:all to fix issues
```

### Step 5: Show verbose details (if requested)

If `--verbose` flag is set:

- Show specific version numbers for each hook/tool
- List individual compliance checks performed
- Show detected deviations from `.project-standards.yaml`
- Display file modification timestamps
- Show cache-busting configuration details (framework, CDN, hash patterns)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status check | `/configure:status` |
| Verbose status | `/configure:status --verbose` |
| Check standards version | `grep "^standards_version:" .project-standards.yaml 2>/dev/null \| sed 's/.*:[[:space:]]*//'` |
| Check last configured date | `grep "^last_configured:" .project-standards.yaml 2>/dev/null \| sed 's/.*:[[:space:]]*//'` |
| List all workflow files | `find .github/workflows -maxdepth 1 -name '*.yml' -exec basename {} \;` |

## Flags

| Flag | Description |
|------|-------------|
| `--verbose` | Show detailed compliance information |

## Notes

- This command is **read-only** - no files are modified
- Use for CI/CD compliance checks (exit code reflects status)
- Run before `/configure:all` to preview what will be fixed

## See Also

- `/configure:all` - Run all compliance checks
- `/configure:select` - Interactively select which components to configure
- `/configure:pre-commit` - Pre-commit specific checks
- `/configure:release-please` - Release-please specific checks
