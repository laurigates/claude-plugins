---
model: opus
description: Analyze all plugins for sub-agent opportunities. Identifies skills with verbose output, gaps in agent coverage, and model selection improvements.
args: "[--focus <plugin-name>]"
allowed-tools: Glob, Grep, Read, Bash(ls *), Bash(wc *), TodoWrite
argument-hint: "analyze all plugins or --focus <plugin-name>"
created: 2026-01-24
modified: 2026-01-24
reviewed: 2026-01-24
---

# /agents:analyze

Analyze the plugin collection to identify where sub-agents would improve workflows by isolating verbose output, enforcing constraints, or specializing behavior.

## Context

- Plugins: !`ls -d */  2>/dev/null | grep -c plugin`
- Existing agents: !`ls agents-plugin/agents/*.md 2>/dev/null | xargs -I{} basename {} .md | tr '\n' ', '`
- Total skills: !`find . -path '*/skills/*/skill.md' 2>/dev/null | wc -l`
- Total commands: !`find . -path '*/commands/*.md' 2>/dev/null | wc -l`

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

#### Model Selection Opportunities

| Assign opus when... | Assign haiku when... |
|---------------------|----------------------|
| Complex reasoning required | Structured/mechanical task |
| Security analysis | Status checks |
| Architecture decisions | Output formatting |
| Debugging methodology | Configuration generation |
| Performance analysis | File operations |

### Step 3: Gap Analysis

Compare identified opportunities against existing agents:

1. **Missing agents**: Skills that have no corresponding agent
2. **Model mismatches**: Agents using wrong model for their task complexity
3. **Tool over-permissions**: Agents with tools they don't need
4. **Consolidation opportunities**: Multiple agents that could be merged
5. **Delegation mapping**: Check if `/delegate` references agents that don't exist

### Step 4: Produce Recommendations

For each recommended new agent, specify:

```markdown
### Proposed: <agent-name>

- **Model**: opus | haiku
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

- **Current model**: X → **Recommended**: Y
- **Reason**: <why the change improves things>
```

### Step 5: Implementation Check

If new agents are recommended, check:
- [ ] Agent name doesn't conflict with existing
- [ ] Agent fills a gap referenced by `/delegate` command
- [ ] Model selection follows haiku-for-mechanical, opus-for-reasoning
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
