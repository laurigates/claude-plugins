---
model: sonnet
created: 2025-12-17
modified: 2026-02-17
reviewed: 2026-02-09
description: "Generate or update CLAUDE.md from project context and blueprint artifacts. Supports @import syntax, CLAUDE.local.md, and auto memory delineation."
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
name: blueprint-claude-md
---

Generate or update the project's CLAUDE.md file based on blueprint artifacts, PRDs, and project structure.

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

**Steps**:

1. **Check current state**:
   - Look for existing `CLAUDE.md` in project root
   - Look for existing `CLAUDE.local.md` (personal preferences, gitignored)
   - Read `docs/blueprint/manifest.json` for configuration
   - Check for `~/.claude/rules/` (user-level rules)
   - Determine `claude_md_mode` (single, modular, or both)

2. **Determine action** (use AskUserQuestion):
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

3. **Gather project context**:
   - **Project structure**: Detect language, framework, build tools
   - **PRDs**: Read `docs/prds/*.md` for requirements
   - **Work overview**: Current phase and progress
   - **Existing rules**: Content from `.claude/rules/` if present
   - **Git history**: Recent patterns and conventions
   - **Dependencies**: Package managers, key libraries

4. **Generate CLAUDE.md sections**:

   **Standard sections** (focused on team-shared instructions):
   ```markdown
   # Project: {name}

   ## Overview
   {Brief project description from PRDs or detection}

   ## Tech Stack
   - Language: {detected}
   - Framework: {detected}
   - Build: {detected}
   - Test: {detected}

   ## Development Workflow

   ### Getting Started
   {Setup commands}

   ### Running Tests
   {Test commands}

   ### Building
   {Build commands}

   ## Architecture
   {Key architectural decisions from PRDs — or use @import:}
   @docs/prds/architecture-prd.md

   ## Conventions

   ### Code Style
   {Detected or from PRDs}

   ### Commit Messages
   {Conventional commits if detected}

   ### Testing Requirements
   {From PRDs or rules}

   ## See Also
   {If modular rules enabled:}
   - `.claude/rules/` - Detailed rules by domain
   - `docs/prds/` - Product requirements
   ```

   **Sections to omit** (auto memory handles these automatically):
   - "Current Focus" — Claude tracks this in auto memory
   - "Key Files" — Claude learns file relationships automatically
   - Debugging tips — Claude records these in auto memory topic files

5. **If modular rules mode = "both"**:
   - Keep CLAUDE.md as high-level overview
   - Reference `.claude/rules/` for details:
     ```markdown
     ## Detailed Rules
     See `.claude/rules/` for domain-specific guidelines:
     - `development.md` - Development workflow
     - `testing.md` - Testing requirements
     - `frontend/` - Frontend-specific rules
     - `backend/` - Backend-specific rules
     ```

6. **If modular rules mode = "modular"**:
   - Create minimal CLAUDE.md with `@import` references
   - Move detailed content to `.claude/rules/`
   - Example lean CLAUDE.md:
     ```markdown
     # Project: {name}

     ## Overview
     {One-paragraph description}

     @docs/prds/main.md

     ## Development
     {Build, test, lint commands}

     ## Rules
     See `.claude/rules/` for detailed guidelines.
     ```

6b. **If "Create CLAUDE.local.md" selected**:
   - Create `CLAUDE.local.md` in project root for personal preferences
   - Add `CLAUDE.local.md` to `.gitignore` if not already present
   - Template:
     ```markdown
     # Personal Preferences

     ## My Environment
     - IDE: {detected or ask}
     - Terminal: {detected or ask}

     ## My Workflow Preferences
     - {Personal conventions not shared with team}
     ```

6c. **If "Add @imports" selected**:
   - Scan existing CLAUDE.md for sections with content that exists in other files
   - Replace duplicated content with `@path/to/source.md` imports
   - Preserve CLAUDE.md-only content inline
   - Show diff of changes before applying

7. **Smart update** (for existing CLAUDE.md):
   - Parse existing sections
   - Identify outdated content (compare with PRDs, structure)
   - Offer section-by-section updates:
     ```
     question: "Found outdated sections. Which would you like to update?"
     options: [list of sections]
     allowMultiSelect: true
     ```

8. **Sync with modular rules**:
   - If rules exist in `.claude/rules/`
   - Detect duplicated content
   - Offer to deduplicate:
     ```
     question: "Found duplicate content between CLAUDE.md and rules/. How to resolve?"
     options:
       - "Keep in CLAUDE.md, remove from rules"
       - "Keep in rules, reference from CLAUDE.md"
       - "Keep both (may cause confusion)"
     ```

9. **Update manifest**:
   - Record CLAUDE.md generation/update
   - Track which PRDs contributed
   - Update timestamp

10. **Update task registry**:

    Update the task registry entry in `docs/blueprint/manifest.json`:

    ```bash
    jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.task_registry["claude-md"].last_completed_at = $now |
       .task_registry["claude-md"].last_result = "success" |
       .task_registry["claude-md"].stats.runs_total = ((.task_registry["claude-md"].stats.runs_total // 0) + 1)' \
      docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
    ```

11. **Report**:
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

    Run `/blueprint-status` to see full configuration.
    ```

**CLAUDE.md Best Practices**:
- Keep it concise (< 500 lines ideally)
- Focus on team-shared instructions (standards, commands, architecture)
- Use `@import` to reference existing docs instead of duplicating content
- Use `CLAUDE.local.md` for personal preferences (auto-gitignored)
- Reference `.claude/rules/` for detailed, path-specific rules
- Let auto memory handle "Current Focus", "Key Files", debugging tips
- Update when PRDs change significantly

12. **Prompt for next action** (use AskUserQuestion):
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

**Template Sections** (customize per project type):

| Project Type | Key Sections |
|--------------|--------------|
| Python | Virtual env, pytest, type hints |
| Node.js | Package manager, test runner, build |
| Rust | Cargo, clippy, unsafe usage rules |
| Monorepo | Workspace structure, shared deps |
| API | Endpoints, auth, error handling |
| Frontend | Components, state, styling |
