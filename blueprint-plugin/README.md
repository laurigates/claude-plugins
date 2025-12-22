# Blueprint Plugin

Blueprint Development methodology for Claude Code - structured feature development with PRDs, PRPs, and work-orders.

## Overview

This plugin provides a documentation-first development workflow:

```
PRD (Product Requirements) → PRP (Product Requirement Prompt) → Work-Order → Implementation
```

## Commands

### Onboarding Commands

| Command | Description |
|---------|-------------|
| `/blueprint-init` | Initialize Blueprint Development structure in a project |
| `/blueprint-prd` | Generate initial PRD from existing project documentation |
| `/blueprint-adr` | Generate Architecture Decision Records from existing codebase |

### Workflow Commands

| Command | Description |
|---------|-------------|
| `/blueprint-generate-commands` | Generate workflow commands from project structure and PRDs |
| `/blueprint-generate-skills` | Generate project-specific skills from PRDs |
| `/blueprint-work-order` | Create work-order with minimal context for subagent execution |
| `/prp-create` | Create a PRP with systematic research and validation gates |
| `/prp-execute` | Execute a PRP with validation loop, TDD workflow, and quality gates |
| `/prp-curate-docs` | Curate documentation for ai_docs to optimize AI context |

### Management Commands

| Command | Description |
|---------|-------------|
| `/blueprint-status` | Show blueprint version and configuration |
| `/blueprint-upgrade` | Upgrade to latest blueprint format |
| `/blueprint-rules` | Manage modular rules |
| `/blueprint-claude-md` | Update CLAUDE.md from blueprint artifacts |

## Skills

| Skill | Description |
|-------|-------------|
| `blueprint-development` | Core methodology for generating project-specific skills and commands from PRDs |
| `confidence-scoring` | Assess quality of PRPs and work-orders for execution readiness |

## Agents

| Agent | Trigger | Description |
|-------|---------|-------------|
| `requirements-documentation` | New features requested | Creates comprehensive PRDs before implementation begins |
| `architecture-decisions` | Architecture decisions made | Documents ADRs for significant technical decisions |
| `prp-preparation` | Implementation starting | Checks if PRP exists, suggests creating one if missing |

## Workflow

### 1. Initialize Blueprint Development

```bash
/blueprint-init
```

Creates the directory structure:
```
.claude/blueprints/
├── prds/                 # Product Requirements Documents
├── adrs/                 # Architecture Decision Records
├── prps/                 # Product Requirement Prompts
├── work-orders/          # Task packages for subagents
│   ├── completed/
│   └── archived/
└── work-overview.md      # Current phase and progress
```

### 2. Generate Initial Documentation (Onboarding)

For existing projects, generate initial documentation from codebase:

```bash
/blueprint-prd    # Generate PRD from README and docs
/blueprint-adr    # Generate ADRs from architecture analysis
```

These commands analyze existing documentation and code patterns, asking clarifying questions to fill gaps.

### 3. Write or Refine PRDs

Create or refine PRDs in `.claude/blueprints/prds/` documenting:
- Feature requirements and user stories
- Technical decisions and architecture
- TDD requirements and test strategies
- Success criteria and quality standards

The `requirements-documentation` agent triggers proactively for new features.

### 4. Generate Project Skills

```bash
/blueprint-generate-skills
```

Extracts patterns from PRDs and generates project-specific skills:
- Architecture patterns
- Testing strategies
- Implementation guides
- Quality standards

### 5. Create Work-Orders

```bash
/blueprint-work-order
```

Generates isolated task packages with minimal context for subagent execution.

### 6. Execute with TDD

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
