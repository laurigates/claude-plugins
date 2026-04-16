---
created: 2026-02-04
modified: 2026-04-16
reviewed: 2026-04-16
description: Run a comprehensive diagnostic scan of Claude Code configuration (plugins, settings, hooks, MCP servers, SessionStart executability, pre-commit validity, permissions coverage, marketplace enrollment) and optionally fix detected issues across registry, stack relevance, and agentic optimisation scopes
allowed-tools: Bash(bash *), Bash(pre-commit *), Read, Glob, Grep, TodoWrite, AskUserQuestion
args: "[--scope=all|registry|stack|agentic] [--fix] [--dry-run] [--verbose]"
argument-hint: "[--scope=all|registry|stack|agentic] [--fix] [--dry-run] [--verbose]"
name: health-check
---

# /health:check

Single entry point for Claude Code health diagnostics. Runs environment checks (plugin registry, settings, hooks, MCP servers, SessionStart executability, pre-commit validity, permissions coverage, marketplace enrollment) plus optional deeper audits, and routes `--fix` to the appropriate internal workflow.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Running Claude Code diagnostics | Viewing raw settings (use Read on settings.json) |
| Troubleshooting plugin registry issues | Inspecting marketplace metadata manually |
| Auditing plugins for project fit | Installing a specific plugin (use `/plugin install`) |
| Checking skill agentic-optimisation quality | Editing a single known skill |
| One-stop `--fix` across registry/stack/agentic | Precise surgical edits to a single file |

## Context

- Current project: !`pwd`
- Project settings exists: !`find .claude -maxdepth 1 -name 'settings.json'`
- Local settings exists: !`find .claude -maxdepth 1 -name 'settings.local.json'`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Description |
|-----------|-------------|
| `--scope=<all\|registry\|stack\|agentic>` | Which audits to run. Default `all`. |
| `--fix` | Apply fixes to findings (prompts for confirmation). |
| `--dry-run` | Preview fixes without modifying files. |
| `--verbose` | Include detailed diagnostics. |

**Scope semantics:**

| Scope | Covers |
|-------|--------|
| `registry` | Plugin registry health (orphaned `projectPath`, stale `enabledPlugins`, registry-vs-settings drift) |
| `stack` | Enabled plugins vs detected project tech stack |
| `agentic` | Skill/command/agent agentic-optimisation compliance |
| `all` | Environment checks + all three audits |

## Execution

Execute this diagnostic router. Default scope is `all` when `--scope` is not provided.

### Step 1: Run environment checks (always)

Environment checks run regardless of `--scope`. They cover the baseline health of the Claude Code installation and the current project's `.claude/` directory.

#### 1a. Core environment scripts

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh" --home-dir "$HOME" --project-dir "$(pwd)"
bash "${CLAUDE_SKILL_DIR}/scripts/check-settings.sh" --home-dir "$HOME" --project-dir "$(pwd)"
bash "${CLAUDE_SKILL_DIR}/scripts/check-hooks.sh" --home-dir "$HOME" --project-dir "$(pwd)"
bash "${CLAUDE_SKILL_DIR}/scripts/check-mcp.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=` and `ISSUES:` from each. Pass `--verbose` when set on `$ARGUMENTS`.

#### 1b. SessionStart smoke test

Check whether `scripts/install_pkgs.sh` (or any script registered in the `SessionStart` hook in `.claude/settings.json`) is executable and exits cleanly in both remote and local contexts.

1. Locate the `SessionStart` hook command from `.claude/settings.json` (look for the `command` field).
2. If a script is found, run:
   ```bash
   CLAUDE_CODE_REMOTE=true bash <script-path>
   ```
   Capture exit code. Expected: 0.
3. Run again to verify idempotency — expected: 0.
4. Run with remote guard off:
   ```bash
   CLAUDE_CODE_REMOTE=false bash <script-path>
   ```
   Expected: 0 (typically a no-op).
5. Report:
   - OK: All three exit 0
   - WARN: Script exists but is not registered in settings.json hook
   - ERROR: Script exits non-zero, or script referenced in hook does not exist

#### 1c. Pre-commit config validator

If `.pre-commit-config.yaml` exists:

```bash
pre-commit validate-config .pre-commit-config.yaml
```

Report:
- OK: exits 0 (config is valid)
- WARN: `pre-commit` not installed — skip check, suggest `pip install pre-commit`
- ERROR: exits non-zero — show validation error

#### 1d. Permissions coverage check

Compare tools referenced in project files against `permissions.allow` in `.claude/settings.json`.

1. Read `permissions.allow` from `.claude/settings.json`. Extract the command prefix from each `Bash(<prefix>:*)` entry.
2. Scan these files for tool invocations:
   - `justfile` / `Justfile` — commands on recipe lines
   - `Makefile` — shell commands on recipe lines
   - `.pre-commit-config.yaml` — `entry:` fields
3. For each tool found in project files:
   - Flag as **MISSING** if no matching `Bash(<tool>:*)` entry exists in `permissions.allow`
4. For each `Bash(<tool>:*)` entry in `permissions.allow`:
   - Flag as **UNUSED** if the tool is not found in any project file (informational, not an error)

Scoring:
- OK: No missing permissions
- WARN: 1–3 missing permissions
- ERROR: 4+ missing permissions

#### 1e. Marketplace enrollment check

1. Read `.claude/settings.json`.
2. Check that `extraKnownMarketplaces.claude-plugins` exists with `source.repo = "laurigates/claude-plugins"`.
3. Check that `enabledPlugins` contains at least one `@claude-plugins` entry.
4. Report:
   - OK: Both checks pass
   - WARN: `enabledPlugins` is empty or missing (marketplace enrolled but no plugins enabled)
   - ERROR: `extraKnownMarketplaces` is missing (run `/configure:claude-plugins --fix` to add it)

### Step 2: Run scope-specific audits

For `--scope=registry` or `all`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/health-plugins/scripts/check-registry.sh" \
  --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=`, `PLUGIN_COUNT=`, `ORPHANED_ENTRIES=`, `STALE_ENABLED_ENTRIES=`, and `ISSUES:`.

For `--scope=stack` or `all`: follow the tech-stack audit steps from the internal `health-audit` skill (see `${CLAUDE_PLUGIN_ROOT}/skills/health-audit/SKILL.md` and its `REFERENCE.md`).

For `--scope=agentic` or `all`: follow the skill-quality audit steps from the internal `health-agentic-audit` skill (see `${CLAUDE_PLUGIN_ROOT}/skills/health-agentic-audit/SKILL.md` and its `REFERENCE.md`).

### Step 3: Report findings

Print a consolidated report grouped by scope:

1. **Environment** — plugins/settings/hooks/MCP status + counts, SessionStart smoke test, pre-commit validity, permissions coverage, marketplace enrollment
2. **Registry** — orphaned projectPath entries, stale enabledPlugins keys, registry-vs-settings drift
3. **Stack** — detected stack + relevant/irrelevant/missing plugin recommendations
4. **Agentic** — skills missing optimisation tables, bare CLI commands, stale reviews

Use `STATUS=` indicators (OK/WARN/ERROR) and issue counts per scope. Include a summary table:

| Check | Status | Issues |
|-------|--------|--------|
| Plugin registry | OK/WARN/ERROR | ... |
| Settings files | OK/WARN/ERROR | ... |
| Hooks configuration | OK/WARN/ERROR | ... |
| MCP servers | OK/WARN/ERROR | ... |
| SessionStart smoke test | OK/WARN/ERROR | ... |
| Pre-commit config | OK/WARN/ERROR/SKIP | ... |
| Permissions coverage | OK/WARN/ERROR | ... |
| Marketplace enrollment | OK/WARN/ERROR | ... |
| Registry audit | OK/WARN/ERROR | ... |
| Stack audit | OK/WARN/ERROR | ... |
| Agentic audit | OK/WARN/ERROR | ... |

See [REFERENCE.md](REFERENCE.md) for the full report template.

### Step 4: Apply fixes (if `--fix`)

If `--fix` is set:

1. If `--scope=all` AND findings exist in multiple scopes, use `AskUserQuestion` to let the user pick which scopes to fix (multi-select: `registry`, `stack`, `agentic`).
2. For each selected scope, delegate:

   | Scope | Delegate to |
   |-------|-------------|
   | `registry` | `bash "${CLAUDE_PLUGIN_ROOT}/skills/health-plugins/scripts/fix-registry.sh" --home-dir "$HOME" --project-dir "$(pwd)"` (pass `--dry-run` when set) |
   | `stack` | Follow the `--fix` flow in `${CLAUDE_PLUGIN_ROOT}/skills/health-audit/SKILL.md` (Step 6) |
   | `agentic` | Follow the `--fix` flow in `${CLAUDE_PLUGIN_ROOT}/skills/health-agentic-audit/SKILL.md` (Step 6) |

3. Parse each script's output (`STATUS=`, `REMOVED_COUNT=`, `MESSAGE=`, `RESTART_REQUIRED=`) and report what changed.
4. If any fix reports `RESTART_REQUIRED=true`, remind the user to restart Claude Code.

### Step 5: Verify

Re-run the relevant checks and confirm issue counts have dropped.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Full scan | `/health:check` |
| Registry only | `/health:check --scope=registry` |
| Stack relevance only | `/health:check --scope=stack` |
| Agentic audit only | `/health:check --scope=agentic` |
| Fix everything (interactive) | `/health:check --fix` |
| Dry-run preview of fixes | `/health:check --fix --dry-run` |
| Detailed diagnostics | `/health:check --verbose` |
| Check plugin registry exists | `find ~/.claude/plugins -name 'installed_plugins.json'` |
| Validate settings JSON | `find .claude -maxdepth 1 -name 'settings.json'` |
| Smoke-test install script | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` |
| Validate pre-commit config | `pre-commit validate-config .pre-commit-config.yaml` |
| Check marketplace enrollment | `find .claude -maxdepth 1 -name 'settings.json'` then grep for `extraKnownMarketplaces` |

## Known Issues

| Issue | Symptom | Fix path |
|-------|---------|----------|
| [#14202](https://github.com/anthropics/claude-code/issues/14202) | Plugin shows "installed" but not active | `/health:check --scope=registry --fix` |
| Stale `enabledPlugins` key in settings.json | Plugin appears enabled but no registry/marketplace entry | `/health:check --scope=registry --fix` |
| Orphaned `projectPath` | Plugin installed for deleted project | `/health:check --scope=registry --fix` |
| Invalid settings JSON | Settings file won't load | `/health:check` |
| Missing marketplace enrollment | `@claude-plugins` skills unavailable in web sessions | `/configure:claude-plugins --fix` |
