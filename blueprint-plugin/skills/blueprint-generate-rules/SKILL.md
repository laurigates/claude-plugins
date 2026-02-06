---
model: opus
created: 2025-12-16
modified: 2026-02-06
reviewed: 2026-01-09
description: "Generate project-specific rules from PRDs"
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
name: blueprint-generate-rules
---

Generate project-specific rules from Product Requirements Documents.

Rules are generated to `.claude/rules/` directory.

**Prerequisites**:
- `docs/prds/` directory exists
- At least one PRD file in `docs/prds/`

**Steps**:

1. **Find and read all PRDs**:
   - Use Glob to find all `.md` files in `docs/prds/`
   - Read each PRD file
   - If no PRDs found, report error and suggest writing PRDs first

2. **Check for existing generated rules**:
   ```bash
   ls .claude/rules/ 2>/dev/null
   ```
   - If rules exist, check manifest for content hashes
   - Compare current content hash vs stored hash
   - If modified, offer options: overwrite, skip, or backup

3. **Analyze PRDs and extract** (aggregated from all PRDs):

   **Architecture Patterns**:
   - Project structure and organization
   - Architectural style (MVC, layered, hexagonal, etc.)
   - Design patterns
   - Dependency injection approach
   - Error handling strategy
   - Code organization conventions
   - Integration patterns

   **Testing Strategies**:
   - TDD workflow requirements
   - Test types (unit, integration, e2e)
   - Mocking patterns
   - Coverage requirements
   - Test structure and organization
   - Test commands

   **Implementation Guides**:
   - How to implement APIs/endpoints
   - How to implement UI components (if applicable)
   - Database operation patterns
   - External service integration patterns
   - Background job patterns (if applicable)

   **Quality Standards**:
   - Code review checklist
   - Performance baselines
   - Security requirements (OWASP, validation, auth)
   - Code style and formatting
   - Documentation requirements
   - Dependency management

4. **Generate four aggregated domain rules**:

   Create in `.claude/rules/`:

   **`architecture-patterns.md`**:
   - Aggregated patterns from all PRDs
   - Fill in project-specific patterns extracted from PRDs
   - Include code examples where possible
   - Reference specific files/directories

   **`testing-strategies.md`**:
   - Aggregated testing requirements from all PRDs
   - Fill in TDD requirements from PRDs
   - Include coverage requirements
   - Include test commands for the project

   **`implementation-guides.md`**:
   - Aggregated implementation patterns from all PRDs
   - Fill in step-by-step patterns for feature types
   - Include code examples

   **`quality-standards.md`**:
   - Aggregated quality requirements from all PRDs
   - Fill in performance baselines from PRDs
   - Fill in security requirements from PRDs
   - Create project-specific checklist

5. **Update manifest with generation tracking**:
   ```json
   {
     "generated": {
       "rules": {
         "architecture-patterns": {
           "source": "docs/prds/*",
           "source_hash": "sha256:...",
           "generated_at": "[ISO timestamp]",
           "plugin_version": "3.0.0",
           "content_hash": "sha256:...",
           "status": "current"
         },
         "testing-strategies": { ... },
         "implementation-guides": { ... },
         "quality-standards": { ... }
       }
     }
   }
   ```

6. **Report**:
   ```
   Rules generated from PRDs!

   Created in .claude/rules/:
   - architecture-patterns.md
   - testing-strategies.md
   - implementation-guides.md
   - quality-standards.md

   PRDs analyzed:
   - docs/prds/[List PRD files]

   Key patterns extracted:
   - Architecture: [Brief summary]
   - Testing: [Brief summary]
   - Implementation: [Brief summary]
   - Quality: [Brief summary]

   Rules are immediately available - Claude auto-discovers them based on context!
   ```

7. **Prompt for next action** (use AskUserQuestion):
   ```
   question: "Rules generated. What would you like to do next?"
   options:
     - label: "Generate workflow commands (Recommended)"
       description: "Create /project:continue and /project:test-loop commands"
     - label: "Update CLAUDE.md"
       description: "Regenerate project overview document with new rules"
     - label: "Review generated rules"
       description: "I'll examine and refine the rules manually"
     - label: "I'm done for now"
       description: "Exit - rules are already available"
   ```

   **Based on selection:**
   - "Generate workflow commands" -> Run `/blueprint:generate-commands`
   - "Update CLAUDE.md" -> Run `/blueprint:claude-md`
   - "Review generated rules" -> Show rule file locations and exit
   - "I'm done for now" -> Exit

**Important**:
- Rules should be markdown files with clear headings
- Keep rule content specific and focused
- Include code examples to make patterns concrete
- Reference PRD sections for traceability
- Rules should be actionable, not just documentation

**Error Handling**:
- If no PRDs found -> Guide user to derive PRDs first (`/blueprint:derive-prd`)
- If PRDs incomplete -> Generate rules with TODO markers for missing sections
- If rules already exist and modified -> Offer to backup before overwriting
