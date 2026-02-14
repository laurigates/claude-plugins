---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-26
name: blueprint-development
description: "Generate project-specific rules and commands from PRDs for Blueprint Development methodology. Use when generating behavioral rules for architecture patterns, testing strategies, implementation guides, or quality standards from requirements documents."
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, TodoWrite
---

# Blueprint Development Rule Generator

This skill teaches Claude how to generate project-specific behavioral rules and commands from Product Requirements Documents (PRDs) as part of the Blueprint Development methodology.

## When to Use This Skill

Activate this skill when:
- User runs `/blueprint:generate-rules` command
- User runs `/blueprint:generate-commands` command
- User asks to "generate rules from PRDs"
- User asks to "create project-specific rules"
- User initializes Blueprint Development in a project

For detailed rule templates, command templates, and generation guidelines, see [REFERENCE.md](REFERENCE.md).

## Rule Generation Process

### Step 1: Analyze PRDs

Read all PRD files in `docs/prds/` and extract:

| Domain | What to Extract |
|--------|----------------|
| **Architecture Patterns** | Project structure, DI patterns, error handling, module boundaries, code organization |
| **Testing Strategies** | TDD workflow, test types, mocking patterns, coverage requirements |
| **Implementation Guides** | Feature implementation patterns (API, UI, data access, integrations) |
| **Quality Standards** | Code review checklists, performance baselines, security requirements |

### Step 2: Generate Four Domain Rules

Create project-specific behavioral rules in `.claude/rules/` alongside manual rules.

**Two-Layer Architecture**:
1. **Plugin layer**: Generic skills from blueprint-plugin (auto-updated)
2. **Rules layer**: Behavioral rules from PRDs in `.claude/rules/` (project-specific, can be manually edited)

Generate these four rules:

| Rule | Location | Purpose |
|------|----------|---------|
| Architecture Patterns | `.claude/rules/architecture-patterns.md` | Structure, organization, design patterns, DI, error handling |
| Testing Strategies | `.claude/rules/testing-strategies.md` | TDD workflow, test types, mocking, coverage |
| Implementation Guides | `.claude/rules/implementation-guides.md` | Step-by-step patterns for APIs, UI, data access |
| Quality Standards | `.claude/rules/quality-standards.md` | Code review, performance, security, code style |

See [REFERENCE.md](REFERENCE.md) for full rule templates and content guidelines.

### Step 3: Track Generated Rules in Manifest

Track which rules were generated from PRDs in `docs/blueprint/manifest.json`:

```json
{
  "generated": {
    "rules": [
      "architecture-patterns.md",
      "testing-strategies.md",
      "implementation-guides.md",
      "quality-standards.md"
    ],
    "commands": []
  },
  "source_prds": [],
  "last_generated": "2026-01-09T..."
}
```

## Command Generation Process

### Step 1: Analyze Project Structure

Determine: project type, language/framework, test runner, build commands, git workflow conventions.

### Step 2: Generate Workflow Commands

Create commands in `.claude/skills/` for project-specific workflows:

| Command | Purpose | Key Tools |
|---------|---------|-----------|
| `/blueprint:init` | Initialize Blueprint structure | Bash, Write |
| `/blueprint:generate-rules` | Generate rules from PRDs | Read, Write, Glob |
| `/blueprint:generate-commands` | Generate workflow commands | Read, Write, Bash, Glob |
| `/blueprint:work-order` | Create isolated work-order for subagent | Read, Write, Glob, Bash |
| `/project:continue` | Analyze state and resume development | Read, Bash, Grep, Glob, Edit, Write |
| `/project:test-loop` | Run automated TDD cycle | Read, Edit, Bash |

See [REFERENCE.md](REFERENCE.md) for full command templates.

**GitHub Work-Order Integration Flow**:
1. Work-order created - GitHub issue created (visibility)
2. Work completed - PR created with `Fixes #N`
3. PR merged - Issue auto-closes
4. Work-order moved to `completed/`

### Step 3: Customize Commands for Project

Adapt command templates based on:
- **Programming language**: Adjust test commands, build commands
- **Framework**: Include framework-specific patterns
- **Project type**: CLI, web app, library have different workflows
- **Team conventions**: Match existing git workflow, commit conventions

## Rule Generation Guidelines

| Guideline | Description |
|-----------|-------------|
| **Extract from PRDs** | Use patterns and decisions directly from PRDs; ask user for gaps |
| **Be specific** | Use precise, actionable guidance with concrete file:line references |
| **Include code examples** | Every pattern should show what it looks like in practice |
| **Document rationale** | Explain why, alternatives considered, trade-offs, when to deviate |
| **Use imperative language** | "Use...", "Follow...", "Ensure..." |
| **Keep rules focused** | One concern per rule file |

## Command Generation Guidelines

| Guideline | Description |
|-----------|-------------|
| **Autonomous execution** | Run without user input (except explicit prompts) |
| **Auto-read context** | Read necessary context automatically |
| **Clear reporting** | Report what was analyzed, done, results, and next steps |
| **Error handling** | Detect missing files, invalid structure, missing commands |

## Integration with Blueprint Development

This skill enables the core Blueprint Development workflow:

**PRDs** (requirements) - **Rules** (behavioral guidelines) - **Commands** (workflow automation) - **Work-orders** (isolated tasks)

By generating project-specific rules and commands from PRDs, Blueprint Development creates a self-documenting, AI-native development environment where behavioral guidelines, patterns, and quality standards are first-class citizens.

## GitHub Work Order Integration

Work orders can be linked to GitHub issues for transparency and cooperative development. See [REFERENCE.md](REFERENCE.md) for workflow modes (`--no-publish`, `--from-issue N`), label setup, completion workflow, and work order file format.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Generate rules | `/blueprint:generate-rules` |
| Generate commands | `/blueprint:generate-commands` |
| Full setup | `/blueprint:init` then `/blueprint:generate-rules` then `/blueprint:generate-commands` |
| Work order (local) | `/blueprint:work-order --no-publish` |
| Work order (GitHub) | `/blueprint:work-order` |
| Work order from issue | `/blueprint:work-order --from-issue N` |

## Examples

See `.claude/docs/blueprint-development/` for complete workflow documentation and examples.
