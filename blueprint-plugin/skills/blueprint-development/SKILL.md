---
model: opus
created: 2025-12-16
modified: 2026-02-14
reviewed: 2026-02-14
name: blueprint-development
description: "Generate project-specific rules and commands from PRDs for Blueprint Development methodology. Use when generating behavioral rules for architecture patterns, testing strategies, implementation guides, or quality standards from requirements documents."
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, TodoWrite
---

# /blueprint:development

Guide and reference for the Blueprint Development methodology that generates project-specific behavioral rules and workflow commands from PRDs (Product Requirements Documents).

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Starting Blueprint Development in a project | Project is already using Blueprint (use `/blueprint:status`) |
| Need to generate rules from PRDs | Starting a brand new project with no PRD yet |
| Want project-specific behavioral guidelines | Using generic development practices |
| Creating workflow automation for a project | Working on isolated tasks without project context |

For detailed rule templates, command templates, and generation guidelines, see [REFERENCE.md](REFERENCE.md).

## Context

- Blueprint initialized: !`test -f docs/blueprint/manifest.json 2>/dev/null`
- PRDs present: !`find docs/prds -name "*.md" -type f 2>/dev/null`
- Rules directory: !`test -d .claude/rules 2>/dev/null`
- Existing rules: !`find .claude/rules -maxdepth 1 -name "*.md" 2>/dev/null`
- Project type: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) -type f -print -quit 2>/dev/null`

## Execution

Execute the complete Blueprint Development setup and rule generation workflow:

### Step 1: Verify project readiness

Check context values above:

1. If Blueprint initialized = "NO" → Error: "Blueprint not initialized. Run `/blueprint:init` first"
2. If PRDs present = "0" → Error: "No PRDs found. Create at least one PRD in `docs/prds/` before generating rules"
3. If Rules directory = "NO" → Create: `mkdir -p .claude/rules`

### Step 2: Analyze PRDs and extract patterns

Read all PRD files in `docs/prds/` and extract:

1. **Architecture Patterns**: Project structure, dependency injection, error handling, module boundaries, layering, code organization
2. **Testing Strategies**: TDD workflow, test types (unit, integration, e2e), mocking patterns, coverage requirements
3. **Implementation Guides**: Patterns for implementing feature types (APIs, UI, database, external services)
4. **Quality Standards**: Code review checklist, performance baselines, security requirements, style standards

See [REFERENCE.md](REFERENCE.md#extraction-patterns) for specific extraction patterns for each category.

### Step 3: Generate four behavioral rules in `.claude/rules/`

Create project-specific rules that guide Claude's behavior during development:

**Three required core rules:**

1. **`architecture-patterns.md`** - Project structure, design patterns, dependency management, error handling, integration patterns
2. **`testing-strategies.md`** - TDD workflow, test structure, test types, mocking patterns, coverage requirements
3. **`quality-standards.md`** - Code review checklist, performance baselines, security standards, style, documentation

**One optional advanced rule (if applicable):**

4. **`implementation-guides.md`** - Step-by-step patterns for implementing specific feature types from PRDs

For each rule file:
- Use templates from [REFERENCE.md](REFERENCE.md#rule-templates)
- Extract content directly from PRDs
- Include code examples and specific references
- Document rationale for architectural choices
- Use imperative language ("Use...", "Follow...", "Ensure...")

See [REFERENCE.md](REFERENCE.md#rule-generation-guidelines) for detailed guidelines on creating effective rules.

### Step 4: Generate workflow commands

Create project-specific workflow commands in `.claude/skills/` or `docs/blueprint/`:

**Six core commands:**

1. **`/blueprint:init`** - Initialize Blueprint Development structure
2. **`/blueprint:generate-rules`** - Generate project rules from PRDs (main entry point)
3. **`/blueprint:generate-commands`** - Generate workflow commands based on project type
4. **`/blueprint:work-order`** - Create isolated work-order for subagent execution
5. **`/project:continue`** - Analyze state and resume development
6. **`/project:test-loop`** - Run automated TDD cycle

For each command:
- Determine project type and language
- Extract test runners, build commands, development workflows
- Customize command implementations using [REFERENCE.md](REFERENCE.md#command-templates)
- Verify with expected `allowed-tools` permissions

### Step 5: Create mapping in manifest

Update `docs/blueprint/manifest.json` with:

```json
{
  "generated": {
    "rules": [
      "architecture-patterns.md",
      "testing-strategies.md",
      "quality-standards.md",
      "implementation-guides.md"
    ],
    "commands": [
      "blueprint-init.md",
      "blueprint-generate-rules.md",
      "blueprint-generate-commands.md",
      "blueprint-work-order.md",
      "project-continue.md",
      "project-test-loop.md"
    ]
  },
  "source_prds": ["project-overview.md"],
  "last_generated": "ISO-8601-timestamp"
}
```

This enables regeneration without losing track of what was auto-generated vs. manually created.

### Step 6: Test and validate

Verify rules and commands work correctly:

1. **Test rules apply**: Check that Claude follows architecture-patterns, testing-strategies, and quality-standards during development
2. **Test commands execute**: Run each command to verify it works as expected
3. **Verify output quality**: Check that generated rules match PRD requirements and include concrete examples
4. **Refine as needed**: Update rules and commands based on feedback and actual project development

### Step 7: Report results and next steps

Create summary report:

- Rules generated: {count} in `.claude/rules/`
- Commands created: {count} (use `/project:continue` to start development)
- Manifest updated with tracking metadata
- **Next steps**:
  1. Review generated rules for accuracy
  2. Add project-specific additions or clarifications
  3. Run `/project:continue` to begin Blueprint Development workflow
  4. Use `/blueprint:work-order` to create isolated tasks for team members

## Integration with Blueprint Development

This skill enables the core Blueprint Development workflow:

**PRDs** (requirements) - **Rules** (behavioral guidelines) - **Commands** (workflow automation) - **Work-orders** (isolated tasks)

By generating project-specific rules and commands from PRDs, Blueprint Development creates a self-documenting, AI-native development environment where behavioral guidelines, patterns, and quality standards are first-class citizens.

## GitHub Work Order Integration

Work orders can be linked to GitHub issues for transparency and cooperative development. See [REFERENCE.md](REFERENCE.md#github-work-order-integration) for workflow modes (`--no-publish`, `--from-issue N`), label setup, completion workflow, and work order file format.

## Agentic Optimizations

| Context | Action |
|---------|--------|
| Check if rules exist | `find .claude/rules -maxdepth 1 -name "*.md" \| wc -l` |
| List existing rules | `ls -1 .claude/rules/*.md 2>/dev/null` |
| Count PRDs | `ls docs/prds/*.md 2>/dev/null \| wc -l` |
| Extract PRD sections | Use Grep to find specific sections by heading pattern |
| Fast generation | Skip manual review step, proceed with standard templates |

## Examples

See `.claude/docs/blueprint-development/` for complete workflow documentation and examples.

---

For detailed rule templates, command examples, extraction patterns, and project-specific customization, see [REFERENCE.md](REFERENCE.md).
