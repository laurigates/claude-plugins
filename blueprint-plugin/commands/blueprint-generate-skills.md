---
description: "Generate project-specific skills from PRDs"
allowed_tools: [Read, Write, Glob]
---

Generate project-specific skills from Product Requirements Documents.

**Prerequisites**:
- `.claude/blueprints/prds/` directory exists
- At least one PRD file in `.claude/blueprints/prds/`

**Steps**:

1. **Find and read all PRDs**:
   - Use Glob to find all `.md` files in `.claude/blueprints/prds/`
   - Read each PRD file
   - If no PRDs found, report error and suggest writing PRDs first

2. **Analyze PRDs and extract**:

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

3. **Generate four domain skills**:

   **Create `.claude/skills/architecture-patterns/SKILL.md`**:
   - Use template from `.claude/skills/blueprint-development/templates/architecture-skill-template.md`
   - Fill in project-specific patterns extracted from PRDs
   - Include code examples where possible
   - Reference specific files/directories

   **Create `.claude/skills/testing-strategies/SKILL.md`**:
   - Use template from `.claude/skills/blueprint-development/templates/testing-skill-template.md`
   - Fill in TDD requirements from PRDs
   - Include coverage requirements
   - Include test commands for the project

   **Create `.claude/skills/implementation-guides/SKILL.md`**:
   - Use template from `.claude/skills/blueprint-development/templates/implementation-skill-template.md`
   - Fill in step-by-step patterns for feature types
   - Include code examples

   **Create `.claude/skills/quality-standards/SKILL.md`**:
   - Use template from `.claude/skills/blueprint-development/templates/quality-skill-template.md`
   - Fill in performance baselines from PRDs
   - Fill in security requirements from PRDs
   - Create project-specific checklist

4. **Create reference documentation** (optional):
   - For each skill, create `reference.md` with additional details
   - Include detailed code examples
   - Document common pitfalls
   - Link to external documentation

5. **Report**:
   ```
   ✅ Skills generated from PRDs!

   Created:
   - .claude/skills/architecture-patterns/
   - .claude/skills/testing-strategies/
   - .claude/skills/implementation-guides/
   - .claude/skills/quality-standards/

   PRDs analyzed:
   - [List PRD files]

   Key patterns extracted:
   - Architecture: [Brief summary]
   - Testing: [Brief summary]
   - Implementation: [Brief summary]
   - Quality: [Brief summary]

   Next steps:
   1. Review generated skills and refine as needed
   2. Run `/blueprint:generate-commands` to create workflow commands
   3. Start development with `/project:continue`

   Note: Skills are immediately available - Claude will auto-discover them based on context!
   ```

**Important**:
- Skills must have valid frontmatter with `name` and `description`
- Keep skill descriptions specific and focused (for better discovery)
- Include code examples to make patterns concrete
- Reference PRD sections for traceability
- Skills should be actionable, not just documentation

**Error Handling**:
- If no PRDs found → Guide user to write PRDs first
- If PRDs incomplete → Generate skills with TODO markers for missing sections
- If skills already exist → Ask user if they want to regenerate or update
