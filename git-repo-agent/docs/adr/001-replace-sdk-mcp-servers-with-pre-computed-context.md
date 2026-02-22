# ADR-001: Replace SDK MCP Servers with Pre-computed Context

- **Status:** Accepted
- **Date:** 2026-02-22
- **Deciders:** @laurigates

## Context

git-repo-agent uses the Claude Agent SDK (`claude-agent-sdk` 0.1.39) to orchestrate
repository analysis. Three tools — `repo_analyze`, `health_score`, and `report_generate` —
were registered as in-process SDK MCP servers via `create_sdk_mcp_server()`, allowing the
orchestrator agent to call them as MCP tools during execution.

### The Problem

SDK MCP servers cause a race condition that crashes the agent on startup:

```
CLIConnectionError: ProcessTransport is not ready for writing
```

**Root cause:** In `claude-agent-sdk` 0.1.39, `process_query()` calls
`transport.end_input()` immediately after writing the user message to stdin
(`client.py:134`). This closes the stdin pipe. However, the CLI subprocess
concurrently sends MCP initialization control requests (via stdout) that require
responses back over stdin. By the time the SDK processes these requests and
attempts to write the response, stdin is already closed.

The race condition sequence:

```
SDK → CLI:  initialize request
CLI → SDK:  initialize response  ✓
CLI → SDK:  mcp_message (repo-tools initialize)  ← async, in task group
SDK → CLI:  user message
SDK:        end_input()  → stdin closed
SDK:        handle mcp_message → tries to write response → FAILS
```

This is reproducible 100% of the time when any SDK MCP server is configured.
Without MCP servers, the SDK works correctly (agents, tool permissions, streaming
all function as expected).

### Investigation Evidence

- Minimal reproduction confirmed: same error with a single MCP tool registered
- Removing MCP servers while keeping agents → works
- Both bundled CLI (2.1.49) and system CLI (2.1.50) exhibit the same behavior
- SDK version 0.1.39 is the latest available on PyPI

## Decision

**Remove SDK MCP servers and pre-compute tool results in the orchestrator before
launching the agent.**

The three MCP tools are deterministic, pure-Python functions that analyze static
repository state. They don't require LLM interaction to produce their output.
Pre-computing their results and embedding them in the agent's prompt is
architecturally superior:

1. **Pre-compute** `analyze_repo()` and `compute_health_score()` in orchestrator Python code
2. **Embed results** as structured data in the system prompt or user message
3. **Remove** `create_sdk_mcp_server()`, MCP tool registrations, and `mcp__repo-tools__*`
   from `allowed_tools`
4. **Keep** the pure Python functions (`analyze_repo`, `compute_health_score`,
   `generate_report`) for direct use by the orchestrator and the `health` command

## Alternatives Considered

### 1. Monkey-patch `end_input()` to no-op when MCP servers exist

- **Rejected:** Fragile workaround that depends on SDK internals; would break on
  SDK updates and masks the real issue.

### 2. Convert MCP tools to external subprocess MCP servers

- **Rejected:** Adds complexity (separate process, stdio transport) for tools that
  are simple synchronous Python functions. Over-engineered for the use case.

### 3. Wait for SDK fix

- **Rejected as sole strategy:** No newer SDK version available. The bug may take
  time to fix upstream. We need a working agent now.

### 4. Embed tool results via Bash tool (agent calls `python -c ...`)

- **Rejected:** Indirect, fragile, and wasteful of LLM turns. The data is
  available before the agent starts — no reason to make it discover it.

## Consequences

### Positive

- **Agent starts with full context** — no wasted LLM turn calling `repo_analyze`
- **Faster execution** — eliminates MCP initialization handshake and tool-call round-trip
- **Simpler architecture** — no MCP protocol overhead for deterministic functions
- **More reliable** — removes the entire class of stdin/control-protocol race conditions
- **`health` command unaffected** — already uses direct Python, not MCP

### Negative

- **Agent loses interactive tool access** — cannot re-analyze during execution
  (acceptable: repo state is static during a single onboarding/maintenance run)
- **Prompt size increases** — embedded JSON adds ~1-2KB to prompt context
  (negligible relative to system prompt size)

### Neutral

- Pure Python tool functions remain unchanged and testable
- `report_generate` can be called post-agent by the orchestrator for final output
- MCP tool decorators (`@tool`) become unused but harmless; can be removed in cleanup

## Follow-up

- [ ] File upstream issue: `claude-agent-sdk` stdin race condition with SDK MCP servers
- [ ] Re-evaluate SDK MCP servers when a fixed SDK version is released
- [ ] Update README.md to reflect architecture change (tools section)
