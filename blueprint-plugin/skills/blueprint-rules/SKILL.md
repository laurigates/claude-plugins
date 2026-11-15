---
created: 2025-12-17
modified: 2026-11-15
reviewed: 2026-02-09
description: "Rule files in .claude/rules/: add, edit, list, or validate paths: frontmatter. Use when adding a path-scoped rule file, listing which rules load, or fixing rule globs."
allowed-tools: Read, Write, Edit, Glob, AskUserQuestion
name: blueprint-rules
---

Manage modular rules for the project. Rules are markdown files in `.claude/rules/` that provide context-specific instructions to Claude.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Need to create/edit modular rules in .claude/rules/ | Use `/blueprint:claude-md` for single-file project instructions |
| Want to list all project and user-level rules | Use `/blueprint:generate-rules` to auto-generate from PRDs |
| Need to add path-specific rules for certain file types | Just need to view CLAUDE.md structure |
| Managing user-level rules (~/.claude/rules/) | Need to sync rules with existing CLAUDE.md |

## Rules Hierarchy (precedence low → high)

| Level | Location | Scope |
|-------|----------|-------|
| User-level | `~/.claude/rules/*.md` | Personal rules across all projects |
| Project rules | `.claude/rules/*.md` (no `paths`) | All files in this project |
| Path-specific rules | `.claude/rules/*.md` (with `paths`) | Only matched files |

Project rules override user-level rules. Path-specific rules load conditionally when working on matching files.

## Execution

Execute this rule-management workflow. Steps 1 and 2 always run; Step 2 picks one action, which runs its own step (3, 4–5, 6, 7 or 8); Steps 9–11 close every action.

### Step 1: Check blueprint status

- Read `docs/blueprint/manifest.json`
- Check if modular rules are enabled
- If not enabled, offer to enable:
  ```
  Use AskUserQuestion:
  question: "Modular rules are not enabled. Would you like to enable them?"
  options:
    - "Yes, create .claude/rules/ structure" → enable and continue
    - "No, use single CLAUDE.md" → exit
  ```

### Step 2: Determine action (use AskUserQuestion)

```
question: "What would you like to do with modular rules?"
options:
  - "List existing rules" → show project and user-level rules
  - "Add a new rule" → create new rule file
  - "Edit existing rule" → modify rule
  - "Generate rules from PRDs" → auto-generate from requirements
  - "Manage user-level rules" → personal rules in ~/.claude/rules/
  - "Sync rules with CLAUDE.md" → bidirectional sync
  - "Validate rules" → check for issues
```

### Step 3: List existing rules

- Scan `.claude/rules/` recursively for `.md` files
- Scan `~/.claude/rules/` for user-level rules
- Parse frontmatter for `paths` field (if scoped)
- Display the rules grouped by level, in the layout in [references/list-display.md](references/list-display.md)

### Step 4: Add a new rule (use AskUserQuestion)

```
question: "What type of rule would you like to create?"
options:
  - "Development workflow" → development.md template
  - "Testing requirements" → testing.md template
  - "Code style/conventions" → code-style.md template
  - "Architecture patterns" → architecture.md template
  - "Language-specific" → prompt for language
  - "Framework-specific" → prompt for framework
  - "Custom" → blank template with guidance
```

Then ask:
```
question: "Should this rule apply to all files or specific paths?"
options:
  - "All files (global)" → no paths frontmatter
  - "Specific file patterns" → prompt for glob patterns
```

### Step 5: Write the rule file from its template

Write the rule from the global or the scoped (`paths` frontmatter) template in [references/rule-templates.md](references/rule-templates.md), which also lists suggested locations and `paths:` patterns for common rule types. Brace expansion is supported in `paths`: `*.{ts,tsx}` matches both `.ts` and `.tsx` files.

### Step 6: Generate rules from PRDs

- Read all PRDs in `docs/prds/`
- Extract key requirements and constraints
- Group by domain (testing, architecture, coding standards)
- Generate rule files:
  - `rules/from-prd-testing.md` - Test requirements from PRDs
  - `rules/from-prd-architecture.md` - Architecture decisions
  - `rules/from-prd-conventions.md` - Coding conventions

### Step 7: Sync rules with CLAUDE.md

- Parse existing CLAUDE.md sections
- Compare with rules in `.claude/rules/`
- Offer sync options:
  ```
  question: "How would you like to sync?"
  options:
    - "CLAUDE.md → rules (split into modular files)"
    - "Rules → CLAUDE.md (consolidate)"
    - "Merge both (combine unique content)"
  ```

### Step 8: Validate rules

- Check for syntax errors in frontmatter
- Validate glob patterns in `paths` field
- Check for conflicting rules
- Warn about overly broad or narrow scopes
- Report in the layout in [references/validation-report.md](references/validation-report.md)

### Step 9: Update manifest

- Add created/modified rules to `generated_artifacts.rules`
- Update `updated_at` timestamp

### Step 10: Report

```
✅ Rule management complete!

{Action summary}

Current rules: {count} files
- Global: {count}
- Scoped: {count}

Run `/blueprint:status` to see full configuration.
```

### Step 11: Prompt for next action (use AskUserQuestion)

```
question: "Rules updated. What would you like to do next?"
options:
  - label: "Update CLAUDE.md (Recommended)"
    description: "Regenerate overview to reflect rule changes"
  - label: "Add another rule"
    description: "Create additional domain-specific rules"
  - label: "Check blueprint status"
    description: "Run /blueprint:status to see full configuration"
  - label: "I'm done for now"
    description: "Exit - rules are active immediately"
```

**Based on selection:**
- "Update CLAUDE.md" → Run `/blueprint:claude-md`
- "Add another rule" → Restart at step 4 (Add a new rule)
- "Check blueprint status" → Run `/blueprint:status`
- "I'm done" → Exit
