---
name: graphiti-episode-storage
description: |
  Store episodes in Graphiti Memory: agent executions, error resolutions, workflow
  completions, technical decisions. Provides JSON schemas and storage patterns.
  Use when user mentions storing in Graphiti, add_memory, episode storage,
  building knowledge base, or documenting agent work.
---

# Graphiti Episode Storage

## Description

Patterns for storing episodes in Graphiti Memory including agent executions, error resolutions, workflow completions, and technical decisions. This skill provides proven JSON schemas and storage patterns for building institutional knowledge.

## When to Use

Automatically apply this skill when:
- Completing significant agent work
- Resolving non-trivial errors
- Finishing multi-step workflows
- Making important technical decisions
- Need to document execution for learning
- Creating audit trails

## Core Concept: Episodes

**Episodes** are discrete events stored in Graphiti Memory that get automatically processed into facts and entities:

- Agent executions and their outcomes
- Error resolutions with root causes
- Workflow completions with metrics
- Technical decision rationales

## Episode Storage Patterns

### Pattern 1: Agent Execution Episodes

Store each agent execution for learning and audit:

```python
mcp__graphiti-memory__add_memory(
    name=f"Agent Execution: {agent_name} - {task_summary}",
    episode_body=json.dumps({
        "agent": agent_name,
        "timestamp": datetime.now().isoformat(),
        "task_description": user_request,
        "context_provided": {
            "tech_stack": ["FastAPI", "PostgreSQL"],
            "constraints": ["Must support async", "90% test coverage"]
        },
        "approach_taken": [
            "Researched FastAPI async patterns",
            "Implemented connection pooling",
            "Added pytest-asyncio for testing"
        ],
        "outcome": "SUCCESS|PARTIAL|FAILED",
        "deliverables": [
            "API endpoints in /src/api/",
            "Tests in /tests/",
            "Documentation in /docs/"
        ],
        "lessons_learned": [
            "Async context managers critical for DB connections",
            "pytest-asyncio fixtures simplify testing"
        ],
        "time_spent_minutes": 45,
        "challenges_encountered": [
            "Initial connection pool configuration incorrect"
        ]
    }),
    source="json",
    source_description=f"Agent execution: {agent_name}",
    group_id=f"{agent_name}_executions"
)
```

**When to use**: After every significant agent execution
**Value**: Learn from similar tasks, avoid past mistakes

### Pattern 2: Error Resolution Episodes

Document how errors were resolved:

```python
mcp__graphiti-memory__add_memory(
    name=f"Error Resolved: {error_type} - {solution_summary}",
    episode_body=json.dumps({
        "error_type": "DatabaseConnectionError",
        "context": {
            "tech_stack": ["PostgreSQL", "SQLAlchemy"],
            "environment": "Development"
        },
        "symptoms": [
            "Connection timeouts after 30 seconds",
            "Error: 'pool exhausted'"
        ],
        "root_cause": "Connection pool size too small for async workload",
        "solution_applied": "Increased pool_size to 20, overflow to 10",
        "verification": "No timeouts after load testing",
        "similar_to": "Connection pooling issues seen in project X",
        "prevention": "Always configure pool_size based on expected concurrency"
    }),
    source="json",
    source_description="Error resolution",
    group_id="error_resolutions"
)
```

**When to use**: After resolving non-trivial errors
**Value**: Build error knowledge base, faster future resolution

### Pattern 3: Workflow Execution Episodes

Store complete multi-agent workflow results:

```python
mcp__graphiti-memory__add_memory(
    name=f"Workflow: {workflow_type} - {project_name}",
    episode_body=json.dumps({
        "workflow_type": "api_development",
        "project_name": "User Auth API",
        "duration_minutes": 180,
        "agents_involved": [
            "research-assistant",
            "python-developer",
            "security-auditor",
            "test-architect"
        ],
        "execution_sequence": [
            {"agent": "research-assistant", "duration": 30, "outcome": "success"},
            {"agent": "python-developer", "duration": 90, "outcome": "success"},
            {"agent": "security-auditor", "duration": 45, "outcome": "issues_found"},
            {"agent": "python-developer", "duration": 15, "outcome": "fixes_applied"}
        ],
        "overall_outcome": "SUCCESS",
        "quality_metrics": {
            "test_coverage": "94%",
            "security_issues": "0 high, 2 low",
            "performance": "avg 120ms response time"
        },
        "lessons_learned": [
            "Security audit early prevents rework",
            "Parallel testing during implementation saves time"
        ]
    }),
    source="json",
    source_description="Multi-agent workflow completion",
    group_id="workflow_executions"
)
```

**When to use**: After completing multi-step workflows
**Value**: Optimize workflow patterns, estimate future timelines

### Pattern 4: Decision Rationale Episodes

Document why important decisions were made:

```python
mcp__graphiti-memory__add_memory(
    name=f"Decision: {decision_topic} - {choice_made}",
    episode_body=json.dumps({
        "decision_topic": "API Framework Selection",
        "context": {
            "project_type": "REST API with async I/O",
            "team_expertise": "Python",
            "requirements": ["High performance", "Modern async support"]
        },
        "options_considered": [
            {"option": "Flask", "pros": ["Simple", "Mature"], "cons": ["No async support"]},
            {"option": "FastAPI", "pros": ["Async", "Modern", "Auto docs"], "cons": ["Newer"]},
            {"option": "Django", "pros": ["Full-featured"], "cons": ["Heavy", "Not async-first"]}
        ],
        "decision_made": "FastAPI",
        "rationale": [
            "Async support critical for I/O-heavy workload",
            "Auto OpenAPI docs reduce maintenance",
            "Growing community and adoption"
        ],
        "outcome_months_later": "Excellent performance, team productive"
    }),
    source="json",
    source_description="Technical decision rationale",
    group_id="technical_decisions"
)
```

**When to use**: After making significant technical decisions
**Value**: Remember why decisions were made, inform future choices

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

**Best Practice**: Use descriptive, consistent group IDs for easy searching

## Episode Quality Guidelines

### What to Store

✅ **Store**:
- Agent executions with approach and outcome
- Error resolutions with root cause and fix
- Workflow completions with metrics
- Technical decisions with rationale
- Patterns that emerge from work
- Lessons learned from successes and failures

❌ **Don't Store**:
- Trivial operations (single file edits)
- Duplicate information already stored
- Secrets or sensitive data
- Excessively verbose logs
- Work-in-progress (wait for completion)

### Episode Quality

**Good Episode** (specific, actionable):
```json
{
  "task": "Implement JWT authentication for FastAPI",
  "approach": ["Used PyJWT library", "Added middleware decorator"],
  "outcome": "SUCCESS",
  "lessons": "HTTP-only cookies more secure than localStorage"
}
```

**Poor Episode** (vague, unusable):
```json
{
  "task": "Did some auth stuff",
  "approach": ["Used library"],
  "outcome": "It worked"
}
```

## Best Practices

1. **Store after completion** - Wait until work succeeds before storing
2. **Be specific** - Generic episodes aren't useful for learning
3. **Include context** - Tech stack, constraints, requirements
4. **Document outcomes** - Success/failure with metrics
5. **Capture lessons** - What would you do differently?
6. **Use consistent group IDs** - Makes searching effective
7. **Update over time** - Add "outcome_months_later" insights

## Common Pitfalls

- ❌ Storing episodes without outcomes (premature storage)
- ❌ Vague descriptions that don't help future work
- ❌ Storing failures without documenting what to avoid
- ❌ Not capturing "why" for decisions
- ❌ Overly verbose episodes (should be concise summaries)
- ❌ Inconsistent group_ids making search ineffective

## Integration with Other Skills

- **graphiti-memory-retrieval**: Search stored episodes before starting similar work
- **graphiti-learning-workflows**: Use episodes in learning workflows
- **agent-file-coordination**: Store agent execution episodes after workflows

## References

- Related Skills: `graphiti-memory-retrieval`, `graphiti-learning-workflows`
- MCP Server: `graphiti-memory` (configured in settings.json)
- Replaces: `knowledge-graph-patterns` (episode storage sections)
