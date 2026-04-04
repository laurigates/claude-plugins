---
name: plugin-settings
description: |
  Configure per-project plugin settings using `.claude/plugin-name.local.md` files.
  Use when building plugins that need user-configurable behavior, storing agent state
  between sessions, or controlling hook activation per-project. Covers file structure,
  YAML frontmatter parsing, gitignore setup, and common patterns like toggle-based
  hooks and agent state management.
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-03-06
modified: 2026-03-06
reviewed: 2026-03-06
---

# Plugin Settings Pattern

Per-project plugin configuration using `.claude/plugin-name.local.md` files with YAML frontmatter for structured settings and markdown body for additional context.

## When to Use This Skill

| Use plugin settings when... | Use alternatives when... |
|-----------------------------|--------------------------|
| Plugin needs per-project configuration | Settings are global (use `~/.claude/settings.json`) |
| Hooks need runtime enable/disable control | Hook behavior is always-on |
| Agent state persists between sessions | State is ephemeral within a session |
| Users customize plugin behavior per-project | Plugin has no configurable behavior |
| Configuration includes prose/prompts alongside structured data | All config is purely structured (use `.json`) |

## File Structure

### Location

```
project-root/
└── .claude/
    └── plugin-name.local.md    # Per-project, user-local settings
```

### Format

```markdown
---
enabled: true
mode: standard
max_retries: 3
allowed_extensions: [".js", ".ts", ".tsx"]
---

# Additional Context

Markdown body for prompts, instructions, or documentation
that hooks and agents can read and use.
```

### Naming Convention

- Use `.claude/plugin-name.local.md` format
- Match the plugin name exactly from `plugin.json`
- The `.local.md` suffix signals user-local (not committed to git)

### Gitignore

Add to project `.gitignore`:

```gitignore
.claude/*.local.md
```

## Reading Settings

### From Shell Scripts (Hooks)

Use the standard frontmatter extraction pattern from `.claude/rules/shell-scripting.md`:

```bash
#!/bin/bash
set -euo pipefail

STATE_FILE=".claude/my-plugin.local.md"

# Quick exit if not configured
[[ -f "$STATE_FILE" ]] || exit 0

# Extract field using standard pattern
extract_field() {
  local file="$1" field="$2"
  head -50 "$file" | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
}

plugin_enabled=$(extract_field "$STATE_FILE" "enabled")
[[ "$plugin_enabled" == "true" ]] || exit 0

plugin_mode=$(extract_field "$STATE_FILE" "mode")
```

### Extract Markdown Body

```bash
# Get content after the closing --- frontmatter delimiter
BODY=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")
```

### From Skills and Agents

Skills and agents read settings with the Read tool:

```markdown
1. Check if `.claude/my-plugin.local.md` exists
2. Read the file and parse YAML frontmatter
3. Apply settings to current behavior
4. Use markdown body as additional context/prompt
```

## Common Patterns

### Pattern 1: Toggle-Based Hook Activation

Control hook activation without editing `hooks.json`:

```bash
#!/bin/bash
set -euo pipefail
STATE_FILE=".claude/security-scan.local.md"
[[ -f "$STATE_FILE" ]] || exit 0

extract_field() {
  local file="$1" field="$2"
  head -50 "$file" | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
}

scan_enabled=$(extract_field "$STATE_FILE" "enabled")
[[ "$scan_enabled" == "true" ]] || exit 0

# Hook logic runs only when enabled
```

### Pattern 2: Agent State Between Sessions

Store agent task state for multi-session work:

```markdown
---
agent_name: auth-implementation
task_number: 3.5
pr_number: 1234
enabled: true
---

# Current Task

Implement JWT authentication for the REST API.
Coordinate with auth-agent on shared types.
```

### Pattern 3: Configuration-Driven Validation

```markdown
---
validation_level: strict
max_file_size: 1000000
allowed_extensions: [".js", ".ts", ".tsx"]
---
```

```bash
validation_level=$(extract_field "$STATE_FILE" "validation_level")
case "$validation_level" in
  strict)  run_strict_checks ;;
  standard) run_standard_checks ;;
  *)       run_standard_checks ;;  # Default
esac
```

## Implementation Checklist

When adding settings to a plugin:

1. Design settings schema (fields, types, defaults)
2. Create template in plugin README
3. Add `.claude/*.local.md` to `.gitignore`
4. Implement parsing using `extract_field` pattern
5. Use quick-exit pattern (`[[ -f "$STATE_FILE" ]] || exit 0`)
6. Provide sensible defaults when file is missing
7. Document that changes require Claude Code restart (hooks only)

## Best Practices

| Practice | Details |
|----------|---------|
| Quick exit | Check file existence first, exit 0 if absent |
| Sensible defaults | Provide fallback values when settings file is missing |
| Use `extract_field` | Standard frontmatter extraction from `shell-scripting.md` |
| Validate values | Check numeric ranges, enum membership |
| File permissions | Settings files should be user-readable only (`chmod 600`) |
| Restart notice | Document that hook-related changes need a Claude Code restart |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check settings exist | `[[ -f ".claude/plugin.local.md" ]]` |
| Extract single field | `head -50 file \| grep -m1 "^field:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| Extract body | `awk '/^---$/{i++; next} i>=2' file` |
| Quick enable check | `[[ "$(extract_field file enabled)" == "true" ]]` |
