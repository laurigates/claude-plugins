---
name: graphiti-learning-workflows
description: |
  Learn from historical data and build institutional knowledge with Graphiti Memory.
  Integrates episode storage and retrieval into learning patterns across sessions.
  Use when user mentions learning workflows, building knowledge over time,
  analyzing past work patterns, or improving from historical data.
---

# Graphiti Learning Workflows

## Description

Workflows for learning from historical data and building institutional knowledge over time. Integrates episode storage and memory retrieval into cohesive learning patterns that improve agent performance across sessions.

## When to Use

Automatically apply this skill when:
- Starting tasks similar to previous work
- Building knowledge over time
- Analyzing trends in development work
- Creating audit trails for compliance
- Improving from past successes and failures
- Recognizing patterns across sessions

## Learning Workflow Stages

### Stage 1: Before Starting Work

**Ask**: "Have I done something like this before?"

**Workflow**:
```
1. Search for similar tasks in relevant group_ids
2. Review past approaches and outcomes
3. Note lessons learned from previous work
4. Apply proven patterns
5. Use proven successful approaches
```

**Example**:
```python
# User asks: "Build REST API with JWT authentication"

# Step 1: Search for similar work
search_memory_facts(
    query="REST API JWT authentication implementation",
    group_ids=["python_development", "agent_executions"],
    max_facts=5
)

# Step 2: Review results
# Found: FastAPI + JWT implementation from 2 months ago
# Outcome: SUCCESS (94% test coverage, 120ms avg response)
# Lessons: "Use HTTP-only cookies", "Async context managers critical"

# Step 3: Apply insights
# - Use FastAPI (proven to work)
# - HTTP-only cookies for tokens
# - Async database connections
# - Start with pytest-asyncio fixtures

# Result: Faster implementation, fewer mistakes
```

### Stage 2: During Work

**Ask**: "Am I encountering a known problem?"

**Workflow**:
```
1. When error occurs, search error_resolutions
2. Check if similar issue solved before
3. Apply known solutions first
4. Try new approaches if no match
5. Document new resolution for future
```

**Example**:
```python
# Error encountered: "PostgreSQL connection pool exhausted"

# Step 1: Search for similar errors
search_memory_facts(
    query="PostgreSQL connection pool exhausted timeout",
    group_ids=["error_resolutions"],
    max_facts=3
)

# Step 2: Found match!
# Root cause: Pool size too small for async workload
# Solution: Increase pool_size to 20, overflow to 10
# Verification: Load test confirms fix

# Step 3: Apply immediately
# Update config, test, verify

# Result: 5-minute fix instead of hours of debugging
```

### Stage 3: After Completing Work

**Ask**: "What should I remember for next time?"

**Workflow**:
```
1. Store execution episode with approach taken
2. Document lessons learned
3. Note what worked well
4. Record challenges and how overcome
5. Update workflow patterns if improved
```

**Example**:
```python
# Just completed: FastAPI authentication implementation

# Step 1: Store episode
add_memory(
    name="Agent Execution: python-developer - FastAPI JWT Auth",
    episode_body=json.dumps({
        "task": "Implement JWT authentication for REST API",
        "approach": ["FastAPI", "PyJWT", "HTTP-only cookies"],
        "outcome": "SUCCESS",
        "lessons_learned": [
            "Async context managers essential for DB",
            "HTTP-only cookies more secure than localStorage",
            "pytest-asyncio fixtures simplify async tests"
        ],
        "time_spent": 45,
        "deliverables": ["/src/api/auth.py", "/tests/test_auth.py"]
    }),
    source="json",
    group_id="python_development"
)

# Result: Knowledge available for next similar task
```

## Learning Patterns

### Pattern 1: Incremental Learning

Build knowledge gradually from each task:

**Week 1**: First FastAPI project
- Store basic implementation patterns
- Document initial lessons

**Week 2**: Second FastAPI project
- Search for first project patterns
- Apply lessons learned
- Store new insights

**Week 3**: Third FastAPI project
- Search both previous projects
- Recognize emerging patterns
- Store refined best practices

**Result**: Each iteration improves on previous work

### Pattern 2: Error Knowledge Base

Build comprehensive error resolution knowledge:

**First Time**: Encounter error
- Debug from scratch
- Document solution
- Store in error_resolutions

**Second Time**: Similar error
- Search error_resolutions
- Apply known solution
- Update if approach improved

**Third Time**: Related error
- Search finds similar patterns
- Recognize pattern family
- Solve faster each time

**Result**: Error resolution time decreases over time

### Pattern 3: Workflow Optimization

Improve multi-agent workflows through learning:

**Initial Workflow**:
```
Research (30 min) → Development (90 min) → Testing (45 min)
Total: 165 minutes
```

**After storing and learning**:
```
Review past similar work (5 min) →
Research only unknowns (15 min) →
Development with proven patterns (60 min) →
Testing with known fixtures (30 min)
Total: 110 minutes (33% faster)
```

**Result**: Workflows optimize through historical learning

### Pattern 4: Decision Consistency

Make consistent technical decisions:

**Problem**: Different projects use different authentication approaches

**Solution**: Store decision rationales
```python
add_memory(
    name="Decision: API Authentication - JWT chosen",
    episode_body=json.dumps({
        "decision": "Use JWT with HTTP-only cookies",
        "rationale": [
            "Stateless scaling",
            "Mobile app compatibility",
            "Better security than localStorage"
        ],
        "alternatives_rejected": [
            "Session cookies - scaling challenges",
            "Basic auth - no token expiry"
        ]
    }),
    group_id="technical_decisions"
)
```

**Result**: Future projects search decisions, maintain consistency

## Integration Workflows

### Workflow 1: Agent Execution with Learning

```
1. Agent receives task
2. Search for similar past work
3. Review approaches and outcomes
4. Execute task using insights
5. Store execution results
6. Note improvements made
```

**Tools used**:
- `search_memory_facts` (before work)
- `add_memory` (after work)

### Workflow 2: Error Resolution with Learning

```
1. Error encountered
2. Search error_resolutions
3. If found: Apply solution
4. If not found: Debug and solve
5. Store resolution details
6. Make available for future
```

**Tools used**:
- `search_memory_facts` (when error occurs)
- `add_memory` (after resolution)

### Workflow 3: Multi-Agent Workflow with History

```
1. Workflow starts
2. Search for similar past workflows
3. Review agent sequence that worked
4. Apply proven coordination patterns
5. Execute workflow
6. Store workflow results with metrics
```

**Tools used**:
- `search_memory_nodes` (workflow patterns)
- `add_memory` (workflow completion)

## Metrics and Insights

Track improvement over time:

**Efficiency Metrics**:
- Time to complete similar tasks (trending down)
- Error resolution time (trending down)
- Code quality metrics (trending up)
- Test coverage (trending up)

**Knowledge Metrics**:
- Episodes stored per domain
- Successful pattern reuse count
- Error resolution knowledge base size
- Decision consistency rate

**Example tracking**:
```python
# Search for all FastAPI projects
search_memory_facts(
    query="FastAPI project implementation",
    group_ids=["python_development"],
    max_facts=20
)

# Analyze:
# - First project: 180 minutes, 85% coverage
# - Second project: 120 minutes, 90% coverage
# - Third project: 90 minutes, 94% coverage
# Insight: 50% improvement through learning
```

## Best Practices

1. **Always search before starting** - Don't reinvent solutions
2. **Store after every significant task** - Build knowledge continuously
3. **Be specific in episodes** - Generic data isn't useful
4. **Document outcomes** - Success and failure both teach
5. **Capture "why"** - Rationales help future decisions
6. **Use consistent group_ids** - Makes patterns findable
7. **Review trends** - Analyze improvement over time
8. **Update episodes** - Add "months later" insights

## Common Pitfalls

- ❌ Not searching before starting (missing available knowledge)
- ❌ Storing vague episodes (unusable for learning)
- ❌ Forgetting to store after work (lost learning opportunity)
- ❌ Inconsistent group_ids (fragmented knowledge)
- ❌ Not documenting failures (losing valuable lessons)
- ❌ Storing too much detail (noise obscures signal)
- ❌ Not reviewing past patterns (missing improvement opportunities)

## Examples

### Example 1: API Development Learning

**First Project** (No history):
```
Task: Build REST API with auth
Time: 180 minutes
Coverage: 85%
Issues: Connection pool problems, test fixture challenges

Store episode with lessons learned
```

**Second Project** (With history):
```
Search: "REST API authentication connection pooling"
Found: First project lessons
Applied: Known solutions
Time: 120 minutes (33% faster)
Coverage: 90%
Issues: Minimal

Store episode noting improvements
```

**Third Project** (Growing knowledge):
```
Search: "REST API authentication"
Found: Both previous projects
Patterns recognized: Async context managers, pytest fixtures
Time: 90 minutes (50% faster than first)
Coverage: 94%
Issues: None

Store episode with refined patterns
```

### Example 2: Error Resolution Learning

**First Occurrence**:
```
Error: PostgreSQL connection timeouts
Debug time: 2 hours
Solution: Increase pool size
Store: Detailed error resolution episode
```

**Second Occurrence** (Similar error):
```
Error: MySQL connection timeouts
Search: "database connection timeout pool"
Found: PostgreSQL solution
Applied: Similar fix
Debug time: 15 minutes (87% faster)
Store: Updated episode with MySQL specifics
```

**Third Occurrence** (Pattern recognition):
```
Error: Redis connection issues
Search: "connection pool exhausted"
Found: Pattern across databases
Recognized: Connection pool sizing principle
Debug time: 5 minutes (95% faster)
Store: General connection pooling best practices
```

## Integration with Other Skills

- **graphiti-episode-storage**: Store episodes for learning
- **graphiti-memory-retrieval**: Search for past knowledge
- **agent-file-coordination**: Document agent learning in workflows
- **agent-coordination-patterns**: Learn optimal coordination patterns

## References

- Related Skills: `graphiti-episode-storage`, `graphiti-memory-retrieval`
- MCP Server: `graphiti-memory` (configured in settings.json)
- Replaces: `knowledge-graph-patterns` (learning workflow sections)
