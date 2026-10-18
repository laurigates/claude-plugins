---
description: Audit plugins for sub-agent opportunities — verbose skills, coverage gaps, over-permissions. Use when reviewing where sub-agents would help or auditing agents' model tiers.
args: "[--focus <plugin-name>]"
allowed-tools: Glob, Grep, Read, Bash(ls *), Bash(wc *), TodoWrite
model: opus
argument-hint: "analyze all plugins or --focus <plugin-name>"
created: 2026-01-24
modified: 2026-10-18
compatibility: claude-code
reviewed: 2026-09-02
name: agents-analyze
agent: general-purpose
context: fork
---

# /agents:analyze

Analyze the plugin collection to identify where sub-agents would improve workflows by isolating verbose output, enforcing constraints, or specializing behavior.

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| Auditing the whole plugin collection for sub-agent opportunities (verbose-output skills, model mismatches, tool over-permissions) | Auditing a single agent's frontmatter, tool list, and prompt completeness — use `agent-patterns-plugin:meta-audit` |
| Mapping delegation gaps and producing a list of proposed new agents | Authoring the new agent file from that proposal — use `agent-patterns-plugin:custom-agent-definitions` |
| Checking each agent's model fits its task-shape tier | Configuring an agent's hooks, permissions, or settings.json wiring — use `hooks-plugin:hooks-configuration` |
| Focusing the analysis on a single plugin's skills (`--focus <plugin>`) | Coordinating multiple agents at runtime — use `agent-patterns-plugin:agent-teams` or `parallel-agent-dispatch` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List all plugins | `find . -maxdepth 1 -type d -name '*-plugin'` |
| Count skills per plugin | `find <plugin>/skills -name 'SKILL.md' -o -name 'skill.md' \| wc -l` |
| List existing agents | `find agents-plugin/agents -maxdepth 1 -name '*.md'` |
| Check agent model field | `grep -r '^model:' agents-plugin/agents/` |
| Check agent allowed-tools | `grep -r '^allowed-tools:' agents-plugin/agents/` |
| Skill tool permissions | `grep -r '^allowed-tools:' */skills/*/SKILL.md` |

## Context

- Plugin directories: !`find . -maxdepth 1 -type d -name '*-plugin'`
- Existing agents: !`find . -path '*/agents-plugin/agents/*' -maxdepth 3 -name '*.md'`
- Skills: !`find . -path '*/skills/*/skill.md'`
- Skills (user-invocable): !`find . -path '*/skills/*/SKILL.md' -not -path './agents-plugin/*'`

## Parameters

- `$1`: Optional `--focus <plugin-name>` to analyze a single plugin in depth

## Your Task

Perform a systematic analysis of the plugin collection to identify sub-agent opportunities.

### Step 1: Inventory Current State

Scan the repository to build an inventory:

1. **List all plugins** with their skill/command counts
2. **Read existing agents** in `agents-plugin/agents/` to understand current coverage
3. **If `--focus` is provided**, restrict analysis to that plugin only

### Step 2: Identify Sub-Agent Opportunities

For each plugin (or focused plugin), evaluate skills and commands against these criteria:

#### Context Isolation (Primary Value)

Operations that produce verbose output benefiting from isolation:

| Indicator | Examples |
|-----------|----------|
| Build tools | docker build, cargo build, webpack, tsc |
| Infrastructure ops | terraform plan/apply, kubectl describe |
| Test runners | Full test suite output, coverage reports |
| Profiling tools | Flame graphs, benchmark results |
| Security scanners | Vulnerability reports, audit output |
| Log analysis | Application logs, system logs |
| Package managers | Dependency trees, audit results |

#### Constraint Enforcement

Operations that should be limited to specific tools:

| Constraint | Rationale |
|------------|-----------|
| Read-only analysis | Security audit, code review - no writes |
| No network | Pure code analysis tasks |
| Limited bash | Tasks that shouldn't execute arbitrary commands |

#### Model: By Task Shape

Pick the model by task shape (`.claude/rules/agent-development.md` § "Model Selection for Agents"): `opus` for judgement work, `sonnet` with an explicit `effort:` for bounded work whose done check fits in one sentence, `haiku` only as a lean read-only reader whose output a stronger stage checks. A subagent's output re-enters the main loop as a tool result, so a weaker model's output needs a check. Recommend moving an existing agent off opus only with a measurement behind it; otherwise dial `effort` down on the current model.

| Audit finding | Recommendation |
|---------------|----------------|
| Agent file declares `model: opus` or `fable` | OK — no change |
| Agent file declares `sonnet` with an explicit `effort:`, and its Scope is bounded and checked | OK — no change |
| Agent file declares `sonnet` for judgement work (review, audit, multi-file edits, untrusted input) | Flag it — recommend `model: opus` |
| Agent file declares `haiku` outside the lean read-only shape, or `inherit`, or omits `model:` | Flag it — the lint rejects these; recommend an explicit tier |
| Agent file's Scope describes mechanical/high-volume work but sets no `effort:` | Recommend `effort: low` (advisory — not lint-enforced) |

`scripts/check-agent-model.sh` enforces the tier shapes: `sonnet` needs an explicit `effort:`, and `haiku` is accepted only as a lean read-only reader (`omitClaudeMd: true`, Read/Grep/Glob tools, explicit effort). Whether an agent's job fits its tier is this audit's judgement, not the lint's; see `.claude/rules/agent-development.md` § "Model Selection for Agents".

### Step 3: Gap Analysis

Compare identified opportunities against existing agents:

1. **Missing agents**: Skills that have no corresponding agent
2. **Tier mismatches**: An agent whose model does not fit its task shape (judgement work below `opus`, or a tier shape the lint rejects)
3. **Tool over-permissions**: Agents with tools they don't need
4. **Consolidation opportunities**: Multiple agents that could be merged
5. **Delegation mapping**: Check if `/delegate` references agents that don't exist

### Step 4: Produce Recommendations

For each recommended new agent, specify:

```markdown
### Proposed: <agent-name>

- **Model**: <tier> — `opus` by default; `sonnet` + explicit `effort:` only for bounded, checked work
- **Covers plugins**: <list>
- **Context value**: <what verbose output it isolates>
- **Tools**: <minimal set>
- **Constraint**: <read-only, no-network, etc.>
- **Priority**: HIGH | MEDIUM | LOW
- **Rationale**: <why this is better than inline execution>
```

For model/tool corrections to existing agents:

```markdown
### Fix: <agent-name>

- **Current model**: <model> → **Recommended**: <tier>
- **Reason**: <why the tier fits the task shape — e.g. judgement work moved back to opus>
```

### Step 5: Implementation Check

If new agents are recommended, check:
- [ ] Agent name doesn't conflict with existing
- [ ] Agent fills a gap referenced by `/delegate` command
- [ ] Model fits the task-shape tier (`opus` by default; `sonnet` + explicit `effort:` only for bounded, checked work)
- [ ] Tool set is minimal (principle of least privilege)
- [ ] Agent has clear "does / does NOT do" boundaries

## Output Format

```markdown
## Sub-Agent Analysis Report

**Scope**: [All plugins | focused plugin name]
**Date**: [today]
**Plugins analyzed**: N
**Existing agents**: N
**Skills without agent coverage**: N

### Current Coverage Map

| Domain | Agent | Skills Covered | Gaps |
|--------|-------|----------------|------|
| ... | ... | ... | ... |

### Recommended New Agents

[Proposals from Step 4]

### Recommended Fixes

[Model/tool corrections from Step 4]

### Delegation Mapping Updates

[Any updates needed for /delegate command's agent reference table]

### Priority Summary

| Priority | Count | Top Recommendation |
|----------|-------|-------------------|
| HIGH | N | ... |
| MEDIUM | N | ... |
| LOW | N | ... |
```

## Post-Actions

After presenting the analysis:
1. Ask the user if they want to implement any of the recommendations
2. If yes, create the agent files following the existing patterns in `agents-plugin/agents/`
3. Update `agents-plugin/README.md` with new agents
4. Update `/delegate` command's agent reference table if needed
