---
created: 2025-12-16
modified: 2025-12-22
reviewed: 2025-12-22
description: "Generate project-specific skills from PRDs"
allowed_tools: [Read, Write, Glob, Bash, AskUserQuestion]
---

Generate project-specific skills from Product Requirements Documents.

Skills are generated to `.claude/blueprints/generated/skills/` (regeneratable layer).

**Prerequisites**:
- `docs/prds/` directory exists
- At least one PRD file in `docs/prds/`

**Steps**:

1. **Find and read all PRDs**:
   - Use Glob to find all `.md` files in `docs/prds/`
   - Read each PRD file
   - If no PRDs found, report error and suggest writing PRDs first

2. **Check for existing generated skills**:
   ```bash
   ls .claude/blueprints/generated/skills/ 2>/dev/null
   ```
   - If skills exist, check manifest for content hashes
   - Compare current content hash vs stored hash
   - If modified, offer options: overwrite, skip, or promote to custom

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

4. **Generate four aggregated domain skills**:

   Create in `.claude/blueprints/generated/skills/`:

   **`architecture-patterns/skill.md`**:
   - Aggregated patterns from all PRDs
   - Fill in project-specific patterns extracted from PRDs
   - Include code examples where possible
   - Reference specific files/directories

   **`testing-strategies/skill.md`**:
   - Aggregated testing requirements from all PRDs
   - Fill in TDD requirements from PRDs
   - Include coverage requirements
   - Include test commands for the project

   **`implementation-guides/skill.md`**:
   - Aggregated implementation patterns from all PRDs
   - Fill in step-by-step patterns for feature types
   - Include code examples

   **`quality-standards/skill.md`**:
   - Aggregated quality requirements from all PRDs
   - Fill in performance baselines from PRDs
   - Fill in security requirements from PRDs
   - Create project-specific checklist

5. **Update manifest with generation tracking**:
   ```json
   {
     "generated": {
       "skills": {
         "architecture-patterns": {
           "source": "docs/prds/*",
           "source_hash": "sha256:...",
           "generated_at": "[ISO timestamp]",
           "plugin_version": "2.0.0",
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
   Skills generated from PRDs!

   Created in .claude/blueprints/generated/skills/:
   - architecture-patterns/
   - testing-strategies/
   - implementation-guides/
   - quality-standards/

   PRDs analyzed:
   - docs/prds/[List PRD files]

   Key patterns extracted:
   - Architecture: [Brief summary]
   - Testing: [Brief summary]
   - Implementation: [Brief summary]
   - Quality: [Brief summary]

   Skills are immediately available - Claude auto-discovers them based on context!

   Layer information:
   - Plugin layer: Generic skills from blueprint-plugin
   - Generated layer: These skills (regeneratable from docs/prds/)
   - Custom layer: Override by creating .claude/skills/[skill-name]/
   ```

7. **Prompt for next action** (use AskUserQuestion):
   ```
   question: "Skills generated. What would you like to do next?"
   options:
     - label: "Generate workflow commands (Recommended)"
       description: "Create /project:continue and /project:test-loop commands"
     - label: "Update CLAUDE.md"
       description: "Regenerate project overview document with new skills"
     - label: "Review generated skills"
       description: "I'll examine and refine the skills manually"
     - label: "Promote skill to custom layer"
       description: "Move a generated skill to .claude/skills/ for customization"
     - label: "I'm done for now"
       description: "Exit - skills are already available"
   ```

   **Based on selection:**
   - "Generate workflow commands" → Run `/blueprint:generate-commands`
   - "Update CLAUDE.md" → Run `/blueprint:claude-md`
   - "Review generated skills" → Show skill file locations and exit
   - "Promote skill" → Run `/blueprint:promote [skill-name]`
   - "I'm done for now" → Exit

**Important**:
- Skills must have valid frontmatter with `name` and `description`
- Keep skill descriptions specific and focused (for better discovery)
- Include code examples to make patterns concrete
- Reference PRD sections for traceability
- Skills should be actionable, not just documentation

**Error Handling**:
- If no PRDs found → Guide user to write PRDs first (`/blueprint:prd`)
- If PRDs incomplete → Generate skills with TODO markers for missing sections
- If skills already exist and modified → Offer to promote to custom layer before overwriting
