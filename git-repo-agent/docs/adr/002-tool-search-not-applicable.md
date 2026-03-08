# ADR-002: Tool Search Tool Not Applicable to git-repo-agent

- **Status:** Accepted
- **Date:** 2026-03-08
- **Deciders:** @laurigates

## Context

Anthropic released the [Tool Search Tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool)
for the Messages API, which enables Claude to work with hundreds or thousands of
tools by dynamically discovering and loading them on-demand. Instead of loading all
tool definitions into the context window upfront, Claude searches the tool catalog
and loads only the tools it needs.

The feature offers two variants:

- **Regex** (`tool_search_tool_regex_20251119`): Claude constructs regex patterns to search tools
- **BM25** (`tool_search_tool_bm25_20251119`): Claude uses natural language queries to search tools

Tools are marked with `defer_loading: true` to keep them out of context until
discovered. This reduces context bloat (~85% token savings reported) and improves
tool selection accuracy, which degrades beyond 30-50 tools.

We evaluated whether git-repo-agent should adopt this feature.

## Decision

**Do not adopt tool search.** The feature operates at a different abstraction layer
than git-repo-agent and provides no benefit at current tool counts.

### Reason 1: Wrong abstraction layer

git-repo-agent uses the Claude Agent SDK (`claude_agent_sdk.query()`), which wraps
Claude Code's tool routing — not the raw Messages API. The SDK's
`ClaudeAgentOptions.allowed_tools` is a string list resolved internally by Claude
Code. There is no `defer_loading` parameter and no mechanism to pass tool search
configuration through to the underlying Messages API calls.

Adopting tool search would require either:

1. The Agent SDK adding `defer_loading` support — not available, not planned
2. Replacing the Agent SDK with direct Messages API calls — would lose Claude Code's
   built-in tools (Read, Write, Edit, Glob, Grep, Bash) and agent orchestration

### Reason 2: Tool counts are far below threshold

| Component | Tool count | Threshold for benefit |
|-----------|------------|----------------------|
| Orchestrator | 9 tools | 30-50+ |
| Blueprint subagent | 6 tools | 30-50+ |
| Configure subagent | 6 tools | 30-50+ |
| Diagnose subagent | 6 tools | 30-50+ |
| Quality subagent | 6 tools | 30-50+ |
| Security subagent | 6 tools | 30-50+ |

Tool selection accuracy is not a problem at these counts.

### Reason 3: Subagent architecture already solves the same problem

The 7-subagent design (blueprint, configure, diagnose, docs, quality, security,
test_runner) is functionally equivalent to tool search's on-demand loading:

- Each subagent sees only its focused tool set (5-6 tools)
- The orchestrator delegates to the right subagent based on the task
- No single agent is overwhelmed with irrelevant tools

This is the same "just-in-time" principle that tool search implements, applied at
the agent routing level rather than the tool loading level.

## Alternatives Considered

### 1. Add tool search for MCP tools in the diagnose workflow

The diagnose workflow uses 4 GitHub MCP tools (`mcp__github__issue_write`, etc.).
If expanded to include Sentry, Grafana, Slack, PagerDuty, or other observability
MCP servers, tool count could cross the 30-50 threshold.

- **Deferred:** Not needed today. Would require Agent SDK support for `defer_loading`
  on MCP tools, or the Messages API MCP connector (`mcp_toolset` with `default_config`).
  Revisit if/when the diagnose workflow adds more MCP integrations.

### 2. Switch to Messages API directly for tool-heavy workflows

- **Rejected:** Would lose Claude Code's built-in tool implementations and
  permission model. The Agent SDK abstraction provides significant value that
  outweighs theoretical tool search benefits.

### 3. Build a custom tool search using `tool_reference` blocks

The API supports client-side tool search implementations that return
`tool_reference` blocks from a custom tool. Could build an embedding-based search
over the full plugin collection's 300+ skills.

- **Deferred:** Interesting for the broader plugin ecosystem, but not for
  git-repo-agent specifically. Would require a separate service and is out of scope.

## Consequences

### Positive

- **No unnecessary complexity** — avoids adding an abstraction layer that provides
  no measurable benefit
- **Architecture validated** — the subagent pattern already achieves what tool search
  solves, confirming the design in ADR-001 and the original agent decomposition

### Negative

- None at current scale

### Re-evaluation Triggers

Revisit this decision if any of the following occur:

- [ ] Agent SDK adds native `defer_loading` / tool search support
- [ ] A single agent's tool count exceeds 25 (approaching the degradation threshold)
- [ ] The diagnose workflow adds 3+ additional MCP server integrations
- [ ] Anthropic releases tool search support for Claude Code's tool routing layer
