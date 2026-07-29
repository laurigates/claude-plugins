---
name: plugin-authoring
description: Add, modify, or delete a skill or plugin in this repo — frontmatter shape, the seven metadata files a plugin touches, and the create/delete checklists. Use when creating a new skill or plugin, removing one, or asking which files a plugin change must update.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(mkdir *), Bash(jq *), Bash(git log *), Bash(bash scripts/check-docs-index.sh *), Bash(bash scripts/plugin-compliance-check.sh *), TodoWrite
argument-hint: (no args)
created: 2026-07-29
modified: 2026-07-29
reviewed: 2026-07-29
---

# /plugin-authoring

The authoring procedures for this marketplace: how to create a skill, how to
create a plugin, what to update when either changes, and how to delete one
without leaving dangling metadata.

Promoted out of `CLAUDE.md` (issue #2140) because all four are **procedures with
a clear trigger** — they do not need to be resident when the user is debugging a
hook. `CLAUDE.md` keeps only the repo blurb, the rules index, and the gotchas.

Detailed patterns live in the rules this skill names; it is the sequence, not a
second copy of them.

## Creating New Skills

See `.claude/rules/skill-development.md` for detailed patterns.

> **Note (Claude Code 2.1.157):** plugins placed in `.claude/skills` are now auto-loaded without a marketplace entry — handy for local or quick one-off plugins. This repo's *published* plugins still use the full marketplace + release-please lifecycle described in Plugin Lifecycle below.

### Quick Start

1. Create skill directory: `mkdir -p <plugin>/skills/<skill-name>`
2. Create `skill.md` with YAML frontmatter:
   ```yaml
   ---
   name: <Skill Name>
   description: <1-2 sentence description>
   allowed-tools: Bash, Read, Grep, Glob, TodoWrite
   created: YYYY-MM-DD
   modified: YYYY-MM-DD
   reviewed: YYYY-MM-DD
   ---
   ```
3. Follow content structure: Core Expertise → Commands → Patterns → Quick Reference
4. Include agentic optimizations table
5. Update all metadata files (see Plugin Lifecycle section)

### Skill Granularity Decision

| Choose... | When... |
|-----------|---------|
| Single skill | Operations are related and share context |
| Multiple skills | Distinct workflows, different user intents |

Example: `bun-package-manager` (deps) vs `bun-development` (run/test/build)

## Creating User-Invocable Skills

Skills are invocable via `/plugin:skill-name` syntax. See `.claude/rules/skill-naming.md` for naming conventions.

1. Create skill directory: `mkdir -p <plugin>/skills/<skill-name>`
2. Create `SKILL.md` with YAML frontmatter:
   ```yaml
   ---
   name: <skill-name>
   description: What it does. Use when...
   args: <arg-spec>
   allowed-tools: Bash, Read
   argument-hint: human hint
   created: YYYY-MM-DD
   modified: YYYY-MM-DD
   reviewed: YYYY-MM-DD
   ---
   ```
3. Include: Context → Execution → Post-actions

## Plugin Lifecycle

### Files to Update

When creating, modifying, or deleting a plugin, update these files:

| File | Location | Action |
|------|----------|--------|
| `plugin.json` | `<plugin>/.claude-plugin/plugin.json` | Create/update plugin manifest |
| `README.md` | `<plugin>/README.md` | Create/update plugin documentation |
| `marketplace.json` | `.claude-plugin/marketplace.json` | Add/update/remove plugin entry |
| `release-please-config.json` | Root | Add/remove plugin package config |
| `.release-please-manifest.json` | Root | Add/remove plugin version entry |
| `PLUGIN-MAP.md` | `docs/PLUGIN-MAP.md` | Add/remove plugin from navigation map |
| `settings.json` | `.claude/settings.json` | Add/remove the plugin in `enabledPlugins` (`<plugin>@laurigates-claude-plugins`) — enforced by the `Plugin: Enablement drift` check |

### Creating a New Plugin

> **Quick scaffold (Claude Code 2.1.157):** `claude plugin init <name>` scaffolds a new plugin in `.claude/skills` (auto-loaded, no marketplace entry needed). Use it for local/quick plugins; for plugins published from this repo, follow the full marketplace + release-please steps below.

1. Create plugin directory structure (see Project Structure in `CLAUDE.md`)
2. Create `.claude-plugin/plugin.json` with required fields
3. Create `README.md` with plugin documentation
4. Add entry to `.claude-plugin/marketplace.json` (under the `plugins` array):
   ```json
   {
     "name": "new-plugin",
     "source": "./new-plugin",
     "description": "Plugin description",
     "version": "1.0.0",
     "keywords": ["keyword1", "keyword2"],
     "category": "category-name"
   }
   ```
   Note: marketplace.json has structure `{ "name": "...", "plugins": [...] }` — add to the `plugins` array.
5. Add to `release-please-config.json`:
   ```json
   "new-plugin": {
     "component": "new-plugin",
     "release-type": "simple",
     "extra-files": [
       {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}
     ],
     "changelog-sections": [
       {"type": "feat", "section": "Features"},
       {"type": "fix", "section": "Bug Fixes"},
       {"type": "perf", "section": "Performance"},
       {"type": "refactor", "section": "Code Refactoring"},
       {"type": "docs", "section": "Documentation"}
     ]
   }
   ```
6. Add to `.release-please-manifest.json`:
   ```json
   "new-plugin": "1.0.0"
   ```
7. Enable it in `.claude/settings.json` so the repo dogfoods it:
   ```json
   "enabledPlugins": { "new-plugin@laurigates-claude-plugins": true }
   ```
   The `Plugin: Enablement drift` check (`scripts/check-enabled-plugins-drift.sh`) fails CI if a marketplace plugin is left disabled.

### Deleting a Plugin

1. Remove plugin directory
2. Remove entry from `.claude-plugin/marketplace.json`
3. Remove package from `release-please-config.json`
4. Remove version from `.release-please-manifest.json`
5. Remove the `<plugin>@laurigates-claude-plugins` key from `.claude/settings.json` `enabledPlugins`

## Development Workflow

1. **Research documentation** - Use context7, web search
2. **Plan skill structure** - Decide granularity, scope
3. **Write skills** - Follow standard structure
4. **Update all metadata files** - See Plugin Lifecycle section
5. **Commit early** - Use conventional commit format (see `.claude/rules/conventional-commits.md`)
6. **Test** - Verify skills load and work
7. **Create PR** - Use conventional commit format for title (drives automation)

## Verify

After a plugin add or delete, the two guards that catch dangling metadata:

```
bash scripts/check-docs-index.sh
bash scripts/plugin-compliance-check.sh
```

`check-docs-index.sh` cross-checks the plugin set and per-plugin skill/agent
counts against disk across `README.md`, `docs/PLUGIN-MAP.md`, and the d2
diagram — use `/docs-refresh` to repair count drift it reports.

## Related

- `.claude/rules/skill-development.md` — skill creation patterns
- `.claude/rules/skill-naming.md` — namespace conventions for user-invocable skills
- `.claude/rules/skill-quality.md` — size limits, required sections, quality checklist
- `.claude/rules/plugin-structure.md` — plugin.json schema and directory layout
- `.claude/rules/release-please.md` — version management and changelog automation
- `.claude/rules/conventional-commits.md` — the commit/PR-title format that drives release-please
- `.claude/rules/skill-consolidation.md` — merging or deleting skills (distinct from the plugin-level checklist here)
- `/docs-refresh` — repairs catalog count drift after a skill or plugin lands
