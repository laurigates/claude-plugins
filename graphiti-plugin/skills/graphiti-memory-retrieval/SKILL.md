---
name: graphiti-memory-retrieval
description: |
  Search and retrieve information from Graphiti Memory graph database. Covers
  search_memory_facts, search_memory_nodes, query construction, and group filtering.
  Use when user mentions Graphiti search, memory retrieval, finding past work,
  searching knowledge graph, or querying episodic memory.
---

# Graphiti Memory Retrieval

## Description

Techniques for searching and retrieving information from Graphiti Memory. Provides proven search patterns for finding similar past work, error solutions, node summaries, and learning from historical data.

## When to Use

Automatically apply this skill when:
- Starting tasks similar to previous work
- Encountering errors that may have been seen before
- Looking for past patterns and solutions
- Need to understand entity relationships
- Building on proven approaches
- Analyzing trends across sessions

## Core Search Types

**Facts Search**: Find specific relationships between entities
- "Agent X solved problem Y using approach Z"
- "Configuration A causes error B"
- "Pattern C appears in successful projects"

**Node Search**: Get comprehensive entity summaries
- All relationships for an entity
- How entities connect across episodes
- Holistic view of patterns

## Search Patterns

### Pattern 1: Search for Similar Past Work

Before starting, search for similar tasks:

```python
# Search for similar operations
mcp__graphiti-memory__search_memory_facts(
    query="FastAPI async database connection setup with PostgreSQL",
    group_ids=["python_development", "agent_executions"],
    max_facts=5
)

# Use results to:
# - Understand approach that worked before
# - Avoid past mistakes
# - Estimate time based on previous similar work
```

**When to use**: Before starting new work
**Value**: Learn from past successes, avoid repeating mistakes

### Pattern 2: Search for Error Patterns

When encountering errors, search knowledge base:

```python
# Search for similar errors
mcp__graphiti-memory__search_memory_facts(
    query="PostgreSQL connection pool exhausted timeout",
    group_ids=["error_resolutions"],
    max_facts=3
)

# Use results to:
# - Apply known solutions
# - Avoid trying failed approaches
# - Understand root causes faster
```

**When to use**: When encountering errors
**Value**: Faster resolution using known solutions

### Pattern 3: Search for Node Summaries

Get comprehensive view of entity relationships:

```python
# Search for patterns across entity relationships
mcp__graphiti-memory__search_memory_nodes(
    query="FastAPI performance optimization techniques",
    group_ids=["python_development"],
    max_nodes=5
)

# Use results to:
# - See all optimization patterns discovered
# - Understand relationships between techniques
# - Apply holistic approach
```

**When to use**: Need comprehensive understanding
**Value**: See patterns and relationships

### Pattern 4: Search Around Known Good Examples

When you know a specific successful case:

```python
# Search centered on a known good execution
mcp__graphiti-memory__search_memory_facts(
    query="async testing patterns",
    center_node_uuid="<uuid_of_successful_project>",
    max_facts=10
)

# Use results to:
# - Find related successful patterns
# - See what worked in conjunction
# - Build on proven approaches
```

**When to use**: Building on known successes
**Value**: Find related winning patterns

### Pattern 5: Entity-Filtered Search

Search for specific types of knowledge:

```python
# Search for user preferences
mcp__graphiti-memory__search_memory_nodes(
    query="coding style preferences for Python",
    entity="Preference",
    max_nodes=5
)

# Search for established procedures
mcp__graphiti-memory__search_memory_nodes(
    query="deployment workflow steps",
    entity="Procedure",
    max_nodes=5
)

# Permitted entity types: "Preference", "Procedure"
```

**When to use**: Looking for specific knowledge types
**Value**: Targeted, relevant results

## Query Construction Best Practices

### Effective Queries

**Good queries** (specific, contextual):
- ✅ "FastAPI async database connection with PostgreSQL and connection pooling"
- ✅ "JWT authentication implementation with refresh tokens"
- ✅ "Rust async error handling with tokio runtime"

**Poor queries** (vague, generic):
- ❌ "database stuff"
- ❌ "auth"
- ❌ "async"

### Query Tips

1. **Include technology names**: "FastAPI", "PostgreSQL", "React"
2. **Add context**: "async", "authentication", "testing"
3. **Specify patterns**: "connection pooling", "JWT tokens", "middleware"
4. **Use domain terms**: "API endpoint", "database migration", "CI/CD"

## Group ID Filtering

Use group IDs to narrow search scope:

```python
# Search specific domain
search_memory_facts(
    query="authentication implementation",
    group_ids=["python_development"],  # Only Python work
    max_facts=5
)

# Search multiple related domains
search_memory_facts(
    query="API authentication",
    group_ids=["python_development", "nodejs_development"],
    max_facts=5
)

# Search by activity type
search_memory_facts(
    query="authentication errors",
    group_ids=["error_resolutions", "security_audits"],
    max_facts=5
)

# Search specific project
search_memory_facts(
    query="deployment issues",
    group_ids=["project_auth_api"],
    max_facts=5
)
```

## Result Interpretation

### Fact Results

Facts contain relationships:
```
Entity A --[relationship]--> Entity B
Example: "FastAPI project" --[uses]--> "PostgreSQL async driver"
```

**Look for**:
- Common patterns across multiple facts
- Successful approaches (outcome: SUCCESS)
- Warnings about failed approaches
- Lessons learned

### Node Results

Nodes contain entity summaries:
```
Entity: "FastAPI Authentication"
Summary: All relationships this entity has
```

**Look for**:
- How entity connects to other concepts
- Frequency of appearance (important patterns)
- Associated lessons and outcomes
- Related best practices

## Search Workflow

### Before Starting Work

1. **Search for similar tasks**
   ```python
   search_memory_facts(
       query="<your task description with tech stack>",
       group_ids=["<relevant domain>"],
       max_facts=5
   )
   ```

2. **Review results** for:
   - Approaches that worked
   - Pitfalls to avoid
   - Time estimates
   - Required resources

3. **Apply insights** to current work

### During Work (Error Encountered)

1. **Search for similar errors**
   ```python
   search_memory_facts(
       query="<error type> <technology> <symptoms>",
       group_ids=["error_resolutions"],
       max_facts=3
   )
   ```

2. **Try known solutions first**
3. **Document if new solution needed**

### After Work (Validating Approach)

1. **Search for similar successful work**
   ```python
   search_memory_nodes(
       query="<technology> <pattern> best practices",
       max_nodes=5
   )
   ```

2. **Compare your approach** to past successes
3. **Note improvements** for future episodes

## Best Practices

1. **Search before starting** - Don't reinvent the wheel
2. **Use specific queries** - Generic queries return generic results
3. **Filter by group_id** - Narrow scope for relevance
4. **Review multiple results** - Patterns emerge from multiple facts
5. **Apply lessons learned** - Use historical knowledge
6. **Combine search types** - Use both facts and nodes searches

## Common Pitfalls

- ❌ Skipping search and reinventing solutions
- ❌ Vague queries returning irrelevant results
- ❌ Not filtering by group_id (too broad)
- ❌ Ignoring lessons from past failures
- ❌ Not checking for similar errors before debugging
- ❌ Only using fact search (missing node relationships)

## Examples

### Example 1: Starting API Development

```
Task: Build REST API with authentication

Search:
mcp__graphiti-memory__search_memory_facts(
    query="REST API authentication implementation FastAPI JWT",
    group_ids=["python_development", "agent_executions"],
    max_facts=5
)

Results show:
- Past FastAPI + JWT implementation (SUCCESS)
- Lesson: "Use HTTP-only cookies for tokens"
- Pitfall: "Avoid storing tokens in localStorage"
- Time: Previous similar task took 90 minutes

Action: Apply proven approach, avoid known pitfalls
```

### Example 2: Resolving Database Error

```
Error: "PostgreSQL connection pool exhausted"

Search:
mcp__graphiti-memory__search_memory_facts(
    query="PostgreSQL connection pool exhausted timeout",
    group_ids=["error_resolutions"],
    max_facts=3
)

Results show:
- Root cause: Pool size too small for async workload
- Solution: Increase pool_size to 20, overflow to 10
- Verification: Load test after change

Action: Apply known solution immediately
```

### Example 3: Understanding Patterns

```
Goal: Optimize FastAPI performance

Search:
mcp__graphiti-memory__search_memory_nodes(
    query="FastAPI performance optimization techniques",
    group_ids=["python_development"],
    max_nodes=5
)

Results show relationships:
- FastAPI connects to async patterns
- Async patterns connect to connection pooling
- Connection pooling connects to performance gains
- Lessons about async context managers

Action: Apply holistic optimization approach
```

## Integration with Other Skills

- **graphiti-episode-storage**: Search episodes you previously stored
- **graphiti-learning-workflows**: Use retrieval in learning workflows
- **agent-coordination-patterns**: Search for successful coordination patterns

## References

- Related Skills: `graphiti-episode-storage`, `graphiti-learning-workflows`
- MCP Server: `graphiti-memory` (configured in settings.json)
- Replaces: `knowledge-graph-patterns` (search sections)
