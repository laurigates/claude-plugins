# Migration Plan: Commands to Skills

Since Claude Code 2.1.7+ unified commands and skills, we can consolidate all `commands/*.md` files into `skills/<name>/SKILL.md`. This simplifies the plugin structure: one mechanism instead of two.

## Why Migrate

- **Unified system**: Both already use `/name` syntax and share the same invocation path
- **Skills are a superset**: Skills support directories (supporting files, templates), auto-discovery by context, and user/Claude invocation control
- **Simpler structure**: Plugins have one `skills/` directory instead of both `commands/` and `skills/`
- **Existing commands keep working** but maintaining two patterns adds cognitive overhead

## Scope

**46 command files across 11 plugins** need conversion:

| Plugin | Commands | Existing Skills | Notes |
|--------|----------|-----------------|-------|
| blueprint-plugin | 22 | 6 | Largest command set |
| configure-plugin | 34 | 4 | Largest overall (commands in subdirs) |
| testing-plugin | 8 | 6 | Commands in `test/` subdir |
| typescript-plugin | 7 | 4 | Commands in `bun/` subdir |
| git-plugin | 6 | 21 | Commands in `git/` subdir |
| finops-plugin | 5 | 2 | Flat commands |
| project-plugin | 5 | 2 | Mixed flat/subdir; 1 duplicate |
| command-analytics-plugin | 4 | 0 | Flat commands |
| code-quality-plugin | 6 | 7 | Mixed flat/subdir |
| agent-patterns-plugin | 5 | 5 | Flat + subdir |
| tools-plugin | 3 | 11 | Flat commands |
| home-assistant-plugin | 1 | 3 | Flat command |
| blog-plugin | 1 | 1 | Flat command |
| api-plugin | 1 | 1 | Flat command |
| langchain-plugin | 1 | 1 | Flat command |
| agents-plugin | 1 | 0 | Flat command |
| container-plugin | 2 | 2 | In `deploy/` subdir |
| documentation-plugin | 4 | 1 | In `docs/` subdir |
| github-actions-plugin | 2 | 6 | In `workflow/` subdir |
| health-plugin | 4 | 1 | In `health/` subdir |
| component-patterns-plugin | 1 | 1 | In `components/` subdir |

## Duplicate Resolution

One confirmed duplicate:

| Plugin | Command | Skill | Resolution |
|--------|---------|-------|------------|
| project-plugin | `changelog-review.md` | `changelog-review/SKILL.md` | Delete command, keep skill |

All other command-skill pairs are **complementary** (different scope/purpose) - both should be kept.

## Frontmatter Conversion

Command frontmatter fields map to skill frontmatter:

| Command Field | Skill Field | Notes |
|---------------|-------------|-------|
| `description` | `description` | Expand with trigger phrases for discovery |
| `args` | `args` | Keep as-is (skills support args too) |
| `argument-hint` | `argument-hint` | Keep as-is |
| `allowed-tools` | `allowed-tools` | Keep as-is |
| `model` | `model` | Keep as-is |
| `created` | `created` | Keep as-is |
| `modified` | `modified` | Update to migration date |
| `reviewed` | `reviewed` | Update to migration date |
| _(missing)_ | `name` | **Add**: derive from filename (kebab-case) |

### Example Conversion

**Before** (`commands/finops-overview.md`):
```yaml
---
model: haiku
description: Quick FinOps summary - org billing and current repo workflow/cache stats
args: "[org]"
allowed-tools: Bash(gh api *), Bash(gh repo *), Bash(gh workflow *), Read, TodoWrite
argument-hint: Optional org name (defaults to current repo's org)
created: 2025-01-30
modified: 2025-01-30
reviewed: 2025-01-30
---
```

**After** (`skills/finops-overview/SKILL.md`):
```yaml
---
model: haiku
name: finops-overview
description: |
  Quick FinOps summary - org billing and current repo workflow/cache stats.
  Use when user says "show costs", "billing overview", "workflow spending",
  or "finops summary".
args: "[org]"
allowed-tools: Bash(gh api *), Bash(gh repo *), Bash(gh workflow *), Read, TodoWrite
argument-hint: Optional org name (defaults to current repo's org)
created: 2025-01-30
modified: 2026-02-06
reviewed: 2026-02-06
---
```

## Phase 1: Core Documentation Updates

Update rules and project docs to reflect the unified model.

### Files to Update

| File | Changes |
|------|---------|
| `CLAUDE.md` | Remove `commands/` from project structure; update "Creating Commands" section to reference skills |
| `.claude/rules/command-naming.md` | Rename to `skill-naming.md`; update all "command" references to "skill"; update file path conventions |
| `.claude/rules/skill-development.md` | Remove "Command File Structure" section (lines 151-190); merge relevant command info into skill section |
| `.claude/rules/plugin-structure.md` | Remove `commands/` from directory layout diagram |
| `.claude/rules/skill-quality.md` | Remove command line limit (300 lines); all are skills now |
| `MIGRATION.md` | Add note about commands→skills consolidation |

## Phase 2: Plugin-by-Plugin Command Migration

For each plugin, in priority order:

### Migration Steps per Plugin

1. **For each command file** `commands/<name>.md`:
   - Create `skills/<name>/SKILL.md`
   - Convert frontmatter (add `name` field, expand `description`)
   - Move content unchanged (body is compatible)
   - Delete original command file
2. **Remove empty `commands/` directory**
3. **Update plugin `README.md`**:
   - Move entries from "Commands" table to "Skills" table
   - Update file path references
4. **Handle subdirectory commands** (`commands/group/name.md`):
   - Flatten into `skills/<group>-<name>/SKILL.md`
   - e.g., `commands/test/run.md` → `skills/test-run/SKILL.md`

### Plugin Migration Order

**Batch 1** - Small plugins (1-3 commands, low risk):
1. home-assistant-plugin (1 command)
2. blog-plugin (1 command)
3. api-plugin (1 command)
4. langchain-plugin (1 command)
5. agents-plugin (1 command)
6. tools-plugin (3 commands)
7. container-plugin (2 commands)
8. github-actions-plugin (2 commands)

**Batch 2** - Medium plugins (4-8 commands):
10. command-analytics-plugin (4 commands)
11. finops-plugin (5 commands)
12. project-plugin (5 commands, handle duplicate)
13. agent-patterns-plugin (5 commands)
14. health-plugin (4 commands)
15. documentation-plugin (4 commands)
16. code-quality-plugin (6 commands)
17. git-plugin (6 commands)
18. component-patterns-plugin (1 command)

**Batch 3** - Large plugins (7+ commands):
19. typescript-plugin (7 commands)
20. testing-plugin (8 commands)
21. blueprint-plugin (22 commands)
22. configure-plugin (34 commands)

## Phase 3: Cross-Reference Updates

### SlashCommand Invocations (5 files)

These files invoke other commands via `SlashCommand` tool. The invocation syntax (`/name`) stays the same since skills use the same `/name` pattern - **no changes needed** for SlashCommand calls.

| File | References | Action |
|------|-----------|--------|
| `project-plugin/commands/project/init.md` | `/setup:new-project`, `/git:smartcommit`, `/deps:install` | Will be migrated to skill in Phase 2; references stay valid |
| `code-quality-plugin/commands/refactor.md` | `/lint:check --fix`, `/test:run` | Will be migrated to skill in Phase 2; references stay valid |
| `testing-plugin/commands/test/setup.md` | `/test:run`, `/lint:check` | Will be migrated to skill in Phase 2; references stay valid |

### README.md Files (23 plugins)

Every plugin with commands has README.md references. Update format:

**Before:**
```markdown
## Commands

| Command | Description |
|---------|-------------|
| `/finops:overview` | Quick FinOps summary |
```

**After:**
```markdown
## Skills

| Skill | Type | Description |
|-------|------|-------------|
| `finops-overview` | User-invocable | Quick FinOps summary |
| `github-actions-finops` | Auto-discovered | FinOps analysis expertise |
```

### Internal Cross-References in Skills

Skills that mention commands in their content:

| Skill File | References | Action |
|------------|-----------|--------|
| `blueprint-plugin/skills/blueprint-development/SKILL.md` | Blueprint commands | Update to reference skills |
| `agent-patterns-plugin/skills/command-context-patterns/SKILL.md` | Command patterns | Update terminology |
| `health-plugin/skills/plugin-registry/SKILL.md` | Health commands | Update to reference skills |
| `testing-plugin/skills/test-tier-selection/SKILL.md` | Test commands | Update to reference skills |

## Phase 4: Cleanup

1. **Delete all empty `commands/` directories**
2. **Update `release-please-config.json`** if any command-specific paths exist
3. **Update `.github/workflows/skill-quality-review.yml`** if it references `commands/`
4. **Final grep for "commands/"** across codebase to catch remaining references
5. **Verify all `/name` invocations still work** by listing discovered skills

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Broken `/name` invocations | Low | Medium | Skills use same `/name` syntax |
| Lost command args support | None | - | Skills support `args` field |
| Duplicate skill names after migration | Low | Medium | Check for name collisions before moving |
| Git history fragmentation | Certain | Low | Use `git mv` where possible; one commit per plugin |

## Name Collision Check

Before migrating, verify no command name collides with an existing skill name in the same plugin:

| Plugin | Command Name | Existing Skill? | Collision? |
|--------|-------------|-----------------|------------|
| project-plugin | `changelog-review` | `changelog-review/SKILL.md` | **YES** - delete command |
| git-plugin | `git/commit` → `git-commit` | `git-commit/skill.md` | **YES** - merge or keep skill |
| All others | - | - | No collisions |

For `git-plugin/git/commit`: The command is a full workflow (commit+push+PR) while the skill is local-commit-only. Options:
- **Option A**: Rename migrated command skill to `git-commit-workflow` (matches existing `git-commit-workflow/SKILL.md` - another collision)
- **Option B**: Rename to `git-full-commit` or `git-commit-push-pr`
- **Option C**: Merge command content into existing `git-commit-workflow/SKILL.md` (already exists)
- **Recommended**: Option C - merge into `git-commit-workflow/SKILL.md` since it covers the same broader workflow

## Commit Strategy

One conventional commit per plugin migration:
```
refactor(plugin-name): migrate commands to skills

Move commands/*.md to skills/<name>/SKILL.md
Update README.md skill tables
Remove empty commands/ directory
```

Final commit for documentation:
```
docs: update rules and project docs for commands-to-skills migration

Update CLAUDE.md, command-naming.md → skill-naming.md,
skill-development.md, plugin-structure.md
```
