---
model: opus
created: 2026-02-05
modified: 2026-02-10
reviewed: 2026-02-05
description: Audit enabled plugins against project tech stack and recommend additions/removals for relevance
allowed-tools: Bash(test *), Bash(find *), Bash(jq *), Bash(claude plugin *), Read, Write, Edit, Glob, Grep, TodoWrite, AskUserQuestion
argument-hint: "[--fix] [--dry-run] [--verbose]"
name: health-audit
---

# /health:audit

Audit the project's enabled plugins against the actual technology stack. Identifies plugins that don't apply to this project and suggests relevant plugins that aren't enabled.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Reviewing plugin relevance for current project | General health diagnostics (use `/health:check`) |
| Cleaning up unused plugins | Plugin registry corruption (use `/health:plugins --fix`) |
| Discovering relevant plugins for tech stack | Agentic optimization audit (use `/health:agentic-audit`) |
| Optimizing project-specific plugin configuration | Installing specific plugin (install directly) |
| Onboarding to existing project | Need comprehensive settings validation |

## Context

- Current project: !`pwd`
- Project settings exists: !`find .claude -maxdepth 1 -name 'settings.json' 2>/dev/null`
- Enabled plugins: !`jq -r '.enabledPlugins[]? // empty' .claude/settings.json 2>/dev/null`
- Package.json exists: !`find . -maxdepth 1 -name 'package.json' 2>/dev/null`
- Cargo.toml exists: !`find . -maxdepth 1 -name 'Cargo.toml' 2>/dev/null`
- pyproject.toml exists: !`find . -maxdepth 1 -name 'pyproject.toml' 2>/dev/null`
- requirements.txt exists: !`find . -maxdepth 1 -name 'requirements.txt' 2>/dev/null`
- go.mod exists: !`find . -maxdepth 1 -name 'go.mod' 2>/dev/null`
- Dockerfile exists: !`find . -maxdepth 1 -name 'Dockerfile' 2>/dev/null`
- docker-compose exists: !`find . -maxdepth 1 \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' \) 2>/dev/null`
- GitHub workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' 2>/dev/null -quit -print`
- Terraform files: !`find . -maxdepth 2 -name '*.tf' 2>/dev/null -quit -print`
- Kubernetes manifests: !`find . -maxdepth 3 \( -path '*/k8s/*' -o -path '*/kubernetes/*' \) -name '*.yaml' 2>/dev/null -quit -print`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Apply recommended changes to `.claude/settings.json` |
| `--dry-run` | Show what would be changed without modifying files |
| `--verbose` | Show detailed analysis of each plugin decision |

## Execution

Execute this plugin relevance audit:

### Step 1: Detect the project technology stack

Analyze project files from the context above to determine the technology stack. Match indicators against the tech stack mapping in [REFERENCE.md](REFERENCE.md).

### Step 2: Retrieve available plugins

Run `claude plugin list --json` to get all available plugins from configured marketplaces. Parse the output for plugin name, description, keywords, and category.

### Step 3: Read currently enabled plugins

Read `.claude/settings.json` and extract the `enabledPlugins` array. If the file does not exist or `enabledPlugins` is not set, treat as empty list.

### Step 4: Analyze plugin relevance

Compare each enabled plugin against the detected tech stack. Use the plugin relevance mapping in [REFERENCE.md](REFERENCE.md) to determine which plugins are relevant, irrelevant, or missing.

Categorize each plugin as:
- **RELEVANT** -- matches detected tech stack
- **NOT RELEVANT** -- no matching indicators found
- **MISSING** -- relevant plugin not currently enabled

### Step 5: Generate the audit report

Print a structured report covering:
1. Detected technology stack with evidence
2. Currently enabled plugins with relevance status
3. Suggested plugins to add (with reasons)
4. Suggested plugins to remove (with reasons)
5. Summary counts

### Step 6: Apply changes (if --fix)

When `--fix` is passed:

1. Back up current settings: `cp .claude/settings.json .claude/settings.json.backup`
2. Ask for confirmation before each category of changes (removals, additions)
3. Update `.claude/settings.json` -- remove confirmed irrelevant plugins, add confirmed relevant plugins, preserve other settings
4. Verify changes by re-reading the file, confirming valid JSON, and showing the diff

## User-Level vs Project-Level

Note: This command only manages **project-level** plugin settings in `.claude/settings.json`.

User-level plugins (in `~/.claude/settings.json`) are managed separately and don't need duplication at project level.

When analyzing, check if a plugin is already enabled at user level:
```bash
jq -r '.enabledPlugins[]? // empty' ~/.claude/settings.json 2>/dev/null
```

If a plugin is enabled at user level, it doesn't need to be in project settings unless you want project-specific behavior.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No `.claude/settings.json` | Create it with recommended plugins |
| Empty `enabledPlugins` | Suggest adding relevant plugins |
| Monorepo with multiple languages | Suggest all matching plugins |
| Plugin not in marketplace | Flag as "unknown" but don't remove |
| User declined changes | Respect decision, show manual instructions |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Plugin relevance audit | `/health:audit` |
| Audit with auto-fix | `/health:audit --fix` |
| Dry-run mode | `/health:audit --dry-run` |
| List enabled plugins | `jq -r '.enabledPlugins[]? // empty' .claude/settings.json 2>/dev/null` |
| Detect project languages | `find . -maxdepth 1 \( -name 'package.json' -o -name 'Cargo.toml' -o -name 'pyproject.toml' \) -exec basename {} \;` |

## Flags

| Flag | Description |
|------|-------------|
| `--fix` | Apply recommended changes (with confirmation) |
| `--dry-run` | Show what would be changed without modifying |
| `--verbose` | Show detailed reasoning for each decision |

## See Also

- `/health:plugins` - Fix plugin registry issues
- `/health:check` - Full diagnostic scan
- `/configure:claude-plugins` - Initial plugin setup
