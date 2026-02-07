# ADR-0015: Adopt Agent Teams and Deprecate Manual Orchestration

---
date: 2026-02-07
created: 2026-02-07
modified: 2026-02-07
status: Accepted
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0009
github-issues: []
---

## Context

Claude Code's new **agent teams** feature (documented at code.claude.com/docs/en/agent-teams) provides native support for multi-agent coordination:

| Capability | Description |
|------------|-------------|
| **Lead + Teammates** | One session coordinates, others work independently with full context windows |
| **Shared task list** | With dependencies, self-claiming, file-locking |
| **Inter-agent messaging** | Direct teammate-to-teammate communication |
| **Delegate mode** | Restricts lead to coordination-only tools |
| **Plan approval** | Teammates plan before implementing; lead approves/rejects |
| **TeammateIdle hook** | Fires when a teammate is about to go idle; can assign more work |
| **TaskCompleted hook** | Fires when a task is marked complete; can gate completion with validation |
| **Permissions inheritance** | Teammates inherit lead's permissions; CLAUDE.md loaded by all |

Our `agent-patterns-plugin` (15 skills, 2 hooks) and `agents-plugin` (10 agent definitions) were built to solve these same problems before native support existed. They implement:

- Orchestrator enforcement via PreToolUse hooks
- File coordination and locking conventions
- Handoff markers (@AGENT-HANDOFF-MARKER)
- Delegation patterns
- Context preservation across compaction (PreCompact hook)
- Agent definition templates

Most of this is now redundant with the native agent teams feature.

## Decision

**Adopt native agent teams. Deprecate and remove manual orchestration infrastructure that duplicates built-in functionality. Adapt remaining unique value into agent-teams-compatible patterns.**

### What Gets Removed

| Component | Plugin | Reason |
|-----------|--------|--------|
| `agent-coordination-patterns` skill | agent-patterns-plugin | Native shared task list + messaging replaces this |
| `agent-file-coordination` skill | agent-patterns-plugin | Native file-locking replaces this |
| `agent-handoff-markers` skill | agent-patterns-plugin | Native messaging replaces @AGENT-HANDOFF-MARKER |
| `delegate` skill | agent-patterns-plugin | Native delegate mode replaces this |
| `workflow-primer` skill | agent-patterns-plugin | Native context per teammate replaces handoff primers |
| `orchestrator-enforcement` hook | agent-patterns-plugin | Native delegate mode enforces coordination-only |
| `pre-compact-primer` hook | agent-patterns-plugin | Evaluate: may still be useful for single-session work |
| `handoffs` skill | tools-plugin | @AGENT-HANDOFF-MARKER no longer needed |
| 10 agent definitions | agents-plugin | Convert to teammate templates (see "What Gets Adapted") |

### What Gets Adapted

| Component | Plugin | Adaptation |
|-----------|--------|------------|
| `meta-assimilate` skill | agent-patterns-plugin | Keep — project config analysis isn't replaced by teams |
| `meta-audit` skill | agent-patterns-plugin | Keep — auditing agent configs still valuable |
| `custom-agent-definitions` skill | agent-patterns-plugin | Adapt to document teammate definition patterns |
| Agent definitions (10) | agents-plugin | Convert to teammate spawn templates with appropriate tool restrictions |
| `code-review` skill | code-quality-plugin | Add optional team pattern: spawn security/performance/correctness reviewers |
| `configure-all` skill | configure-plugin | Add optional team pattern: parallel config checks via teammates |
| `test-full` skill | testing-plugin | Add optional team pattern: parallel unit/integration/e2e via teammates |
| `blueprint-prp-execute` skill | blueprint-plugin | Add optional team pattern for large multi-module PRPs |
| `command-analytics` tracking | command-analytics-plugin | Extend to track teammate context in usage analytics |

### What Stays Unchanged

All domain-specific skills (280+), safety hooks (`bash-antipatterns`, `kubectl-context-validation`), language ecosystem plugins, and focused single-agent workflows remain as-is. Agent teams doesn't change how individual skills work — it changes how multiple agents coordinate.

## Consequences

### Positive

- **Reduced maintenance**: Remove ~12 skills and 2 hooks of custom orchestration code
- **Better UX**: Native features are more reliable than convention-based patterns
- **File safety**: Built-in file-locking prevents race conditions (our convention-based approach was advisory only)
- **Simpler mental model**: Users learn one system (agent teams) instead of our custom patterns + subagents
- **Plan approval**: Free validation gate that our hooks approximated but couldn't fully enforce

### Negative

- **Breaking change**: Users relying on `agent-patterns-plugin` orchestration skills need to migrate
- **Feature dependency**: We now depend on agent teams being available (requires Claude Code version with this feature)
- **PreCompact hook gap**: The `pre-compact-primer` hook for single-session context preservation may still be needed — agent teams doesn't address long single-session compaction

### Risks

| Risk | Mitigation |
|------|------------|
| Agent teams feature is experimental/unstable | Phase the migration: deprecate first, remove after feature is GA |
| Users on older Claude Code versions | Keep agent-patterns-plugin available but mark as deprecated |
| PreCompact value loss | Test whether agent teams' per-teammate context makes this unnecessary |

## References

- [Agent Teams Documentation](https://code.claude.com/docs/en/agent-teams)
- [ADR-0009: Task-Focused Agent Consolidation](0009-task-focused-agent-consolidation.md) (prior art for agent organization)
