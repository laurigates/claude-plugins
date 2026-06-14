---
name: mcp-code-execution
description: Scaffold the code execution pattern for MCP-based agents. Use when agents call many MCP tools, intermediate data exceeds context, you need loops, or PII must stay out of context.
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-02-08
modified: 2026-06-14
reviewed: 2026-06-14
---

# MCP Code Execution Pattern

Expert knowledge for designing agent systems that generate and execute code to interact with MCP servers, instead of calling tools directly.

For the typed-wrapper code, the six key-pattern examples, and the project
scaffolding steps, see [REFERENCE.md](REFERENCE.md).

## When to Use This Skill

| Use code execution when... | Use direct tool calls / `mcp-management` when... |
|----------------------------|--------------------------------------------------|
| Designing agents that fan out across 10+ MCP servers or 50+ tools | Installing or configuring one or two servers in `.mcp.json` |
| Intermediate results are large (>10K tokens) and would blow context | Results are small and all needed by the model |
| Workflows need loops, retries, or conditionals across tool calls | Linear sequences of 2–3 tool calls |
| PII must not reach the model context | Tool responses contain no sensitive data |
| Tasks benefit from state persistence across runs | Stateless, one-shot operations |
| You want agents to accumulate reusable skills | Fixed, predefined workflows |

## Core Architecture

### How It Works

Instead of loading all MCP tool definitions into context upfront, the agent:

1. **Discovers** available tools by navigating a typed file tree
2. **Generates** TypeScript/Python code that imports and calls typed wrapper functions
3. **Executes** the code in a sandboxed environment
4. **Returns** only filtered/summarized results to the model

This reduces token usage from O(all_tool_definitions) to O(only_relevant_imports).

### File Tree Structure

```
project/
├── servers/
│   ├── google-drive/
│   │   ├── getDocument.ts
│   │   ├── getSheet.ts
│   │   └── index.ts          # Re-exports all tools
│   ├── salesforce/
│   │   └── index.ts
│   └── slack/
│       └── index.ts
├── skills/                    # Agent-accumulated reusable functions
├── workspace/                 # Persistent state between executions
├── client.ts                  # MCP client that routes calls to servers
└── sandbox.config.ts          # Execution environment configuration
```

Each MCP tool gets a **typed wrapper** function the agent imports
(`callMCPTool<T>("server__tool", input)`); the agent writes ordinary code
against those wrappers. See
[REFERENCE.md → Typed wrapper pattern](REFERENCE.md#typed-wrapper-pattern).

## Key Patterns

Six patterns make this efficient — each with a worked code example in
[REFERENCE.md → Key patterns](REFERENCE.md#key-patterns):

| Pattern | What it buys |
|---------|--------------|
| **Progressive tool discovery** | Navigate `servers/` on demand — ~150K tokens → ~2K (98.7% reduction) |
| **Context-efficient filtering** | Filter large datasets in the sandbox; only a summary reaches the model |
| **Native control flow** | Loops/retries/conditionals run in the sandbox, not as chained tool calls |
| **PII tokenization** | The client tokenizes sensitive fields so PII never enters model context |
| **State persistence** | Save intermediate results to `workspace/` for cross-execution continuity |
| **Skill accumulation** | Persist reusable functions to `skills/` for future executions |

## Scaffolding a New Project

The five-step scaffold — identify servers → generate typed wrappers → create the
routing client → configure the sandbox → wire the agent loop — is detailed with
code in [REFERENCE.md → Scaffolding a new project](REFERENCE.md#scaffolding-a-new-project).
The agent loop becomes: explore `servers/` → generate code → execute in sandbox
→ filtered output returns → decide done or iterate.

## Security Checklist

| Item | Status |
|------|--------|
| Sandboxed execution environment | Required |
| Resource limits (CPU, memory, disk) | Required |
| Network isolation (MCP servers only) | Required |
| Execution timeout | Required |
| PII tokenization in MCP client | Recommended for sensitive data |
| Audit logging of all executions | Recommended |
| Read-only access to `servers/` | Recommended |
| Scoped write access to `workspace/` only | Recommended |

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Many tools (50+) | Use progressive discovery via file tree |
| Large intermediate data | Filter in sandbox, return summaries |
| Multi-step workflows | Generate single code block with control flow |
| Sensitive data pipelines | Enable PII tokenization in MCP client |
| Long-running tasks | Use `workspace/` for state persistence |
| Repeated operations | Extract to `skills/` for reuse |

## Quick Reference

### Token Impact

| Approach | Tool definitions | Intermediate data | Total |
|----------|-----------------|-------------------|-------|
| Direct tool calls | All loaded upfront | Passes through context | High |
| Code execution | On-demand discovery | Stays in sandbox | Low |

### When NOT to Use This Pattern

- Simple integrations with 1–3 MCP servers
- All tool responses are small and needed by the model
- No sensitive data in tool responses
- Infrastructure complexity isn't justified (sandbox setup, monitoring)
- Prototype or proof-of-concept stage

## Reference

- [REFERENCE.md](REFERENCE.md) — typed-wrapper code, key-pattern examples, scaffolding steps
- [Anthropic Engineering: Code Execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp)
- [Cloudflare "Code Mode"](https://blog.cloudflare.com/) — independent validation of the same pattern
