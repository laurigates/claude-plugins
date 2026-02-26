---
model: sonnet
created: 2025-12-16
modified: 2026-02-26
reviewed: 2026-02-26
name: mcp-management
description: |
  Install and configure Model Context Protocol (MCP) servers for Claude Code projects.
  Use when you want to add or enable an MCP server, connect a tool or integration
  (database, API, file system), update MCP settings in .mcp.json, manage OAuth-authenticated
  remote MCP servers, enable/disable individual servers at runtime, or troubleshoot
  MCP server connection issues.
allowed-tools: Bash(jq *), Bash(find *), Read, Write, Edit, Grep, Glob, AskUserQuestion
---

# MCP Server Management

Expert knowledge for managing Model Context Protocol (MCP) servers on a project-by-project basis, with support for runtime management, OAuth remote servers, and dynamic server discovery.

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

### Local Server (Stdio)

```json
{
  "mcpServers": {
    "context7": {
      "command": "bunx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
```

### Remote Server (HTTP+SSE with OAuth)

```json
{
  "mcpServers": {
    "my-remote-server": {
      "url": "https://mcp.example.com/sse",
      "headers": {
        "Authorization": "Bearer ${MY_API_TOKEN}"
      }
    }
  }
}
```

## Runtime Server Management

### `/mcp` Commands (Claude Code 2.1.50+)

Use these slash commands to manage servers without editing configuration files:

| Command | Description |
|---------|-------------|
| `/mcp` | List all configured MCP servers and their connection status |
| `/mcp enable <server>` | Enable a server for the current session |
| `/mcp disable <server>` | Disable a server for the current session (session-scoped only) |

**Note**: Enable/disable are session-scoped. Edit `.mcp.json` for permanent changes.

### Check Server Status

```bash
# List configured servers
jq -r '.mcpServers | keys[]' .mcp.json

# Verify server config
jq '.mcpServers.context7' .mcp.json
```

## OAuth Support for Remote MCP Servers

Claude Code 2.1.50+ includes improved OAuth handling for remote MCP servers:

### OAuth Flow Overview

Remote MCP servers using HTTP+SSE transport use OAuth 2.1:

1. Claude Code discovers OAuth metadata from `/.well-known/oauth-authorization-server`
2. Discovery metadata is **cached** to avoid repeated HTTP round-trips on session start
3. User authorizes in the browser; token is stored and reused across sessions
4. If additional permissions are needed mid-session, **step-up auth** is triggered

### Step-Up Auth

Step-up auth occurs when a tool requires elevated permissions not granted in the initial OAuth flow:

1. Server signals that additional scope is required
2. Claude Code prompts the user to re-authorize with the expanded scope
3. After re-authorization, the original tool call is retried automatically

### OAuth Discovery Caching

Metadata from `/.well-known/oauth-authorization-server` is cached per server URL. If a remote server changes its OAuth configuration, force a refresh by:

1. Using `/mcp disable <server>` then `/mcp enable <server>` in the session
2. Or restarting Claude Code to clear the cache

### Remote Server Configuration

```json
{
  "mcpServers": {
    "my-service": {
      "url": "https://api.example.com/mcp/sse",
      "headers": {
        "Authorization": "Bearer ${MY_SERVICE_TOKEN}"
      }
    }
  }
}
```

Use `${VAR_NAME}` syntax for environment variable references — never hardcode tokens.

## Dynamic Tool Discovery (`list_changed`)

MCP servers that support the `list_changed` capability can update their tool list dynamically without requiring a session restart.

### How It Works

1. Server declares `{"tools": {"listChanged": true}}` in its capabilities response
2. When the server's tool set changes, it sends `notifications/tools/list_changed`
3. Claude Code refreshes its tool list from that server automatically
4. New tools become available immediately in the current session

### Practical Implications

- **No session restart required** when a server adds or removes tools dynamically
- Useful for servers that expose project-context-specific tools
- For `resources/list_changed` and `prompts/list_changed` — same pattern applies

### Checking Capabilities

The capabilities are declared by the server during initialization. Claude Code subscribes automatically when the server declares support. No client-side configuration is required.

## Troubleshooting

### Server Won't Connect

```bash
# Verify server command is available
which bunx  # or npx, uvx, go

# Test server manually
bunx -y @upstash/context7-mcp  # Should start without error

# Validate JSON syntax
jq empty .mcp.json && echo "JSON is valid" || echo "JSON syntax error"
```

### Missing Environment Variables

```bash
# List all env vars referenced in .mcp.json
jq -r '.mcpServers[] | .env // {} | to_entries[] | "\(.key)=\(.value)"' .mcp.json

# Check which are set
jq -r '.mcpServers[] | .env // {} | keys[]' .mcp.json | while read var; do
  clean_var=$(echo "$var" | sed 's/\${//;s/}//')
  [ -z "${!clean_var}" ] && echo "MISSING: $clean_var" || echo "SET: $clean_var"
done
```

### OAuth Remote Server Issues

| Symptom | Likely Cause | Action |
|---------|-------------|--------|
| Authorization prompt repeats | Token not persisted | Check token storage permissions |
| Step-up auth loop | Scope mismatch | Revoke and re-authorize |
| Discovery fails | Server down or URL wrong | Verify server URL and connectivity |
| Cache stale | Server changed OAuth config | Disable/enable server to refresh |

### SDK MCP Server Race Condition (2.1.49/2.1.50)

When using `claude-agent-sdk` 0.1.39 with MCP servers, a known race condition in SDK-based MCP servers causes `CLIConnectionError: ProcessTransport is not ready for writing`. Workaround: use pre-computed context or static stdio servers instead of SDK MCP servers.

## Configuration Patterns

### Project-Scoped (Recommended)

Store in `.mcp.json` at project root. Add to `.gitignore` for personal configs or track for team configs.

```json
{
  "mcpServers": {
    "context7": {
      "command": "bunx",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    }
  }
}
```

### User-Scoped (Personal)

For servers you want available everywhere, add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "my-personal-tool": {
      "command": "npx",
      "args": ["-y", "my-personal-mcp"]
    }
  }
}
```

### Plugin-Scoped

Plugins can declare MCP servers in `plugin.json`:

```json
{
  "mcpServers": {
    "plugin-api": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/api-server",
      "args": ["--port", "8080"]
    }
  }
}
```

Or via external file: `"mcpServers": "./.mcp.json"`

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
