---
created: 2025-12-17
modified: 2026-09-23
reviewed: 2026-02-09
description: CLAUDE.md and CLAUDE.local.md from blueprint artifacts. Use when editing CLAUDE.md team instructions, converting inline content to @imports, or setting up CLAUDE.local.md.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
name: blueprint-claude-md
---

Generate or update the project's CLAUDE.md file based on blueprint artifacts, PRDs, and project structure.

Branch-specific detail lives in `references/`, split by the path that needs it — an invocation opens only the file for the branch it takes.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Need to create/update CLAUDE.md for team instructions | Use `/blueprint:rules` for path-specific rules |
| Want to add @imports to existing CLAUDE.md | Use `/blueprint:generate-rules` to create rules from PRDs |
| Need to create CLAUDE.local.md for personal preferences | Editing individual rule files directly |
| Converting inline content to lean @import structure | Just need to view current memory configuration |

## CLAUDE.md vs Auto Memory

Claude Code has two complementary systems for project context. CLAUDE.md should contain **team-shared instructions** — not patterns Claude learns on its own.

| Belongs in CLAUDE.md | Belongs in Auto Memory (managed by Claude) |
|----------------------|---------------------------------------------|
| Team coding standards | Debugging insights and workarounds |
| Build/test/lint commands | Personal workflow preferences |
| Architecture decisions | Project-specific patterns learned over time |
| Required conventions | File relationships and navigation shortcuts |
| CI/CD workflows | Common mistakes and how to fix them |

Auto memory lives at `~/.claude/projects/<project>/memory/` and is managed automatically. Do not duplicate auto memory concerns into CLAUDE.md.

## Memory Hierarchy (precedence low → high)

1. **User-level rules**: `~/.claude/rules/` — personal rules across all projects
2. **CLAUDE.md (project)**: Team-shared project instructions (checked into git)
3. **CLAUDE.local.md**: Personal project-specific preferences (gitignored)
4. **.claude/rules/**: Modular, path-specific rules
5. **Managed policy**: Organization-wide instructions (enterprise, system paths)
6. **Auto memory**: Claude's own notes (`~/.claude/projects/<project>/memory/`)

## @import Syntax

CLAUDE.md files support importing other markdown files to stay lean:

```markdown
# Project: MyApp

@docs/architecture.md
@docs/conventions.md
@.claude/rules/testing.md
```

- Paths are relative to the file containing the import
- Recursive imports supported (max depth 5)
- Imports are not evaluated inside code spans or code blocks
- First-time external imports trigger an approval dialog

Use `@import` to reference existing documentation rather than duplicating content into CLAUDE.md.

## CLAUDE.md Best Practices

- Keep it concise (< 500 lines ideally)
- Focus on team-shared instructions (standards, commands, architecture)
- Use `@import` to reference existing docs instead of duplicating content
- Use `CLAUDE.local.md` for personal preferences (auto-gitignored)
- Reference `.claude/rules/` for detailed, path-specific rules
- Let auto memory handle "Current Focus", "Key Files", debugging tips
- Update when PRDs change significantly

## Execution

Execute this CLAUDE.md workflow:

### Step 1: Check current state

- Look for existing `CLAUDE.md` in project root
- Look for existing `CLAUDE.local.md` (personal preferences, gitignored)
- Read `docs/blueprint/manifest.json` for configuration
- Check for `~/.claude/rules/` (user-level rules)
- Determine `claude_md_mode` (single, modular, or both)

### Step 2: Determine action

Use AskUserQuestion:

```
{If CLAUDE.md exists:}
question: "CLAUDE.md already exists. What would you like to do?"
options:
  - "Update with latest project info" → merge updates
  - "Regenerate completely" → overwrite (backup first)
  - "Add missing sections only" → append new content
  - "Add @imports for existing docs" → replace inline content with imports
  - "Convert to modular rules" → split into .claude/rules/
  - "Create CLAUDE.local.md" → personal preferences (gitignored)
  - "View current structure" → analyze and display

{If CLAUDE.md doesn't exist:}
question: "No CLAUDE.md found. How would you like to create it?"
options:
  - "Generate from project analysis" → auto-generate
  - "Generate from PRDs" → use blueprint PRDs
  - "Generate with @imports (lean)" → auto-generate using imports for existing docs
  - "Start with template" → use starter template
  - "Use modular rules instead" → skip CLAUDE.md, use rules/
```

### Step 3: Gather project context

- **Project structure**: Detect language, framework, build tools
- **PRDs**: Read `docs/prds/*.md` for requirements
- **Work overview**: Current phase and progress
- **Existing rules**: Content from `.claude/rules/` if present
- **Git history**: Recent patterns and conventions
- **Dependencies**: Package managers, key libraries

### Step 4: Generate CLAUDE.md sections

Build the sections from [`references/template-sections.md`](references/template-sections.md): the standard skeleton, tailored with the per-project-type additions. Leave out what auto memory handles (see "CLAUDE.md vs Auto Memory" above).

### Step 5: Apply the modular rules mode

If modular rules mode is `both` or `modular`, follow the matching section of [`references/modular-rules-split.md`](references/modular-rules-split.md). Mode `single` skips this step.

### Step 6: Apply a selected option

- "Create CLAUDE.local.md" → [`references/template-sections.md`](references/template-sections.md) § CLAUDE.local.md template
- "Add @imports for existing docs" → [`references/smart-update.md`](references/smart-update.md) § Add @imports

### Step 7: Smart update (existing CLAUDE.md)

When CLAUDE.md already exists, follow [`references/smart-update.md`](references/smart-update.md) § Smart update.

### Step 8: Sync with modular rules

When `.claude/rules/` has rules, follow [`references/modular-rules-split.md`](references/modular-rules-split.md) § Sync with modular rules.

### Step 9: Update manifest and task registry

Record the run in `docs/blueprint/manifest.json` per [`references/manifest-and-registry.md`](references/manifest-and-registry.md).

### Step 10: Report

```
✅ CLAUDE.md updated!

{Created | Updated}: CLAUDE.md
{If created:} CLAUDE.local.md (personal preferences, gitignored)

Sections:
- Overview ✅
- Tech Stack ✅
- Development Workflow ✅
- Architecture ✅
- Conventions ✅

@imports used: {count, if any}
- @docs/prds/architecture.md
- @.claude/rules/testing.md

Sources used:
- PRDs: {list}
- Rules: {list}
- Project detection: {what was detected}

{If modular mode:}
Note: Detailed rules are in .claude/rules/
CLAUDE.md serves as overview and quick reference.

Note: "Current Focus" and "Key Files" are managed by Claude's
auto memory — no need to maintain these in CLAUDE.md.

Run `/blueprint:status` to see full configuration.
```

### Step 11: Prompt for next action

Use AskUserQuestion:

```
question: "CLAUDE.md updated. What would you like to do next?"
options:
  - label: "Check blueprint status (Recommended)"
    description: "Run /blueprint:status to verify configuration"
  - label: "Manage modular rules"
    description: "Add or edit rules in .claude/rules/"
  - label: "Continue development"
    description: "Run /project:continue to work on next task"
  - label: "I'm done for now"
    description: "Exit - CLAUDE.md is saved"
```

**Based on selection:**
- "Check blueprint status" → Run `/blueprint:status`
- "Manage modular rules" → Run `/blueprint:rules`
- "Continue development" → Run `/project:continue`
- "I'm done" → Exit
