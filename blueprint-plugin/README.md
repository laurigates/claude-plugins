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
| `/blueprint-generate-rules` | Generate project-specific rules from PRDs |
| `/blueprint-work-order` | Create work-order with minimal context for subagent execution |
| `/prp-create` | Create a PRP with systematic research and validation gates |
| `/prp-execute` | Execute a PRP with validation loop, TDD workflow, and quality gates |
| `/prp-curate-docs` | Curate documentation for ai_docs to optimize AI context |

### Management Commands

| Command | Description |
|---------|-------------|
| `/blueprint-execute` | **Smart meta command** - Analyzes repository state and executes the next logical blueprint action (idempotent) |
| `/blueprint-status` | Show blueprint version and configuration |
| `/blueprint-upgrade` | Upgrade to latest blueprint format |
| `/blueprint-rules` | Manage modular rules |
| `/blueprint-claude-md` | Update CLAUDE.md from blueprint artifacts |

### Feature Tracking Commands

| Command | Description |
|---------|-------------|
| `/blueprint-feature-tracker-status` | Display feature completion statistics |
| `/blueprint-feature-tracker-sync` | Synchronize tracker with work-overview.md and TODO.md |

## Skills

| Skill | Description |
|-------|-------------|
| `blueprint-development` | Core methodology for generating project-specific skills and commands from PRDs |
| `confidence-scoring` | Assess quality of PRPs and work-orders for execution readiness |
| `feature-tracking` | Track implementation status against requirements with hierarchical FR codes |

## Agents

| Agent | Trigger | Description |
|-------|---------|-------------|
| `requirements-documentation` | New features requested | Creates comprehensive PRDs before implementation begins |
| `architecture-decisions` | Architecture decisions made | Documents ADRs for significant technical decisions |
| `prp-preparation` | Implementation starting | Checks if PRP exists, suggests creating one if missing |

## Workflow

### Smart Mode: Using `/blueprint-execute`

The easiest way to use Blueprint Development is with the **idempotent meta command**:

```bash
/blueprint-execute
```

This command:
- ✅ **Analyzes** current repository state
- ✅ **Determines** what needs to happen next
- ✅ **Executes** the appropriate action automatically
- ✅ **Safe to run anytime** - idempotent and smart

**Perfect for:**
- Morning start routine (figures out where you left off)
- After pulling changes (checks for stale content, upgrades)
- When stuck or unsure (always knows what to do next)
- Periodic check-ins (shows progress, suggests next work)

The command automatically handles:
1. Initialization (if not set up)
2. Upgrades (when available)
3. Stale content detection and regeneration
4. PRP execution (when ready)
5. Work-order execution (when pending)
6. Feature tracking sync
7. Status and next steps (when caught up)

**Example usage:**
```bash
# First time in a project
/blueprint-execute  # → Runs /blueprint-init

# After creating PRDs
/blueprint-execute  # → Runs /blueprint-generate-rules

# When PRPs are ready
/blueprint-execute  # → Prompts to execute PRPs

# When everything is current
/blueprint-execute  # → Shows status and options
```

---

### Manual Mode: Step-by-Step Workflow

You can also run individual commands directly when you know exactly what you want:

### 1. Initialize Blueprint Development

```bash
/blueprint-init
```

Creates the directory structure:
```
docs/
├── blueprint/
│   ├── manifest.json     # Blueprint configuration
│   ├── work-overview.md  # Current phase and progress
│   └── work-orders/      # Task packages for subagents
│       ├── completed/
│       └── archived/
├── prds/                 # Product Requirements Documents
├── adrs/                 # Architecture Decision Records
└── prps/                 # Product Requirement Prompts
```

### 2. Generate Initial Documentation (Onboarding)

For existing projects, generate initial documentation from codebase:

```bash
/blueprint-prd    # Generate PRD from README and docs
/blueprint-adr    # Generate ADRs from architecture analysis
```

These commands analyze existing documentation and code patterns, asking clarifying questions to fill gaps.

### 3. Write or Refine PRDs

Create or refine PRDs in `docs/prds/` documenting:
- Feature requirements and user stories
- Technical decisions and architecture
- TDD requirements and test strategies
- Success criteria and quality standards

The `requirements-documentation` agent triggers proactively for new features.

### 4. Generate Project Skills

```bash
/blueprint-generate-rules
```

Extracts patterns from PRDs and generates project-specific rules:
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

## Feature Tracking (Optional)

Track implementation progress against requirements documents using hierarchical FR codes.

### Enable During Init

Feature tracking can be enabled during `/blueprint-init`. When enabled, it creates:
- `docs/blueprint/feature-tracker.json` - Main tracker file

### Feature Tracker Structure

The tracker uses hierarchical FR codes mapped to your requirements:

```json
{
  "features": {
    "FR1": {
      "name": "Game Setup",
      "features": {
        "FR1.1": { "name": "Window Config", "status": "complete" },
        "FR1.2": { "name": "Mode Selection", "status": "in_progress" }
      }
    }
  },
  "statistics": {
    "total_features": 42,
    "complete": 22,
    "completion_percentage": 52.4
  }
}
```

### Status Values

- `not_started` - No implementation
- `in_progress` - Active work
- `partial` - Some sub-features complete
- `complete` - Fully implemented
- `blocked` - Missing dependencies

### Sync Targets

The tracker syncs with:
- `work-overview.md` - Completed/pending sections
- `TODO.md` - Checkbox states

### Quick Commands

```bash
# View statistics
jq '.statistics' docs/blueprint/feature-tracker.json

# List incomplete features
jq '.. | objects | select(.status == "not_started") | .name' docs/blueprint/feature-tracker.json

# Show PRD status
jq '.prds | to_entries | .[] | "\(.key): \(.value.status)"' docs/blueprint/feature-tracker.json
```

## Installation

```bash
/plugin install blueprint-plugin@lgates-claude-plugins
```

## License

MIT
