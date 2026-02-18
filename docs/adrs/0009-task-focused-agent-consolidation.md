# ADR-0009: Task-Focused Agent Consolidation

## Status

Accepted

## Date

2025-12-27

## Context

The plugin collection had grown to 23 agents across 12 plugins. Analysis revealed several anti-patterns that reduced effectiveness:

### Problems Identified

1. **Organizational mimicry**: Agents modeled after job titles (test-architect, service-designer, ux-implementation) rather than tasks users actually request
2. **Consultant/handoff pattern**: Agents that produced specs and delegated via `@HANDOFF` markers instead of completing work
3. **Overlapping scope**: Multiple agents doing variations of the same thing (code-analysis, code-review, security-audit all reviewing code)
4. **Hypothetical over-engineering**: Agents for scenarios that don't map to real user requests (service blueprints, journey mapping)

### External Influences

- [12-Factor Agents](https://github.com/humanlayer/12-factor-agents) principles, particularly Factor 10: Small, Focused Agents
- Anthropic guidance on using rules + skills + generic subagents over specialized role-agents
- Real-world feedback: "Nobody wants front-end backend split in real companies. The best engineers are those that can do both."

### Key Insight

The question for each agent should be: *"What actual task does a user ask for that invokes this?"*

- "Review my PR" → clear task
- "I need a test-architecture agent to produce a @HANDOFF spec" → nobody says this

## Decision

Consolidate 23 role-based agents into 5 task-focused agents that complete bounded work (3-20 steps) without handoffs.

### Target Architecture

```
agents-plugin/agents/
├── test.md             # Write and run tests (haiku)
├── review.md           # Code/commit/PR review (opus)
├── debug.md            # Diagnose and fix bugs (opus)
├── security-audit.md   # Security vulnerability analysis (opus)
├── performance.md      # Performance analysis (sonnet)
├── refactor.md         # Code refactoring (sonnet)
├── research.md         # Technical research (sonnet)
├── dependency-audit.md # Dependency health checks (haiku)
├── docs.md             # Generate documentation (haiku)
└── ci.md               # Pipeline configuration (haiku)
```

### Model Selection Rationale

Three-tier model palette: opus (deep reasoning), sonnet (moderate judgment), haiku (mechanical tasks).

| Agent | Model | Rationale |
|-------|-------|-----------|
| test | haiku | Straightforward: analyze → write tests → run → report |
| review | opus | Complex reasoning: security analysis, pattern recognition, trade-offs |
| debug | opus | Complex reasoning: root cause analysis, system-level thinking |
| security-audit | opus | Complex reasoning: vulnerability analysis, threat modeling |
| performance | sonnet | Pattern-based analysis: profiling, benchmarking, optimization recommendations |
| refactor | sonnet | Pattern-based restructuring: follows established refactoring patterns |
| research | sonnet | Moderate judgment: research, evaluate, and summarize findings |
| dependency-audit | haiku | Mechanical: scan packages, check versions, report CVEs |
| docs | haiku | Straightforward: analyze code → generate documentation |
| ci | haiku | Straightforward: understand requirement → write config |

### Consolidation Mapping

| Deleted Agents | Consolidated To |
|----------------|-----------------|
| test-architecture, test-runner | test |
| code-analysis, code-review, security-audit, commit-review | review |
| system-debugging, linter-fixer, code-refactoring | debug |
| documentation, research-documentation | docs |
| cicd-pipelines | ci |
| service-design, ux-implementation | deleted (skills cover patterns) |
| typescript-development, javascript-development, rust-development, python-development | deleted (skills cover patterns) |
| architecture-decisions, prp-preparation, requirements-documentation | deleted (planning, not agents) |
| api-integration, dotfiles-manager | deleted (too niche for dedicated agent) |

### Design Principles Applied

1. **Task-oriented, not role-oriented**: Each agent maps to a real user request
2. **Complete the job**: No @HANDOFF patterns; agents finish what they start
3. **Small scope**: 3-20 steps per task
4. **Generic + Skills**: Expertise lives in skills (loaded on demand), agents are task runners
5. **Main Claude as primary implementer**: Agents handle delegated subtasks

## Consequences

### Advantages

- **Clarity**: Users know which agent handles their task
- **Efficiency**: Less context switching, no handoff overhead
- **Maintainability**: 5 agents to maintain instead of 23
- **Cost optimization**: Three-tier model selection — haiku for mechanical tasks, sonnet for moderate reasoning, opus only for deep analysis
- **Reliability**: Smaller scope means fewer opportunities to lose focus

### Disadvantages

- **Less specialized knowledge**: Agents are generalists within their task domain
- **Migration effort**: Expertise from deleted agents needed extraction to skills
- **Learning curve**: Users accustomed to specific agents need to adapt

### Mitigation

- Extract best patterns from deleted agents into skills
- Skills provide specialized knowledge when loaded
- Document mapping from old agents to new ones

## Alternatives Considered

### 1. Keep All Agents, Add Orchestrator

Add a meta-agent to route between existing 23 agents.

**Rejected**: Doesn't solve the fundamental problems (handoffs, overlap, hypothetical scenarios). Adds complexity.

### 2. Reduce to Language-Specific Agents

Keep typescript-developer, python-developer, etc. as the primary agents.

**Rejected**: Languages don't map to tasks. A "typescript developer" still needs to test, review, debug. Task-focus is more natural.

### 3. No Agents, Just Skills

Eliminate agents entirely; use skills loaded into main Claude.

**Rejected**: Some tasks benefit from dedicated context and bounded scope. Agents save main context for orchestration.

## Related Decisions

- ADR-0001: Plugin-Based Architecture
- ADR-0002: Domain-Driven Plugin Organization

## References

- [12-Factor Agents - Factor 10](https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-10-small-focused-agents.md)
- [Anthropic: Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)
