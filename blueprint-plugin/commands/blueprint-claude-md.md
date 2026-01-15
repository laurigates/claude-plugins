---
created: 2025-12-17
modified: 2026-01-09
reviewed: 2025-12-17
description: "Generate or update CLAUDE.md from project context and blueprint artifacts"
allowed_tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
---

Generate or update the project's CLAUDE.md file based on blueprint artifacts, PRDs, and project structure.

**Steps**:

1. **Check current state**:
   - Look for existing `CLAUDE.md` in project root
   - Read `docs/blueprint/manifest.json` for configuration
   - Determine `claude_md_mode` (single, modular, or both)

2. **Determine action** (use AskUserQuestion):
   ```
   {If CLAUDE.md exists:}
   question: "CLAUDE.md already exists. What would you like to do?"
   options:
     - "Update with latest project info" → merge updates
     - "Regenerate completely" → overwrite (backup first)
     - "Add missing sections only" → append new content
     - "Convert to modular rules" → split into .claude/rules/
     - "View current structure" → analyze and display

   {If CLAUDE.md doesn't exist:}
   question: "No CLAUDE.md found. How would you like to create it?"
   options:
     - "Generate from project analysis" → auto-generate
     - "Generate from PRDs" → use blueprint PRDs
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

   **Standard sections**:
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
   {Key architectural decisions from PRDs}

   ## Conventions

   ### Code Style
   {Detected or from PRDs}

   ### Commit Messages
   {Conventional commits if detected}

   ### Testing Requirements
   {From PRDs or rules}

   ## Current Focus
   {From work-overview.md}

   ## Key Files
   {Important files and their purposes}

   ## See Also
   {If modular rules enabled:}
   - `.claude/rules/` - Detailed rules by domain
   - `docs/prds/` - Product requirements
   ```

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
   - Create minimal CLAUDE.md with references
   - Move detailed content to `.claude/rules/`

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

10. **Report**:
    ```
    ✅ CLAUDE.md updated!

    {Created | Updated}: CLAUDE.md

    Sections:
    - Overview ✅
    - Tech Stack ✅
    - Development Workflow ✅
    - Architecture ✅
    - Conventions ✅
    - Current Focus ✅

    Sources used:
    - PRDs: {list}
    - Rules: {list}
    - Project detection: {what was detected}

    {If modular mode:}
    Note: Detailed rules are in .claude/rules/
    CLAUDE.md serves as overview and quick reference.

    Run `/blueprint-status` to see full configuration.
    ```

**CLAUDE.md Best Practices**:
- Keep it concise (< 500 lines ideally)
- Focus on "what Claude needs to know"
- Reference modular rules for details
- Update when PRDs change significantly
- Include current focus/phase for context

11. **Prompt for next action** (use AskUserQuestion):
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
