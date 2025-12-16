# Graphiti Plugin

Graphiti knowledge graph integration - memory, learning, and episode storage for Claude Code.

## Overview

This plugin provides comprehensive Graphiti Memory integration for building institutional knowledge, learning from historical data, and storing episodic memory. It enables semantic search across agent executions, error resolutions, workflows, and technical decisions.

## Commands

| Command | Description |
|---------|-------------|
| `/build-knowledge-graph` | Build comprehensive knowledge graph from Obsidian vault documentation |

## Skills

| Skill | Description |
|-------|-------------|
| `graphiti-episode-storage` | Store episodes in Graphiti Memory: agent executions, error resolutions, workflow completions, technical decisions |
| `graphiti-learning-workflows` | Learn from historical data and build institutional knowledge with Graphiti Memory |
| `graphiti-memory-retrieval` | Search and retrieve information from Graphiti Memory graph database |

## Core Concepts

### Episodes

Episodes are discrete events stored in Graphiti Memory that get automatically processed into facts and entities:

- **Agent Executions** - Record agent work with approach, outcome, and lessons learned
- **Error Resolutions** - Document how errors were resolved with root cause analysis
- **Workflow Completions** - Store multi-agent workflow results with metrics
- **Technical Decisions** - Preserve decision rationales and alternatives considered

### Learning Workflow

1. **Before Work**: Search for similar past tasks to apply proven patterns
2. **During Work**: Search for known error solutions when issues arise
3. **After Work**: Store execution results for future learning

### Search Types

- **Facts Search**: Find specific relationships between entities
- **Node Search**: Get comprehensive entity summaries and relationships

## Usage Examples

### Store Agent Execution

```python
mcp__graphiti-memory__add_memory(
    name="Agent Execution: python-developer - FastAPI JWT Auth",
    episode_body=json.dumps({
        "agent": "python-developer",
        "task": "Implement JWT authentication for REST API",
        "approach": ["FastAPI", "PyJWT", "HTTP-only cookies"],
        "outcome": "SUCCESS",
        "lessons_learned": [
            "Async context managers essential for DB",
            "HTTP-only cookies more secure than localStorage"
        ],
        "time_spent_minutes": 45
    }),
    source="json",
    group_id="python_development"
)
```

### Search for Past Work

```python
mcp__graphiti-memory__search_memory_facts(
    query="REST API JWT authentication implementation",
    group_ids=["python_development", "agent_executions"],
    max_facts=5
)
```

### Search for Error Solutions

```python
mcp__graphiti-memory__search_memory_facts(
    query="PostgreSQL connection pool exhausted timeout",
    group_ids=["error_resolutions"],
    max_facts=3
)
```

### Build Knowledge Graph from Documentation

```bash
/build-knowledge-graph
```

Processes technical documentation files and builds a comprehensive knowledge graph for semantic search.

## Group ID Conventions

Organize episodes with consistent group IDs:

**By Domain**:
- `python_development` - Python-related tasks
- `nodejs_development` - Node.js/TypeScript tasks
- `rust_development` - Rust programming tasks
- `infrastructure` - DevOps, containers, Kubernetes
- `git_operations` - Git and GitHub operations

**By Activity Type**:
- `agent_executions` - General agent work
- `error_resolutions` - Problem solving
- `workflow_executions` - Multi-step workflows
- `technical_decisions` - Architecture and tech choices
- `code_reviews` - Review findings and improvements

**By Project**:
- `project_auth_api` - Specific project work
- `project_frontend_app` - Another project
- `migration_postgres_to_mongo` - Migration project

## Learning Patterns

### Incremental Learning

Build knowledge gradually from each task:
- **Week 1**: Store basic implementation patterns
- **Week 2**: Search for first project patterns, apply lessons
- **Week 3**: Recognize emerging patterns, store refined best practices

**Result**: Each iteration improves on previous work

### Error Knowledge Base

Build comprehensive error resolution knowledge:
- **First Time**: Debug from scratch, document solution
- **Second Time**: Search error_resolutions, apply known solution
- **Third Time**: Recognize pattern family, solve faster

**Result**: Error resolution time decreases over time

### Workflow Optimization

Improve multi-agent workflows through learning:
- **Initial**: Research (30 min) → Development (90 min) → Testing (45 min) = 165 min
- **Optimized**: Review past work (5 min) → Development (60 min) → Testing (30 min) = 95 min

**Result**: 42% improvement through historical learning

## Best Practices

1. **Always search before starting** - Don't reinvent solutions
2. **Store after every significant task** - Build knowledge continuously
3. **Be specific in episodes** - Generic data isn't useful
4. **Document outcomes** - Success and failure both teach
5. **Capture "why"** - Rationales help future decisions
6. **Use consistent group_ids** - Makes patterns findable
7. **Review trends** - Analyze improvement over time

## Requirements

- Graphiti Memory MCP server must be configured in settings.json
- Access to `mcp__graphiti-memory__add_memory` tool
- Access to `mcp__graphiti-memory__search_memory_facts` tool
- Access to `mcp__graphiti-memory__search_memory_nodes` tool

## Installation

```bash
/plugin install graphiti-plugin@lgates-claude-plugins
```

## Companion Plugins

Works well with:
- **python-plugin** - For Python development patterns
- **typescript-plugin** - For TypeScript development patterns
- **tools-plugin** - For agent coordination patterns
- **testing-plugin** - For test execution and quality analysis

## License

MIT
