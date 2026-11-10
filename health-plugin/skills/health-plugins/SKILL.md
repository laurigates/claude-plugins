---
created: 2026-02-04
modified: 2026-11-10
compatibility: claude-code
reviewed: 2026-11-10
user-invocable: false
description: "Run check-registry.sh and fix-registry.sh: find orphaned projectPath rows and stale enabledPlugins keys, back up, remove. Use when seeing plugin-already-installed errors or registry drift."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-registry.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/fix-registry.sh *), Bash(claude plugin list *), Bash(claude plugin install *), Read, Glob, Grep, TodoWrite, AskUserQuestion
args: "[--fix] [--dry-run] [--plugin <name>]"
argument-hint: "[--fix] [--dry-run] [--plugin <name>]"
name: health-plugins
---

# Orphaned-Entry Diagnostic and Repair Scripts

Run the bundled registry diagnostic and repair scripts: find orphaned and stale entries, remove them with a backup, and install a plugin into the current project. For what the registry holds, how scopes resolve, and the #14202 background, use `health-plugin:plugin-registry`.

This skill is model-invoked only (`user-invocable: false`). The user-facing entry point is `/health:check --scope=registry`, with `--fix` to apply repairs; it runs the same bundled scripts.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Running the orphan/stale-entry diagnostic or its fix script | Comprehensive health check (`/health:check`) |
| Diagnosing project-scope vs global plugin issues | Auditing plugins for relevance (`health-plugin:health-audit`) |
| Cleaning up orphaned plugin entries | Settings validation only (`health-plugin:settings-configuration`) |
| Resolving "plugin already installed" errors | Agentic optimization audit (`health-plugin:health-agentic-audit`) |
| A project runs an older plugin version than the user install | Registry structure and field reference (`health-plugin:plugin-registry`) |

## Context

- Current project: !`pwd`
- Current project has plugins: !`find . -maxdepth 2 -path '*/.claude-plugin/plugin.json' -type f`
- Project settings exists: !`find . -maxdepth 2 -path './.claude/settings.json' -type f`
- Project plugins dir: !`find . -maxdepth 1 -type d -name '.claude-plugin'`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Description |
|-----------|-------------|
| `--fix` | Apply fixes to the plugin registry |
| `--dry-run` | Show what would be fixed without making changes |
| `--plugin <name>` | Check/fix a specific plugin only |

## Execution

Execute this plugin registry diagnostic with the bundled scripts. Both default `--home-dir` to `$HOME` and `--project-dir` to the current directory, so pass only the flags taken from `$ARGUMENTS`. Run each script exactly as spelled in the steps, so the `allowed-tools` rule pre-approves it.

### Step 1: Diagnose the registry

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-registry.sh [--plugin <name>] [--verbose]
```

Parse the `STATUS=`, `PLUGIN_COUNT=`, `ORPHANED_ENTRIES=`, and `ISSUES:` lines from output. The `=== PLUGINS ===` section lists each installed plugin with scope, version, source, and projectPath.

### Step 2: Report findings

Print a structured diagnostic report summarising:

1. Registry location, validity, and plugin counts (total / global / project-scoped)
2. Orphaned entries (projectPath directory missing) with severity and suggested fix
3. Plugins enabled in settings but not in the registry
4. Plugins from other projects (INFO only, shown with `--verbose`)

Use the `ISSUES:` lines as the authoritative list of problems.

### Step 3: Apply fixes (if --fix)

If `$ARGUMENTS` contains `--fix`:

1. Confirm with the user (via `AskUserQuestion`) which orphaned plugins to remove, unless `--dry-run` is also set.
2. Run the fix script:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/fix-registry.sh [--plugin <name>] [--dry-run]
   ```

   The script creates a timestamped backup at `~/.claude/plugins/installed_plugins.json.backup.<UTC-timestamp>` before modifying the registry, validates the resulting JSON, and aborts safely on any error.
3. Parse `STATUS=`, `REMOVED=`, `REMOVED_COUNT=`, and `BACKUP_PATH=` lines to report what changed.
4. **Surface durability warnings.** If the output includes `SETTINGS_CHEZMOI_MANAGED=true`, relay the `WARNING=` line to the user: the edited `~/.claude/settings.json` is chezmoi-managed, so the fix reverts on the next `chezmoi apply` unless the same key is also removed from the chezmoi source (printed as `SETTINGS_CHEZMOI_SOURCE=`).

### Step 4: Handle "plugin needed in current project"

When a plugin exists in the registry under a different `projectPath` and the user wants it in the current project:

1. Confirm with `AskUserQuestion`, naming the scope: `project` records the plugin in the committed `.claude/settings.json` for everyone who clones the repo; `local` records it in `.claude/settings.local.json` for this user only; `user` covers every project on this machine.
2. Run the install from the project directory with the chosen scope:

   ```bash
   claude plugin install <plugin>@<marketplace> --scope project
   ```

3. Verify the side effect, not the message: `claude plugin list --json` must show a row for the plugin whose `scope` is the chosen one and whose `projectPath` is the current directory (for `project` and `local`).
4. If the install reports the plugin as already installed and no such row exists, that is the upstream #14202 symptom (background in `health-plugin:plugin-registry`). Report it, and point to the last-resort registry edit in `health-plugin:plugin-registry` (§ Last resort: edit the registry by hand) rather than editing the registry from this skill.

### Step 5: Verify the fix

After applying fixes, re-run Step 1 and confirm the issue count has dropped. Tell the user to run `/reload-plugins` or start a new session for the changes to load.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Registry diagnostics (user-facing) | `/health:check --scope=registry` |
| Fix registry issues (user-facing) | `/health:check --scope=registry --fix` |
| Dry-run (user-facing) | `/health:check --scope=registry --fix --dry-run` |
| Diagnose only (script) | `bash ${CLAUDE_SKILL_DIR}/scripts/check-registry.sh` |
| Fix only (script) | `bash ${CLAUDE_SKILL_DIR}/scripts/fix-registry.sh` |
| Installs per scope | `claude plugin list --json` |

## See Also

- `/health:check` — full diagnostic scan; `--scope=registry` runs this skill's scripts
- `health-plugin:plugin-registry` — registry structure, install scopes, version lag, issue #14202, last-resort manual edits
- `health-plugin:settings-configuration` — settings hierarchy and permission patterns
