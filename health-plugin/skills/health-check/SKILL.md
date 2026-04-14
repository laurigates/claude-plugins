---
created: 2026-02-04
modified: 2026-04-14
reviewed: 2026-04-14
description: Run a comprehensive diagnostic scan of Claude Code configuration including plugins, settings, hooks, MCP servers, SessionStart executability, pre-commit validity, permissions coverage, and marketplace enrollment
allowed-tools: Bash(bash *), Read, Glob, Grep, TodoWrite
args: "[--fix] [--verbose]"
argument-hint: "[--fix] [--verbose]"
name: health-check
---

# /health:check

Run a comprehensive diagnostic scan of your Claude Code environment. Identifies issues with plugin registry, settings files, hooks configuration, and MCP servers.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Running comprehensive Claude Code diagnostics | Checking specific component only (use `/health:plugins`, `/health:settings`) |
| Troubleshooting general Claude Code issues | Plugin registry issues only (use `/health:plugins --fix`) |
| Validating environment configuration | Auditing plugins for project fit (use `/health:audit`) |
| Identifying misconfigured settings or hooks | Just viewing settings (use Read tool on settings.json) |
| Quick health check before starting work | Need agentic optimization audit (use `/health:agentic-audit`) |

## Context

- User home: !`echo $HOME`
- Current project: !`pwd`
- Project settings exists: !`find .claude -maxdepth 1 -name 'settings.json'`
- Local settings exists: !`find .claude -maxdepth 1 -name 'settings.local.json'`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Attempt to automatically fix identified issues |
| `--verbose` | Show detailed diagnostic information |

## Execution

Execute this comprehensive health check by running the diagnostic scripts. Pass `--verbose` and `--fix` flags through from `$ARGUMENTS` when specified.

### Step 1: Check plugin registry

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh" --home-dir "$HOME" --project-dir "$(pwd)" [--fix] [--verbose]
```

Parse the `STATUS=` and `ISSUES:` lines from output.

### Step 2: Validate settings files

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-settings.sh" --home-dir "$HOME" --project-dir "$(pwd)" [--verbose]
```

Parse the `STATUS=` and `ISSUES:` lines from output.

### Step 3: Check hooks configuration

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-hooks.sh" --home-dir "$HOME" --project-dir "$(pwd)" [--verbose]
```

Parse the `STATUS=` and `ISSUES:` lines from output.

### Step 4: Check MCP server configuration

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-mcp.sh" --home-dir "$HOME" --project-dir "$(pwd)" [--verbose]
```

Parse the `STATUS=` and `ISSUES:` lines from output.

### Step 5: SessionStart smoke test

Check whether `scripts/install_pkgs.sh` (or any script registered in the `SessionStart` hook in `.claude/settings.json`) is executable and exits cleanly in both remote and local contexts.

1. Locate the `SessionStart` hook command from `.claude/settings.json` (look for the `command` field).
2. If a script is found, run:
   ```bash
   CLAUDE_CODE_REMOTE=true bash <script-path>
   ```
   Capture exit code. Expected: 0.
3. Run again to verify idempotency:
   ```bash
   CLAUDE_CODE_REMOTE=true bash <script-path>
   ```
   Expected: 0 (second run must also succeed).
4. Run with remote guard off:
   ```bash
   CLAUDE_CODE_REMOTE=false bash <script-path>
   ```
   Expected: 0 (script must exit cleanly when not in remote mode — typically a no-op).
5. Report results:
   - OK: All three exit 0
   - WARN: Script exists but is not registered in settings.json hook
   - ERROR: Script exits non-zero, or script referenced in hook does not exist

### Step 6: Pre-commit config validator

If `.pre-commit-config.yaml` exists:

```bash
pre-commit validate-config .pre-commit-config.yaml
```

Report:
- OK: exits 0 (config is valid)
- WARN: `pre-commit` not installed — skip check, suggest `pip install pre-commit`
- ERROR: exits non-zero — show validation error

### Step 7: Permissions coverage check

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

Report a table:

```
Permissions Coverage
====================
MISSING (in project files, not in allow list):
  just      (found in Makefile — add "Bash(just:*)")
  docker    (found in justfile — add "Bash(docker:*)")

UNUSED (in allow list, not found in project files):
  Bash(gofmt:*)   (informational)
```

Scoring:
- OK: No missing permissions
- WARN: 1–3 missing permissions
- ERROR: 4+ missing permissions

### Step 8: Marketplace enrollment check

1. Read `.claude/settings.json`.
2. Check that `extraKnownMarketplaces.claude-plugins` exists with `source.repo = "laurigates/claude-plugins"`.
3. Check that `enabledPlugins` contains at least one `@claude-plugins` entry.
4. Report:
   - OK: Both checks pass
   - WARN: `enabledPlugins` is empty or missing (marketplace enrolled but no plugins enabled)
   - ERROR: `extraKnownMarketplaces` is missing (run `/configure:claude-plugins --fix` to add it)

### Step 9: Generate the diagnostic report

Using the structured output from Steps 1-8, print a diagnostic report following the template in [REFERENCE.md](REFERENCE.md). Include status indicators (OK/WARN/ERROR), issue counts, and recommended actions. If `--fix` was used and fixes were applied, include a summary of changes made.

Include rows for the new checks in the summary table:

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick health check | `/health:check` |
| Health check with auto-fix | `/health:check --fix` |
| Detailed diagnostics | `/health:check --verbose` |
| Check plugin registry exists | `find ~/.claude/plugins -name 'installed_plugins.json'` |
| Validate settings JSON | `find .claude -maxdepth 1 -name 'settings.json'` |
| Smoke-test install script | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` |
| Verify idempotency | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` (run twice) |
| Validate pre-commit config | `pre-commit validate-config .pre-commit-config.yaml` |
| Check marketplace enrollment | `find .claude -maxdepth 1 -name 'settings.json'` then grep for `extraKnownMarketplaces` |

## Known Issues Database

Reference these known Claude Code issues when diagnosing:

| Issue | Symptoms | Solution |
|-------|----------|----------|
| #14202 | Plugin shows "installed" but not active in project | Run `/health:plugins --fix` |
| Orphaned projectPath | Plugin was installed for deleted project | Run `/health:plugins --fix` |
| Invalid JSON | Settings file won't load | Validate and fix JSON syntax |
| Hook timeout | Commands hang or fail silently | Check hook timeout settings |

## Flags

| Flag | Description |
|------|-------------|
| `--fix` | Attempt automatic fixes for identified issues |
| `--verbose` | Include detailed diagnostic output |

## See Also

- `/health:plugins` - Detailed plugin registry diagnostics
- `/health:settings` - Settings file validation
- `/health:hooks` - Hooks configuration check
- `/health:mcp` - MCP server diagnostics
