# PRP: Agent Teams Migration

**Created**: 2026-02-07
**Modified**: 2026-02-07
**Status**: Draft
**Priority**: P1 - Architecture Simplification
**Related ADRs**: [ADR-0015](../adrs/0015-agent-teams-adoption.md), [ADR-0009](../adrs/0009-task-focused-agent-consolidation.md)

---

## Goal

Migrate from custom multi-agent orchestration infrastructure to Claude Code's native agent teams feature. Remove redundant skills/hooks, convert agent definitions to teammate templates, and add optional team patterns to high-value skills.

### Why

The `agent-patterns-plugin` (16 skills, 2 hooks) and `agents-plugin` (10 agent definitions) implement coordination patterns that are now built into Claude Code. Maintaining custom orchestration code that duplicates native functionality creates:

- **Maintenance burden**: 16 orchestration skills to keep current
- **User confusion**: Two systems for the same purpose (custom patterns vs native teams)
- **Weaker guarantees**: Our convention-based file locking is advisory; native file-locking is enforced
- **Context waste**: Loading orchestration skills into context when native features handle it

### Target Users

- Users currently relying on `agent-patterns-plugin` for multi-agent workflows
- Users of `agents-plugin` agent definitions (test, review, debug, etc.)
- Users of `/handoffs` command for @AGENT-HANDOFF-MARKER management

---

## Success Criteria

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Skills removed | Count of deprecated orchestration skills removed | >= 12 |
| Hooks removed | Custom orchestration hooks removed | 1 (orchestrator-enforcement) |
| Agent conversions | Agent definitions converted to teammate templates | 10/10 |
| Zero regression | Existing non-orchestration skills unaffected | 100% |
| Documentation | Migration guide for existing users | Complete |

### Acceptance Tests

1. All removed skills are gone from the plugin directory and marketplace
2. `agents-plugin` agents work as teammate templates
3. `meta-assimilate` and `meta-audit` skills still function independently
4. `pre-compact-primer` hook evaluated and decision documented
5. Optional team patterns added to `code-review`, `configure-all`, `test-full`
6. `command-analytics-plugin` tracks teammate context when available

---

## Scope

### Phase 1: Remove Redundant Orchestration (agent-patterns-plugin)

Remove skills whose functionality is now native to agent teams:

| Skill | Native Replacement | Action |
|-------|--------------------|--------|
| `agent-coordination-patterns` | Shared task list + messaging | **Remove** |
| `agent-file-coordination` | Native file-locking | **Remove** |
| `agent-handoff-markers` | Native inter-agent messaging | **Remove** |
| `delegate` | Native delegate mode | **Remove** |
| `delegation-first` | Native delegate mode | **Remove** |
| `workflow-primer` | Per-teammate context windows | **Remove** |
| `multi-agent-workflows` | Agent teams configuration | **Remove** |
| `agentic-patterns-source` | Agent teams docs | **Remove** |
| `command-context-patterns` | Agent teams context handling | **Remove** |
| `check-negative-examples` | Plan approval gates bad patterns | **Remove** |
| `wip-todo` | Shared task list | **Remove** |
| `claude-hooks-configuration` | Evaluate: may have non-orchestration value | **Evaluate** |

Keep these skills (unique value not replaced by agent teams):

| Skill | Reason to Keep |
|-------|----------------|
| `meta-assimilate` | Project config analysis — not an orchestration feature |
| `meta-audit` | Agent config auditing — adapt to also audit team configs |
| `custom-agent-definitions` | Adapt to document teammate definition patterns |
| `mcp-management` | MCP server management — orthogonal to agent teams |

#### Hook Changes

| Hook | Action | Rationale |
|------|--------|-----------|
| `orchestrator-enforcement.sh` (PreToolUse) | **Remove** | Native delegate mode enforces coordination-only access |
| `pre-compact-primer.sh` (PreCompact) | **Keep for now** | Still valuable for single-session long-running work where agent teams isn't active. Re-evaluate after testing whether teammate context windows make this unnecessary. |

#### Metadata Updates

- Update `agent-patterns-plugin/plugin.json`: remove orchestration keywords, update description
- Update `.claude-plugin/marketplace.json`: update plugin description
- Update `hooks.json`: remove PreToolUse orchestrator-enforcement entry

### Phase 2: Convert Agent Definitions (agents-plugin)

Convert the 10 agent definitions to teammate-compatible templates:

| Agent | Model | Adaptation Notes |
|-------|-------|------------------|
| `test.md` | haiku | Add tool restrictions (testing tools only). Add `allowedTools` for test frameworks. |
| `review.md` | opus | Natural teammate — can review in parallel with implementation. Add security/performance/correctness specializations. |
| `debug.md` | opus | Keep as subagent template too — debugging is often a focused single task. |
| `ci.md` | haiku | Add workflow file permissions. Restrict to `.github/` directory. |
| `docs.md` | haiku | Add doc directory restrictions. Good teammate for parallel doc generation. |
| `security-audit.md` | opus | Excellent teammate — can audit in parallel with development. |
| `refactor.md` | opus | Add file-lock awareness for safe parallel refactoring. |
| `dependency-audit.md` | haiku | Keep as subagent — typically a quick, focused task. |
| `research.md` | opus | Excellent teammate — isolates web research from main context. |
| `performance.md` | opus | Keep as subagent — profiling output is verbose and focused. |

**Decision per agent**: Convert to teammate template if the task benefits from parallel execution and communication. Keep as subagent if the task is focused, short, and doesn't need coordination.

| Best as Teammate | Best as Subagent | Either |
|------------------|------------------|--------|
| review, security-audit, research, docs | dependency-audit, performance | test, debug, ci, refactor |

### Phase 3: Remove /handoffs (tools-plugin)

| Component | Action | Rationale |
|-----------|--------|-----------|
| `tools-plugin/skills/handoffs/SKILL.md` | **Remove** | @AGENT-HANDOFF-MARKER convention replaced by native messaging |

Update `tools-plugin/plugin.json` and marketplace entry.

### Phase 4: Add Optional Team Patterns

Add team-aware documentation to skills that benefit from parallel execution:

| Skill | Plugin | Team Pattern |
|-------|--------|-------------|
| `code-review` | code-quality-plugin | "For comprehensive review, spawn teammates for security, performance, and correctness review in parallel" |
| `configure-all` | configure-plugin | "Spawn teammates for linting, security, testing, and formatting checks in parallel" |
| `test-full` | testing-plugin | "Spawn teammates for unit, integration, and e2e test suites in parallel" |
| `blueprint-prp-execute` | blueprint-plugin | "For multi-module PRPs, spawn teammates per module with shared task list" |
| `project-continue` | project-plugin | "Spawn research teammate + implementation teammate for large codebases" |
| `docs-generate` | documentation-plugin | "Spawn teammates for parallel doc generation across modules" |

These are documentation additions, not behavioral changes. Skills continue to work without agent teams.

### Phase 5: Extend Analytics

| Component | Change |
|-----------|--------|
| `command-analytics-plugin` | Extend `track-usage.sh` to capture `CLAUDE_TEAM_ROLE` or similar env var when available |

---

## Implementation Order

```
Phase 1 (Remove orchestration)
  ├── Remove 11-12 skills from agent-patterns-plugin
  ├── Remove orchestrator-enforcement hook
  ├── Update plugin.json, marketplace.json, hooks.json
  └── Update release-please configs if plugin scope changes significantly

Phase 2 (Convert agents)
  ├── Add teammate metadata to agent definitions
  ├── Document which agents are best as teammates vs subagents
  └── Update agents-plugin README

Phase 3 (Remove handoffs)
  ├── Remove handoffs skill from tools-plugin
  └── Update tools-plugin metadata

Phase 4 (Add team patterns)
  ├── Add "Agent Teams" section to 6 skills
  └── Documentation only, no behavioral changes

Phase 5 (Extend analytics)
  └── Update track-usage.sh for teammate context
```

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Agent teams feature changes/breaks | Skills reference patterns that no longer work | Phase 4 additions are documentation only — easy to update |
| Users depend on removed orchestration skills | Workflows break | Create migration guide mapping old skills → native features |
| PreCompact hook removal premature | Context loss in long sessions | Keep hook, evaluate separately |
| Agent teams not available in all environments | Teammate templates don't work | Keep subagent compatibility in agent definitions |

---

## Out of Scope

- Removing or changing any domain-specific skills (280+ skills across 25 plugins)
- Modifying safety hooks (bash-antipatterns, kubectl-context-validation)
- Changing language ecosystem plugins (python, typescript, rust)
- Modifying blueprint PRP/ADR validation hooks (domain-specific, not orchestration)
- Refactoring the plugin directory structure itself
