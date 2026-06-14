---
created: 2025-12-16
modified: 2026-06-14
reviewed: 2026-06-14
name: mcp-management
description: Install and configure MCP servers for Claude Code. Use when adding/enabling servers, updating .mcp.json, managing OAuth remote servers, or troubleshooting connections.
user-invocable: false
allowed-tools: Bash(jq *), Bash(find *), Read, Write, Edit, Grep, Glob, AskUserQuestion
---

# MCP Server Management

Expert knowledge for managing Model Context Protocol (MCP) servers on a project-by-project basis, with support for runtime management, OAuth remote servers, and dynamic server discovery.

For server config examples, the OAuth deep-dive, dynamic-discovery detail,
troubleshooting scripts, and full configuration-pattern examples, see
[REFERENCE.md](REFERENCE.md).

## When to Use This Skill

| Use this skill when... | Use configure-mcp instead when... |
|------------------------|------------------------------------|
| Understanding MCP architecture and concepts | Setting up `.mcp.json` for a new project |
| Managing servers at runtime (enable/disable) | Installing new servers interactively |
| Setting up OAuth remote MCP servers | Running compliance checks on MCP configuration |
| Troubleshooting connection failures | Adding specific servers from the registry |
| Implementing `list_changed` dynamic discovery | Generating project standards reports |

## MCP Architecture Overview

MCP connects Claude Code to external tools and data sources via two transport types:

| Transport | Usage | Auth | Configuration |
|-----------|-------|------|---------------|
| **Stdio** (local) | Command-based servers via `npx`, `bunx`, `uvx`, `go run` | None needed | `.mcp.json` |
| **HTTP+SSE** (remote) | URL-based servers hosted externally | OAuth 2.1 | `.mcp.json` with `url` field |

Local servers declare a `command` + `args`; remote servers declare a `url` +
`headers` (with `${VAR_NAME}` token references, never hardcoded). See
[REFERENCE.md → Server configuration examples](REFERENCE.md#server-configuration-examples).

## Runtime Server Management

### `/mcp` Commands (Claude Code 2.1.50+)

Manage servers without editing configuration files:

| Command | Description |
|---------|-------------|
| `/mcp` | List all configured MCP servers and their connection status |
| `/mcp enable <server>` | Enable a server for the current session |
| `/mcp disable <server>` | Disable a server for the current session (session-scoped only) |

**Note**: Enable/disable are session-scoped. Edit `.mcp.json` for permanent changes.

### Check Server Status

```bash
jq -r '.mcpServers | keys[]' .mcp.json   # List configured servers
jq '.mcpServers.context7' .mcp.json      # Verify a server's config
```

## OAuth Remote Servers (2.1.50+)

Remote HTTP+SSE servers use OAuth 2.1: Claude Code discovers metadata from
`/.well-known/oauth-authorization-server` (cached per URL), the user authorizes
in-browser once, and **step-up auth** re-prompts when a tool needs elevated
scope. To refresh stale OAuth config, `/mcp disable` then `/mcp enable` the
server. Full flow, step-up detail, and caching behavior in
[REFERENCE.md → OAuth support](REFERENCE.md#oauth-support-for-remote-mcp-servers).

## Dynamic Tool Discovery (`list_changed`)

Servers declaring `{"tools": {"listChanged": true}}` push
`notifications/tools/list_changed` when their tool set changes, and Claude Code
refreshes that server's tools **without a session restart** — useful for servers
exposing project-context-specific tools. Same pattern for `resources` and
`prompts`. Subscription is automatic; no client config needed. See
[REFERENCE.md → Dynamic tool discovery](REFERENCE.md#dynamic-tool-discovery-list_changed).

## Troubleshooting

Common failure modes and the diagnostic scripts for each (server won't connect,
missing env vars, OAuth issues, the SDK MCP race condition) are in
[REFERENCE.md → Troubleshooting scripts](REFERENCE.md#troubleshooting-scripts).
Quick OAuth triage:

| Symptom | Likely Cause | Action |
|---------|-------------|--------|
| Authorization prompt repeats | Token not persisted | Check token storage permissions |
| Step-up auth loop | Scope mismatch | Revoke and re-authorize |
| Discovery fails | Server down or URL wrong | Verify server URL and connectivity |
| Cache stale | Server changed OAuth config | Disable/enable server to refresh |

## Configuration Patterns

Three scopes, each with a worked `.mcp.json` / `settings.json` / `plugin.json`
example in [REFERENCE.md → Configuration patterns](REFERENCE.md#configuration-patterns):

- **Project-scoped** (recommended) — `.mcp.json` at project root; `.gitignore` it for personal configs or track for team configs.
- **User-scoped** (personal) — `~/.claude/settings.json` for servers available everywhere.
- **Plugin-scoped** — declared in `plugin.json` (or referenced via `"mcpServers": "./.mcp.json"`).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status check | `jq -c '.mcpServers \| keys' .mcp.json 2>/dev/null` |
| Validate JSON | `jq empty .mcp.json 2>&1` |
| List env vars needed | `jq -r '.mcpServers[] \| .env // {} \| keys[]' .mcp.json 2>/dev/null \| sort -u` |
| Check specific server | `jq -e '.mcpServers.context7' .mcp.json >/dev/null 2>&1 && echo "installed"` |
| Find servers in plugin | `find . -name '.mcp.json' -maxdepth 2` |

## Quick Reference

### Server Types by Transport

| Type | When to Use | Example |
|------|-------------|---------|
| `command` (stdio) | Local tools, no auth needed | `bunx`, `npx`, `uvx`, `go run` |
| `url` (HTTP+SSE) | Remote hosted servers, OAuth needed | `https://...` |

### Key Files

| File | Purpose |
|------|---------|
| `.mcp.json` | Project-level MCP server config (team-shareable) |
| `~/.claude/settings.json` | User-level MCP server config (personal) |
| `plugin.json` | Plugin-level MCP server declarations |
