---
created: 2026-02-05
modified: 2026-11-12
compatibility: claude-code
reviewed: 2026-11-12
user-invocable: false
description: "Plugin audit against detected stack (Python, Node, Rust, Go, Terraform, Docker, K8s). Use when cleaning up unused plugins or discovering stack-relevant ones for a project."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/enabled-plugins.sh *), Bash(claude plugin list *), Read, Glob, Grep, TodoWrite, AskUserQuestion
args: "[--fix] [--dry-run] [--verbose]"
argument-hint: "[--fix] [--dry-run] [--verbose]"
name: health-audit
---

# health-audit

The user-facing entry point is `/health:check --scope=stack`, with `--fix` to apply changes; this skill is model-invoked only (`user-invocable: false`).

Audit the project's enabled plugins against the actual technology stack. Identifies plugins that don't apply to this project and suggests relevant plugins that aren't enabled.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Reviewing plugin relevance for current project | General health diagnostics (use `/health:check`) |
| Cleaning up unused plugins | Plugin registry corruption (`/health:check --scope=registry --fix`) |
| Discovering relevant plugins for tech stack | Bare CLI commands in skill docs (`/health:check --scope=agentic`) |
| Optimizing project-specific plugin configuration | Installing specific plugin (install directly) |
| Onboarding to existing project | Need comprehensive settings validation |

## Context

- Current project: !`pwd`
- Project settings exists: !`find . -maxdepth 2 -path '*/.claude/settings.json'`
- Package.json exists: !`find . -maxdepth 1 -name 'package.json'`
- Cargo.toml exists: !`find . -maxdepth 1 -name 'Cargo.toml'`
- pyproject.toml exists: !`find . -maxdepth 1 -name 'pyproject.toml'`
- requirements.txt exists: !`find . -maxdepth 1 -name 'requirements.txt'`
- go.mod exists: !`find . -maxdepth 1 -name 'go.mod'`
- Dockerfile exists: !`find . -maxdepth 1 -name 'Dockerfile'`
- docker-compose exists: !`find . -maxdepth 1 \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' \)`
- GitHub workflows: !`find . -maxdepth 3 -path '*/.github/workflows/*' -name '*.yml' -print -quit`
- Terraform files: !`find . -maxdepth 2 -name '*.tf' -print -quit`
- Kubernetes manifests: !`find . -maxdepth 3 \( -path '*/k8s/*' -o -path '*/kubernetes/*' \) -name '*.yaml' -print -quit`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Apply recommended changes to `.claude/settings.json` |
| `--dry-run` | Show what would be changed without modifying files |
| `--verbose` | Show detailed analysis of each plugin decision |

## Execution

Execute this plugin relevance audit:

### Step 1: Detect the project technology stack

Analyze project files from the values in [Context](#context) to determine the technology stack. Match indicators against the tech stack mapping in [REFERENCE.md](REFERENCE.md).

### Step 2: Retrieve installed and available plugins

Run `claude plugin list --json --available`. It prints one object with two arrays:

- `installed` -- plugins already installed; each entry's `id` is `plugin-name@marketplace-name`, with `scope` and `version`
- `available` -- marketplace plugins that are not installed; each entry has `pluginId`, `name`, `description`, `marketplaceName` and `version`

The catalog is both arrays together: `available` leaves out what `installed` lists. Neither carries keywords or a category, so match on plugin name and description. Without `--available` the command lists installed plugins only. Field shapes are in [REFERENCE.md](REFERENCE.md#plugin-list-json).

### Step 3: Read the enabledPlugins settings

From the project root, run `bash ${CLAUDE_SKILL_DIR}/scripts/enabled-plugins.sh list`. `enabledPlugins` is an object mapping `plugin-name@marketplace-name` to `true` (enabled) or `false` (explicitly disabled), and the script reads it that way for user, project and local settings:

- `PROJECT_ENABLED=` / `PROJECT_DISABLED=` -- the entries in `.claude/settings.json`, the file this skill audits and `--fix` edits
- `USER_ENABLED=` / `LOCAL_ENABLED=` and their `_DISABLED=` twins -- the other scopes
- `EFFECTIVE_ENABLED=` -- IDs whose highest-precedence entry is `true` (local over project over user; managed settings are not read)

A missing file or an unset `enabledPlugins` means no entries. On `STATUS=ERROR` (a settings file is not valid JSON) report the file and stop. On `TYPE=not_object` (an `enabledPlugins` that is not an object) report it and skip `--fix` until it is corrected by hand.

### Step 4: Analyze plugin relevance

Compare each project entry against the detected tech stack. Use the plugin relevance mapping in [REFERENCE.md](REFERENCE.md) to determine which plugins are relevant, irrelevant, or missing.

Categorize each plugin as:
- **RELEVANT** -- in `PROJECT_ENABLED` and matches the detected stack
- **NOT RELEVANT** -- in `PROJECT_ENABLED` with no matching indicators
- **DISABLED** -- in `PROJECT_DISABLED`: a deliberate opt-out; list it, and do not suggest adding it back
- **MISSING** -- relevant to the stack and absent from `EFFECTIVE_ENABLED`; a plugin the user already enables at user or local scope is not missing

### Step 5: Generate the audit report

Print a structured report covering:
1. Detected technology stack with evidence
2. Currently enabled plugins with relevance status
3. Suggested plugins to add (with reasons)
4. Suggested plugins to remove (with reasons)
5. Summary counts

### Step 6: Apply changes (if --fix)

When `--fix` is passed:

1. Ask for confirmation of each category of changes (removals, additions) with `AskUserQuestion`.
2. Run `bash ${CLAUDE_SKILL_DIR}/scripts/enabled-plugins.sh apply --settings .claude/settings.json --enable <id> --remove <id>`, one flag per confirmed ID in `plugin-name@marketplace-name` form. The script copies the file to `.claude/settings.json.backup`, sets each `--enable` key to `true`, deletes each `--remove` key, keeps every other setting, and creates the file when it does not exist.
3. Remove by deleting the key, not by writing `false`: project settings take precedence over user settings, so a project `false` would turn the plugin off for every teammate who enables it themselves.
4. Verify by re-running `list` and report the `ENABLED=` and `REMOVED=` lines from the apply output.

With `--dry-run`, print the `apply` command you would run and stop.

## User-Level vs Project-Level

This skill writes only **project-level** plugin settings in `.claude/settings.json`.

Precedence runs local over project over user: a user-level `false` does not disable a plugin the project enables, and a developer who wants it off on one machine sets it to `false` in `.claude/settings.local.json`. The `list` output carries `USER_ENABLED=`; a plugin enabled there needs no project entry unless the whole team should have it.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No `.claude/settings.json` | `apply` creates it with the confirmed plugins |
| Empty or unset `enabledPlugins` | Suggest adding relevant plugins |
| Entry set to `false` in project settings | Report as DISABLED; leave it unless the user asks |
| `enabledPlugins` is not an object | Report `not_object`; skip `--fix` |
| Monorepo with multiple languages | Suggest all matching plugins |
| Enabled ID in neither `installed[].id` nor `available[].pluginId` | Flag as "unknown" but don't remove |
| User declined changes | Respect decision, show manual instructions |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Plugin relevance audit | `/health:check --scope=stack` |
| Audit with auto-fix | `/health:check --scope=stack --fix` |
| Dry-run mode | `/health:check --scope=stack --fix --dry-run` |
| Enabled plugins, all scopes | `bash ${CLAUDE_SKILL_DIR}/scripts/enabled-plugins.sh list` |
| Installed + marketplace catalog | `claude plugin list --json --available` |

## Flags

| Flag | Description |
|------|-------------|
| `--fix` | Apply recommended changes (with confirmation) |
| `--dry-run` | Show what would be changed without modifying |
| `--verbose` | Show detailed reasoning for each decision |

## See Also

- `health-plugin:health-plugins` - Plugin registry repair (user path: `/health:check --scope=registry --fix`)
- `/health:check` - Full diagnostic scan
- `/configure:claude-plugins` - Initial plugin setup
