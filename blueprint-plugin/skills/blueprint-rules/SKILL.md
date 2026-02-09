---
model: haiku
created: 2025-12-17
modified: 2026-02-09
reviewed: 2026-02-09
description: "Manage modular rules in .claude/rules/ directory. Supports path-specific rules with glob patterns, brace expansion, and user-level rules."
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
name: blueprint-rules
---

Manage modular rules for the project. Rules are markdown files in `.claude/rules/` that provide context-specific instructions to Claude.

## Rules Hierarchy (precedence low → high)

| Level | Location | Scope |
|-------|----------|-------|
| User-level | `~/.claude/rules/*.md` | Personal rules across all projects |
| Project rules | `.claude/rules/*.md` (no `paths`) | All files in this project |
| Path-specific rules | `.claude/rules/*.md` (with `paths`) | Only matched files |

Project rules override user-level rules. Path-specific rules load conditionally when working on matching files.

**Steps**:

1. **Check blueprint status**:
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

2. **Determine action** (use AskUserQuestion):
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

3. **List existing rules**:
   - Scan `.claude/rules/` recursively for `.md` files
   - Scan `~/.claude/rules/` for user-level rules
   - Parse frontmatter for `paths` field (if scoped)
   - Display:
     ```
     📜 Modular Rules

     User-Level Rules (~/.claude/rules/ — personal, all projects):
     - preferences.md - Personal coding style
     - workflow.md - Personal workflow habits

     Project Global Rules (apply to all files):
     - development.md - TDD workflow and conventions
     - testing.md - Test requirements

     Project Scoped Rules (apply to specific paths):
     - frontend/react.md - paths: ["src/components/**/*.{ts,tsx}"]
     - backend/api.md - paths: ["src/api/**/*.ts"]

     Total: 6 rules (2 user-level, 2 global, 2 scoped)
     ```

4. **Add a new rule** (use AskUserQuestion):
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

5. **Rule file templates**:

   **Global rule template**:
   ```markdown
   # {Rule Name}

   ## Overview
   {Brief description of when this rule applies}

   ## Requirements
   - {Requirement 1}
   - {Requirement 2}

   ## Examples
   {Code examples if applicable}
   ```

   **Scoped rule template** (with `paths` frontmatter):
   ```markdown
   ---
   paths:
     - "src/components/**/*.{ts,tsx}"
   ---

   # {Rule Name}

   ## Overview
   {Brief description - applies only to matched paths}

   ## Requirements
   - {Requirement 1}
   - {Requirement 2}
   ```

   Brace expansion is supported: `*.{ts,tsx}` matches both `.ts` and `.tsx` files.
   Glob patterns follow standard syntax: `**` for recursive, `*` for single level.

6. **Generate rules from PRDs**:
   - Read all PRDs in `docs/prds/`
   - Extract key requirements and constraints
   - Group by domain (testing, architecture, coding standards)
   - Generate rule files:
     - `rules/from-prd-testing.md` - Test requirements from PRDs
     - `rules/from-prd-architecture.md` - Architecture decisions
     - `rules/from-prd-conventions.md` - Coding conventions

7. **Sync rules with CLAUDE.md**:
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

8. **Validate rules**:
   - Check for syntax errors in frontmatter
   - Validate glob patterns in `paths` field
   - Check for conflicting rules
   - Warn about overly broad or narrow scopes
   - Report:
     ```
     ✅ Rule Validation

     Checked: 4 rules
     Valid: 4
     Warnings: 1
       - frontend/react.md: paths pattern may be too broad

     No errors found.
     ```

9. **Update manifest**:
   - Add created/modified rules to `generated_artifacts.rules`
   - Update `updated_at` timestamp

10. **Report**:
    ```
    ✅ Rule management complete!

    {Action summary}

    Current rules: {count} files
    - Global: {count}
    - Scoped: {count}

    Run `/blueprint-status` to see full configuration.
    ```

11. **Prompt for next action** (use AskUserQuestion):
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

**Common Rule Patterns**:

| Rule Type | Suggested Path | Scope Pattern |
|-----------|---------------|---------------|
| React components | `rules/frontend/react.md` | `["**/*.{tsx,jsx}"]` |
| API handlers | `rules/backend/api.md` | `["src/{api,routes}/**/*"]` |
| Database models | `rules/backend/models.md` | `["src/{models,db}/**/*"]` |
| Test files | `rules/testing.md` | `["**/*.{test,spec}.*"]` |
| Documentation | `rules/docs.md` | `["**/*.md", "docs/**/*"]` |
| Config files | `rules/config.md` | `["*.config.{js,ts,mjs}", ".env*"]` |
