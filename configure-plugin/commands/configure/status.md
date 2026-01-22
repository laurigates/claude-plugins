---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
description: Show infrastructure standards compliance status (read-only)
allowed-tools: Glob, Grep, Read, TodoWrite
argument-hint: "[--verbose]"
---

# /configure:status

Display infrastructure standards compliance status without making changes.

## Context

Quick read-only check of repository compliance against project standards. Use this to see current status before running `/configure:all` or specific configure commands.

## Workflow

### Phase 1: Project Detection

1. Read `.project-standards.yaml` if exists (shows tracked version and last configured date)
2. Auto-detect project type from file structure
3. Report discrepancy if detected type differs from tracked type

### Phase 2: Configuration Scan

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
| Security | `.github/workflows/*security*`, `.secrets.baseline`, `pyproject.toml [tool.bandit]` |

### Phase 3: Quick Compliance Check

For each component, determine status:

| Status | Meaning |
|--------|---------|
| ✅ PASS | Fully compliant with project standards |
| ⚠️ WARN | Present but outdated or incomplete |
| ❌ FAIL | Missing required configuration |
| ⏭️ SKIP | Not applicable for project type |

### Phase 4: Report Output

```
Infrastructure Standards Status
====================================
Repository: R4C-Cesium-Viewer
Project Type: frontend (detected)
Standards Version: 2025.1 (tracked: 2025.1)
Last Configured: 2025-11-15

Component Status:
  Pre-commit      ✅ PASS   v5.0.0 hooks, conventional commits
  Release-please  ✅ PASS   Node workspace plugin
  Dockerfile      ⚠️ WARN   Missing healthcheck
  Skaffold        ✅ PASS   3 profiles configured
  CI Workflows    ⚠️ WARN   Missing test workflow
  Helm            ⏭️ SKIP   No helm/ directory
  Cache Busting   ✅ PASS   Content hashing enabled (Next.js)
  Tests           ✅ PASS   Vitest configured
  Coverage        ⚠️ WARN   72% (below 80% threshold)
  Linting         ✅ PASS   Biome configured
  Formatting      ✅ PASS   Biome configured
  Dead Code       ⚠️ WARN   Knip found 3 unused exports
  Editor          ✅ PASS   .editorconfig present
  Security        ✅ PASS   detect-secrets + npm audit

Summary: 2 warnings, 0 failures
Run /configure:all to fix issues
```

### Phase 5: Verbose Mode

If `--verbose` flag:
- Show specific version numbers for each hook/tool
- List individual compliance checks performed
- Show detected deviations from `.project-standards.yaml`
- Display file modification timestamps
- Show cache-busting configuration details (framework, CDN, hash patterns)

## Flags

| Flag | Description |
|------|-------------|
| `--verbose` | Show detailed compliance information |

## Examples

```bash
# Quick status overview
/configure:status

# Detailed compliance report
/configure:status --verbose
```

## Notes

- This command is **read-only** - no files are modified
- Use for CI/CD compliance checks (exit code reflects status)
- Run before `/configure:all` to preview what will be fixed

## See Also

- `/configure:all` - Run all compliance checks
- `/configure:select` - Interactively select which components to configure
- `/configure:pre-commit` - Pre-commit specific checks
- `/configure:release-please` - Release-please specific checks
- `/configure:cache-busting` - Cache-busting specific checks
