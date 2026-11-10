---
created: 2026-02-04
modified: 2026-11-10
compatibility: claude-code
reviewed: 2026-06-17
description: "Claude Code health check — every environment check in one pass, names the broken layer, `--fix` repairs. Use when asked for a health check, or the install misbehaves and the cause is unknown."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-plugin-scope-lag.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-settings.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-hooks.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-mcp.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-permissions-coverage.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-runtime.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-usage.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/health-plugins/scripts/check-registry.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/health-plugins/scripts/fix-registry.sh *), Bash(pre-commit validate-config *), Read, Glob, Grep, TodoWrite, AskUserQuestion
args: "[--scope=all|registry|stack|agentic|runtime|usage] [--fix] [--dry-run] [--verbose]"
argument-hint: "[--scope=all|registry|stack|agentic|runtime|usage] [--fix] [--dry-run] [--verbose]"
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
- Project settings exists: !`find . -maxdepth 2 -path '*/.claude/settings.json'`
- Local settings exists: !`find . -maxdepth 2 -path '*/.claude/settings.local.json'`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Description |
|-----------|-------------|
| `--scope=<all\|registry\|stack\|agentic\|runtime\|usage>` | Which audits to run. Default `all`. |
| `--fix` | Apply fixes to findings (prompts for confirmation). |
| `--dry-run` | Preview fixes without modifying files. |
| `--verbose` | Include detailed diagnostics. |

**Scope semantics:**

| Scope | Covers |
|-------|--------|
| `registry` | Plugin registry health (orphaned `projectPath`, stale `enabledPlugins`, registry-vs-settings drift) |
| `stack` | Enabled plugins vs detected project tech stack |
| `agentic` | Skill/command/agent agentic-optimisation compliance |
| `runtime` | `~/.claude.json` bloat (dead `projects[]`/`githubRepoPaths[*]`, orphaned `disabledMcpServers`, duplicate MCP names, legacy `history`), `history.jsonl` growth, `cleanupPeriodDays` validity. Read-only. |
| `usage` | Session-telemetry mining of `~/.claude/projects/*/*.jsonl` for never-fired and dormant skills *and* plugin agents. Read-only, local-leaning (SKIPs when history is insufficient). |
| `all` | Environment checks + all five audits |

## Execution

Execute this diagnostic router. Default scope is `all` when `--scope` is not provided.

Run every bundled script exactly as spelled in this file — `bash ${CLAUDE_SKILL_DIR}/scripts/<name>.sh …` or `bash ${CLAUDE_PLUGIN_ROOT}/skills/health-plugins/scripts/<name>.sh …`, path unquoted. Each `allowed-tools` rule pre-approves the command text it spells, so an invocation written another way is not pre-approved and goes through the normal permission flow.

### Step 1: Run environment checks (always)

Environment checks run regardless of `--scope`. They cover the baseline health of the Claude Code installation and the current project's `.claude/` directory.

#### 1a. Core environment scripts (including 1d permissions coverage)

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh --home-dir "$HOME" --project-dir "$(pwd)"
bash ${CLAUDE_SKILL_DIR}/scripts/check-plugin-scope-lag.sh --home-dir "$HOME" --project-dir "$(pwd)"
bash ${CLAUDE_SKILL_DIR}/scripts/check-settings.sh --home-dir "$HOME" --project-dir "$(pwd)"
bash ${CLAUDE_SKILL_DIR}/scripts/check-hooks.sh --home-dir "$HOME" --project-dir "$(pwd)"
bash ${CLAUDE_SKILL_DIR}/scripts/check-mcp.sh --home-dir "$HOME" --project-dir "$(pwd)"
bash ${CLAUDE_SKILL_DIR}/scripts/check-permissions-coverage.sh --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=`, `REASON=` (when present) and `ISSUES:` from each. Pass `--verbose` when set on `$ARGUMENTS`.

Read the extra `check-settings.sh` keys (`PROJECT_DIR_RESOLVED=`, `PROJECT_DIR_HINT=`), `check-mcp.sh` keys (`MCP_SOURCE_COUNT=`, `SERVER:`, `SERVER_SHADOWED:`), `check-plugin-scope-lag.sh` `TYPE=scope_lag` rows, `check-hooks.sh` keys (`SETTINGS_HOOK_COUNT=`, `PLUGIN_HOOK_COUNT=`, `PLUGINS_UNRESOLVED=`, and the `SOURCE=` field on each `ISSUES:` row), and `check-permissions-coverage.sh` keys (`TOOLS_FOUND=`, `TOOLS_MISSING=`, `TOOLS_UNRESOLVED=`, `UNUSED_RULE_COUNT=`, `TYPE=missing_permission` rows) as described in [references/environment-checks.md](references/environment-checks.md#interpreting-the-1a-script-output), and name the config or `.mcp.json` file each finding came from (for `scope_lag`, the project path and both versions; for a hook finding, the settings file or the plugin that declared it; for `missing_permission`, the tool and the task file).

#### 1b, 1c, 1e. SessionStart smoke test, pre-commit config, marketplace enrollment

Run each check as specified in [references/environment-checks.md](references/environment-checks.md#checks-1b-1c-1e) and score it OK/WARN/ERROR (pre-commit may SKIP when the tool is absent).

### Step 2: Run scope-specific audits

For `--scope=registry` or `all`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/health-plugins/scripts/check-registry.sh --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=`, `PLUGIN_COUNT=`, `ORPHANED_ENTRIES=`, `STALE_ENABLED_ENTRIES=`, and `ISSUES:`.

For `--scope=stack` or `all`: invoke the `health-plugin:health-audit` skill with the Skill tool, passing `--verbose` when set. Load it through the Skill tool rather than reading its SKILL.md: only a loaded skill gets its own `${CLAUDE_SKILL_DIR}` substituted and its own `allowed-tools` (its `enabled-plugins.sh` and `claude plugin list` commands are not granted here).

For `--scope=agentic` or `all`: invoke the `health-plugin:health-agentic-audit` skill with the Skill tool the same way, passing `--verbose` when set.

For `--scope=runtime` or `all`:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-runtime.sh --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=`, `ISSUES:`, `CLEANUP_SUGGESTED=`, and the per-finding counts (`PROJECTS_DEAD=`, `GH_PATHS_DEAD=`, `ORPHAN_DISABLED_MCP=`, `DUPLICATE_MCP=`, `LEGACY_PROJECT_HISTORY_ENTRIES=`, `HISTORY_JSONL_BYTES=`, `CLEANUP_PERIOD_DAYS=`). `--history-warn-mb N` sets the `history.jsonl` WARN threshold (default 50). Pass `--verbose` to list every dead path / orphaned server (default is a single rolled-up issue per category to keep output compact).

The runtime audit is **read-only**: it prints suggested cleanups (`claude purge <path> --dry-run` for dead projects, `jq` filters otherwise) for the operator; what it detects is described in [references/audit-scopes.md](references/audit-scopes.md#runtime-scope).

> **Concurrent-write warning.** The harness rewrites `~/.claude.json` on session end. Before acting on the audit's suggested cleanups, close every other Claude Code session — otherwise the in-memory state of a live session will clobber your edits when it next writes the file. An automated cleanup writer is out of scope for this audit.

For `--scope=usage` or `all`:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-usage.sh --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=`, `REASON=` (when present), `HISTORY_AVAILABLE=`, `TRANSCRIPTS_SCANNED=`, `INVENTORY_SOURCE=`, `PLUGINS_ENABLED=`, `RETENTION_DAYS=`, `SKILLS_ENABLED=`, `SKILLS_FIRED=`, `SKILLS_NEVER_FIRED=`, `SKILLS_DORMANT=`, `AGENTS_ENABLED=`, `AGENTS_FIRED=`, `AGENTS_NEVER_FIRED=`, `AGENTS_DORMANT=`, `SCHEMA_DRIFT_SUSPECTED=`, and `ISSUES:`. Pass `--verbose` to list every never-fired / dormant skill and agent (default rolls each category into one issue line). Pass `--window-days N` to change the dormancy threshold (default 30). The inventory is read from `installed_plugins.json` + `enabledPlugins`, so only enabled plugins at their active version count.

The usage audit is **read-only** and advisory (review candidates, not a delete list); it SKIPs on insufficient history and WARNs on transcript schema drift. Never read `pluginUsage.usageCount` for it. Details: [references/audit-scopes.md](references/audit-scopes.md#usage-scope).

### Step 3: Report findings

Print a consolidated report grouped by scope:

1. **Environment** — plugins/settings/hooks/MCP status + counts, SessionStart smoke test, pre-commit validity, permissions coverage (tools found, tools missing an allow rule, unused project rules), marketplace enrollment
2. **Registry** — orphaned projectPath entries, stale enabledPlugins keys, registry-vs-settings drift
3. **Stack** — detected stack + relevant/irrelevant/missing plugin recommendations
4. **Agentic** — bare CLI commands missing compact/fail-fast/JSON flags, stale or missing `reviewed` dates (CLI-wrapper skills without an Agentic Optimizations table appear as INFO only)
5. **Runtime** — `~/.claude.json` size, dead projects/githubRepoPaths, orphaned disabledMcpServers, duplicate MCP naming, legacy per-project history; `history.jsonl` size; effective `cleanupPeriodDays` (read-only — no `--fix` path)
6. **Usage** — never-fired and dormant skills from session telemetry (read-only — no `--fix` path; SKIPs when history is insufficient)

Use `STATUS=` indicators (OK/WARN/ERROR) and issue counts per scope. Include the one-row-per-check table from [REFERENCE.md § Summary Table](REFERENCE.md#summary-table).

See [REFERENCE.md](REFERENCE.md) for the full report template.

### Step 4: Apply fixes (if `--fix`)

If `--fix` is set:

1. If `--scope=all` AND findings exist in multiple scopes, use `AskUserQuestion` to let the user pick which scopes to fix (multi-select: `registry`, `stack`, `agentic`).
2. For each selected scope, delegate:

   | Scope | Delegate to |
   |-------|-------------|
   | `registry` | `bash ${CLAUDE_PLUGIN_ROOT}/skills/health-plugins/scripts/fix-registry.sh --home-dir "$HOME" --project-dir "$(pwd)"` (append `--dry-run` when set) |
   | `stack` | Skill tool: `health-plugin:health-audit` with `--fix` (plus `--dry-run` when set); it runs its own Step 6 |
   | `agentic` | Skill tool: `health-plugin:health-agentic-audit` with `--fix`; it runs its own Step 6 |

3. Parse each script's output (`STATUS=`, `REMOVED_COUNT=`, `MESSAGE=`, `RESTART_REQUIRED=`) and report what changed.
4. If any fix reports `RESTART_REQUIRED=true`, remind the user to restart Claude Code.

Permissions coverage has no `--fix` path: report the missing rules and let the user decide which to add.

### Step 5: Verify

Re-run the relevant checks and confirm issue counts have dropped.

## Agentic Optimizations

Per-scope invocations and quick manual checks: [references/command-reference.md](references/command-reference.md).

## Known Issues

Known symptoms and their fix paths: [references/known-issues.md](references/known-issues.md).
