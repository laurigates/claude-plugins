---
model: opus
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
description: Check and configure pre-commit hooks for project standards
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--type <frontend|infrastructure|python>]"
---

# /configure:pre-commit

Check and configure pre-commit hooks against project standards.

## Context

This command validates `.pre-commit-config.yaml` against project standards and optionally applies fixes.

**Skills referenced**: `pre-commit-standards`

## Version Checking

**CRITICAL**: Before flagging outdated hook versions, verify latest releases:

1. **pre-commit-hooks**: Check [GitHub releases](https://github.com/pre-commit/pre-commit-hooks/releases)
2. **conventional-pre-commit**: Check [GitHub releases](https://github.com/compilerla/conventional-pre-commit/releases)
3. **biome**: Check [GitHub releases](https://github.com/biomejs/biome/releases)
4. **ruff-pre-commit**: Check [GitHub releases](https://github.com/astral-sh/ruff-pre-commit/releases)
5. **detect-secrets**: Check [GitHub releases](https://github.com/Yelp/detect-secrets/releases)

Use WebSearch or WebFetch to verify current versions before reporting outdated hooks.

## Workflow

### Phase 1: Project Type Detection

Determine project type to select appropriate standards:

1. Check for `.project-standards.yaml` with `project_type` field
2. If not found, auto-detect:
   - **infrastructure**: Has `terraform/`, `helm/`, `argocd/`, or `*.tf` files
   - **frontend**: Has `package.json` with vue/react dependencies
   - **python**: Has `pyproject.toml` or `requirements.txt`
3. Allow override via `--type` flag

### Phase 2: Configuration Detection

1. Check if `.pre-commit-config.yaml` exists
2. If missing: Report FAIL status, offer to create from template
3. If exists: Read and parse configuration

### Phase 3: Compliance Analysis

Compare existing configuration against project standards (from `pre-commit-standards` skill):

**Required Base Hooks (All Projects):**
- `pre-commit-hooks` v5.0.0+ with: trailing-whitespace, end-of-file-fixer, check-yaml, check-json, check-merge-conflict, check-added-large-files
- `conventional-pre-commit` v4.3.0+ with commit-msg stage

**Frontend-specific:**
- `biome` (pre-commit) v0.4.0+
- `helmlint` (if helm/ directory exists)

**Infrastructure-specific:**
- `tflint`, `helmlint` (gruntwork v0.1.29+)
- `actionlint` v1.7.7+
- `helm-docs` v1.14.2+
- `detect-secrets` v1.5.0+

**Python-specific:**
- `ruff-pre-commit` v0.8.4+ (ruff, ruff-format)
- `detect-secrets` v1.5.0+

### Phase 4: Report Generation

Generate compliance report:

```
Pre-commit Compliance Report
================================
Project Type: frontend (detected)
Config File: .pre-commit-config.yaml (found)

Hook Status:
  pre-commit-hooks     v5.0.0   ✅ PASS
  conventional-pre-commit v3.6.0   ⚠️ WARN (standard: v4.3.0)
  biome                v0.4.0   ✅ PASS
  helmlint             v0.1.23  ⚠️ WARN (standard: v0.1.29)

Outdated Hooks:
  - conventional-pre-commit: v3.6.0 → v4.3.0
  - gruntwork/helmlint: v0.1.23 → v0.1.29

Overall: 2 issues found
```

### Phase 5: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing config file**: Create from standard template for detected project type
2. **Missing hooks**: Add required hooks with standard versions
3. **Outdated versions**: Update `rev:` values to standard versions
4. **Missing hook types**: Add `default_install_hook_types` with `pre-commit` and `commit-msg`

After modification:
- Run `pre-commit install --install-hooks` to install hooks
- Update `.project-standards.yaml` with compliance status

### Phase 6: Standards Tracking

Update or create `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
project_type: "frontend"
last_configured: "2025-11-28"
components:
  pre-commit: "2025.1"
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--type <type>` | Override project type detection (frontend, infrastructure, python) |

## Examples

```bash
# Check compliance and offer fixes
/configure:pre-commit

# Check only, no modifications
/configure:pre-commit --check-only

# Auto-fix all issues
/configure:pre-commit --fix

# Force infrastructure type
/configure:pre-commit --type infrastructure
```

## Error Handling

- **No git repository**: Warn but continue (pre-commit still useful)
- **Invalid YAML**: Report parse error, offer to replace with template
- **Unknown hook repos**: Skip (don't remove custom hooks)
- **Permission errors**: Report and suggest manual fix

## See Also

- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview
- `pre-commit-standards` skill - Standard definitions
