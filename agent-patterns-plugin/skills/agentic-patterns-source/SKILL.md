---
model: haiku
created: 2026-01-26
modified: 2026-02-05
reviewed: 2026-01-26
name: agentic-patterns-source
description: |
  Look up proven AI agent design patterns from agentic-patterns.com. Use when you need
  inspiration for how to structure an agent workflow, want to implement a feedback loop
  or context window management strategy, are deciding between agent architectures, or
  need reference implementations for patterns like chain-of-thought, ReAct, or tool use.
allowed-tools: WebFetch, WebSearch, Task
---

# Agentic Patterns Source

## Overview

[Awesome Agentic Patterns](https://agentic-patterns.com/) is a curated catalog of production-ready AI agent patterns. It bridges the gap between toy demos and production systems by documenting repeatable solutions that teams are actually using.

**Primary URL**: https://agentic-patterns.com/

## When to Use This Skill

| Use this skill when... | Use other skills when... |
|------------------------|-------------------------|
| Designing multi-agent orchestration | Implementing Claude Code-specific hooks (`claude-hooks-configuration`) |
| Solving context window limitations | Writing custom agent definitions (`custom-agent-definitions`) |
| Implementing feedback/self-correction loops | Creating file-based coordination (`agent-file-coordination`) |
| Researching security/sandboxing patterns | Setting up MCP servers (`mcp-management`) |
| Need production-tested patterns with references | Need Claude Code workflow patterns (`multi-agent-workflows`) |

## Pattern Categories

### 1. Context & Memory

Managing limited context windows through curation, caching, and episodic memory.

**Key Patterns:**
- Context Window Auto-Compaction
- Progressive Disclosure for Large Files
- Semantic Context Filtering
- Self-Identity Accumulation

**When to research:** Context limits affecting performance, memory persistence needs, large codebase navigation.

### 2. Feedback Loops

Self-healing mechanisms, CI integration, and iterative refinement.

**Key Patterns:**
- Self-correction loops
- CI integration patterns
- Iterative refinement workflows

**When to research:** Implementing retry logic, self-healing agents, continuous improvement cycles.

### 3. Learning & Adaptation

Reinforcement fine-tuning and skill library evolution.

**Key Patterns:**
- Memory Reinforcement Learning (MemRL)
- Skill Library Evolution

**When to research:** Agents that improve over time, skill accumulation, adaptive behavior.

### 4. Orchestration & Control

Task decomposition, multi-agent coordination, and tool routing.

**Key Patterns:**
- Planner-Worker Separation for Long-Running Agents
- Lane-Based Execution Queueing
- Custom Sandboxed Background Agent
- Tool routing patterns

**When to research:** Complex multi-step tasks, parallel agent execution, long-running operations.

### 5. Reliability & Eval

Testing harnesses, logging, and reproducibility safeguards.

**Key Patterns:**
- Failover-Aware Model Fallback
- Testing harnesses
- Observability patterns

**When to research:** Production reliability, testing agent behavior, debugging failures.

### 6. Security & Safety

Sandboxing, PII protection, and deterministic scanning.

**Key Patterns:**
- External Credential Sync
- Sandboxed Tool Authorization
- PII protection patterns

**When to research:** Secure agent execution, credential management, data protection.

### 7. Tool Use & Environment

Shell integration, browser automation, and API design.

**Key Patterns:**
- Intelligent Bash Tool Execution
- Browser automation patterns
- API design for agents

**When to research:** Tool integration, shell command patterns, API consumption.

### 8. UX & Collaboration

Human handoffs, async workflows, and transparency mechanisms.

**Key Patterns:**
- Human-in-the-loop patterns
- Async workflow management
- Transparent reasoning displays

**When to research:** User interaction design, approval workflows, explainability.

## Research Workflow

### Finding Patterns for a Specific Challenge

1. **Search the catalog**
   ```
   WebSearch: site:agentic-patterns.com {challenge_keywords}
   ```

2. **Fetch pattern details**
   ```
   WebFetch: https://agentic-patterns.com/patterns/{category}/{pattern-name}
   Prompt: Extract the pattern description, implementation guidance, and referenced examples
   ```

3. **Cross-reference with local skills**
   - Compare with existing agent-patterns-plugin skills
   - Identify gaps or enhancement opportunities

### Exploring a Category

```
WebFetch: https://agentic-patterns.com/
Prompt: List all patterns in the {category} category with brief descriptions
```

### Staying Current

The site actively maintains patterns with NEW and UPDATED badges:

1. **Check for new patterns**
   ```
   WebFetch: https://agentic-patterns.com/
   Prompt: List patterns marked as NEW or UPDATED in the past month
   ```

2. **Review for applicability**
   - Does this pattern address a gap in our plugin?
   - Can we adapt it to Claude Code workflows?
   - Should we create a new skill based on this pattern?

## Pattern Applicability to Claude Code

| Site Category | Claude Code Plugin/Skill |
|---------------|-------------------------|
| Context & Memory | Context management in CLAUDE.md, skill loading |
| Feedback Loops | Pre/post hooks, test-driven workflows |
| Orchestration & Control | `multi-agent-workflows`, `delegation-first` |
| Tool Use & Environment | `claude-hooks-configuration`, `mcp-management` |
| Security & Safety | Permission systems, tool restrictions |
| UX & Collaboration | `agent-handoff-markers`, approval workflows |

## Integration with Other Skills

This skill complements:

- **multi-agent-workflows**: Apply catalog patterns to Claude Code agent design
- **agent-coordination-patterns**: Enhance coordination with production patterns
- **delegation-first**: Research delegation patterns from real implementations
- **custom-agent-definitions**: Use patterns to inform agent specialization

## Delegation Pattern

For deep pattern research:

```markdown
Use research-documentation agent for:
- Comprehensive pattern analysis
- Cross-referencing multiple patterns
- Building implementation recommendations

Example delegation prompt:
"Research agentic-patterns.com for patterns related to {challenge}.
Extract implementation guidance and compare with our existing
agent-patterns-plugin skills. Identify patterns we should adopt."
```

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Quick pattern lookup | WebSearch with site filter |
| Category exploration | WebFetch main page, filter by category |
| Deep pattern analysis | Delegate to research agent |
| Staying current | Monthly review of NEW/UPDATED patterns |

## Quick Reference

| Need | Search Query |
|------|-------------|
| Context limits | `site:agentic-patterns.com context window compaction` |
| Multi-agent | `site:agentic-patterns.com orchestration multi-agent` |
| Self-healing | `site:agentic-patterns.com feedback loop self-correction` |
| Security | `site:agentic-patterns.com sandbox authorization` |
| Tool use | `site:agentic-patterns.com tool execution shell` |
