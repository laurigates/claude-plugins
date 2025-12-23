---
created: 2025-12-16
modified: 2025-12-22
reviewed: 2025-12-22
description: "Generate workflow commands based on project structure and PRDs"
allowed_tools: [Read, Write, Bash, Glob, AskUserQuestion]
---

Generate workflow commands customized for this project.

Commands are generated to `.claude/blueprints/generated/commands/` (regeneratable layer).

**Prerequisites**:
- Project has recognizable structure (package.json, Makefile, etc.)
- PRDs exist in `docs/prds/`

**Steps**:

1. **Detect project type and stack**:
   - Check for `package.json` → Node.js project
   - Check for `pyproject.toml` / `setup.py` → Python project
   - Check for `Cargo.toml` → Rust project
   - Check for `go.mod` → Go project
   - Check for `Makefile` → Check make targets

2. **Detect test runner and commands**:
   - Node.js: Check `package.json` scripts for `test`, `test:unit`, `test:integration`
   - Python: Check for pytest, unittest
   - Rust: `cargo test`
   - Go: `go test`

3. **Detect build and dev commands**:
   - Check `package.json` scripts
   - Check `Makefile` targets
   - Check project-specific tools

4. **Check for existing generated commands**:
   ```bash
   ls .claude/blueprints/generated/commands/ 2>/dev/null
   ```
   - If commands exist, check manifest for content hashes
   - Compare current content hash vs stored hash
   - If modified, offer options: overwrite, skip, or promote to custom

5. **Generate `/project:continue` command**:

   Create file at `.claude/blueprints/generated/commands/project-continue.md`:
   ```markdown
   ---
   description: "Continue development on [project-name] (project-specific)"
   allowed_tools: [Read, Bash, Grep, Glob, Edit, Write]
   ---

   Continue project development (customized for this project).

   **Project-specific configuration**:
   - Test command: `[detected_test_command]`
   - Build command: `[detected_build_command]`
   - Dev command: `[detected_dev_command]`

   1. **Check current state**:
      - Run `git status` (branch, uncommitted changes)
      - Run `git log -5 --oneline` (recent commits)

   2. **Read context**:
      - All PRDs in `docs/prds/`
      - `work-overview.md` (current phase and progress)
      - Recent work-orders (completed and pending)

   3. **Identify next task**:
      - Based on PRD requirements
      - Based on work-overview progress
      - Based on git status (resume if in progress)

   4. **Begin work following TDD**:
      - Apply project-specific skills automatically
      - Follow RED → GREEN → REFACTOR workflow
      - Commit incrementally with conventional commits

   Report before starting:
   - Current project status summary
   - Next task identified
   - Approach and plan
   ```

6. **Generate `/project:test-loop` command**:

   Create file at `.claude/blueprints/generated/commands/project-test-loop.md`:
   ```markdown
   ---
   description: "TDD loop for [project-name] using [test-runner]"
   allowed_tools: [Read, Edit, Bash]
   ---

   Run TDD cycle (customized for this project).

   **Project-specific configuration**:
   - Test command: `[detected_test_command]`
   - Watch mode: `[detected_watch_command]` (if available)

   1. **Run test suite**: `[detected_test_command]`
   2. **If tests fail**:
      - Analyze failure output
      - Identify root cause
      - Make minimal fix to pass the test
      - Re-run tests to confirm
   3. **If tests pass**:
      - Check for refactoring opportunities
      - Refactor while keeping tests green
      - Re-run tests to confirm still passing
   4. **Repeat until**:
      - All tests pass
      - No obvious refactoring needed
      - User intervention required

   Report:
   - Test results summary
   - Fixes applied
   - Refactorings performed
   - Current status (all pass / needs work / blocked)
   ```

7. **Generate project-specific commands** (optional):
   - If web app: Commands for starting dev server, running migrations
   - If CLI: Commands for building, testing CLI
   - If library: Commands for building, publishing

8. **Update manifest with generation tracking**:
   ```json
   {
     "project": {
       "detected_stack": ["typescript", "bun", "react"]
     },
     "generated": {
       "commands": {
         "project-continue": {
           "source": "auto-detection",
           "detected_stack": "[detected stack]",
           "generated_at": "[ISO timestamp]",
           "plugin_version": "2.0.0",
           "content_hash": "sha256:...",
           "status": "current"
         },
         "project-test-loop": { ... }
       }
     }
   }
   ```

9. **Report**:
   ```
   Workflow commands generated!

   Created in .claude/blueprints/generated/commands/:
   - project-continue.md → /project:continue
   - project-test-loop.md → /project:test-loop
   [- Additional project-specific commands]

   Detected configuration:
   - Project type: [Node.js / Python / Rust / etc.]
   - Stack: [detected libraries/frameworks]
   - Test command: [detected command]
   - Build command: [detected command]
   - Dev command: [detected command]

   Layer information:
   - Plugin layer: Generic commands from blueprint-plugin
   - Generated layer: These commands (regeneratable)
   - Custom layer: Override by creating .claude/commands/project/
   ```

10. **Prompt for next action** (use AskUserQuestion):
    ```
    question: "Workflow commands ready. What would you like to do?"
    options:
      - label: "Start development (Recommended)"
        description: "Run /project:continue to begin working on next task"
      - label: "Create a work-order"
        description: "Package a task for isolated subagent execution"
      - label: "Update CLAUDE.md"
        description: "Regenerate project overview with new commands"
      - label: "Promote command to custom layer"
        description: "Move a generated command to .claude/commands/ for customization"
      - label: "I'm done for now"
        description: "Exit - commands are ready to use anytime"
    ```

    **Based on selection:**
    - "Start development" → Run `/project:continue`
    - "Create a work-order" → Run `/blueprint:work-order`
    - "Update CLAUDE.md" → Run `/blueprint:claude-md`
    - "Promote command" → Run `/blueprint:promote [command-name]`
    - "I'm done for now" → Exit

**Important**:
- Detect actual project commands (detect dynamically from project structure)
- Include project-specific test commands
- Commands should be immediately usable
- Report what was detected for transparency

**Error Handling**:
- If project type unclear → Ask user for clarification
- If no test command found → Ask user how to run tests
- If commands already exist and modified → Offer to promote to custom layer before overwriting
