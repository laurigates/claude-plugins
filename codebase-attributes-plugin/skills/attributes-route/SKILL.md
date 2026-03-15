---
model: sonnet
name: attributes-route
description: Route to specialized agents based on codebase health attributes. Use after /attributes:collect to automatically address findings by severity.
allowed-tools: Read, Glob, Grep, Agent, TodoWrite
args: "[--dry-run] [--focus <category>] [--min-severity <level>]"
argument-hint: "--dry-run"
created: 2026-03-15
modified: 2026-03-15
reviewed: 2026-03-15
---

# /attributes:route

Route to specialized agents based on codebase health attributes.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Have attribute data and want automated remediation | Need to collect attributes first (use `/attributes:collect`) |
| Want severity-based agent prioritization | Know exactly which agent to use |
| Batch-fixing multiple health findings | Fixing a single specific issue |

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--dry-run` | Show routing plan without spawning agents |
| `--focus <category>` | Only route for: docs, tests, security, quality, ci |
| `--min-severity <level>` | Minimum severity: critical, high, medium (default), low |

## Execution

### Step 1: Load Attributes

Read attribute data from one of:
1. `.claude/attributes.json` (if exists)
2. Run `/attributes:collect` to generate fresh data

### Step 2: Filter and Prioritize

1. Filter attributes by `--focus` category if specified
2. Filter by `--min-severity` threshold
3. Group by target agent from the `actions` array
4. Calculate priority per agent using weights: critical=4, high=3, medium=2, low=1
5. Sort agents by descending priority

### Step 3: Display Routing Plan

Show the routing plan:

```
Attribute-Based Routing

Based on attribute analysis, prioritize these agents in order:

1. security (priority 7): .env file committed; No security scanning in CI
2. test_runner (priority 3): No test directory or test files found
3. docs (priority 2): Missing CLAUDE.md
```

If `--dry-run`, stop here.

### Step 4: Execute Routing

For each agent in priority order, spawn the agent with its findings as context:

| Attribute Category | Agent | Condition |
|---|---|---|
| security (critical/high) | security-audit | Always route first |
| tests | test | When test gaps found |
| quality (high+) | refactor | Anti-patterns exceed threshold |
| quality (medium) | review | Code review suggestions |
| docs | docs | Documentation gaps |
| ci | configure | CI configuration gaps |

When spawning each agent, include:
- The specific findings for that agent
- Whether each finding is auto-fixable
- The severity level

### Step 5: Report

After all agents complete, summarize:
- Which agents were invoked
- Which findings were addressed
- Remaining findings that need manual attention

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Preview routing | `/attributes:route --dry-run` |
| Security only | `/attributes:route --focus security` |
| Critical only | `/attributes:route --min-severity critical` |
| Full remediation | `/attributes:route` |
