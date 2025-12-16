# Blueprint Plugin

Blueprint Development methodology for Claude Code - structured feature development with PRDs, PRPs, and work-orders.

## Overview

This plugin provides a documentation-first development workflow:

```
PRD (Product Requirements) → PRP (Product Requirement Prompt) → Work-Order → Implementation
```

## Commands

| Command | Description |
|---------|-------------|
| `/blueprint-init` | Initialize Blueprint Development structure in a project |
| `/blueprint-generate-commands` | Generate workflow commands from project structure and PRDs |
| `/blueprint-generate-skills` | Generate project-specific skills from PRDs |
| `/blueprint-work-order` | Create work-order with minimal context for subagent execution |
| `/prp-create` | Create a PRP with systematic research and validation gates |
| `/prp-execute` | Execute a PRP with validation loop, TDD workflow, and quality gates |
| `/prp-curate-docs` | Curate documentation for ai_docs to optimize AI context |

## Skills

| Skill | Description |
|-------|-------------|
| `blueprint-development` | Core methodology for generating project-specific skills and commands from PRDs |
| `confidence-scoring` | Assess quality of PRPs and work-orders for execution readiness |

## Agent

| Agent | Description |
|-------|-------------|
| `requirements-documentation` | Creates comprehensive PRDs before implementation begins |

## Workflow

### 1. Initialize Blueprint Development

```bash
/blueprint-init
```

Creates the directory structure:
```
.claude/blueprints/
├── prds/                 # Product Requirements Documents
├── work-orders/          # Task packages for subagents
│   ├── completed/
│   └── archived/
└── work-overview.md      # Current phase and progress
```

### 2. Write PRDs

Create PRDs in `.claude/blueprints/prds/` documenting:
- Feature requirements and user stories
- Technical decisions and architecture
- TDD requirements and test strategies
- Success criteria and quality standards

### 3. Generate Project Skills

```bash
/blueprint-generate-skills
```

Extracts patterns from PRDs and generates project-specific skills:
- Architecture patterns
- Testing strategies
- Implementation guides
- Quality standards

### 4. Create Work-Orders

```bash
/blueprint-work-order
```

Generates isolated task packages with minimal context for subagent execution.

### 5. Execute with TDD

```bash
/prp-execute
```

Runs the implementation with RED → GREEN → REFACTOR workflow.

## Installation

```bash
/plugin install blueprint-plugin@lgates-claude-plugins
```

## License

MIT
