# MCP Server Management — Reference

Supporting material for [`mcp-management`](SKILL.md). Loaded on demand. The
decision tables, architecture overview, and quick reference live in `SKILL.md`;
this file carries the OAuth deep-dive, dynamic-discovery detail, troubleshooting
scripts, and full configuration-pattern examples.

## Server configuration examples

### Local server (stdio)

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

### Remote server (HTTP+SSE with OAuth)

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

Use `${VAR_NAME}` syntax for environment variable references — never hardcode
tokens.

## OAuth support for remote MCP servers

Remote MCP servers using HTTP+SSE transport use OAuth 2.1 (Claude Code 2.1.50+):

1. Claude Code discovers OAuth metadata from `/.well-known/oauth-authorization-server`
2. Discovery metadata is **cached** to avoid repeated HTTP round-trips on session start
3. User authorizes in the browser; token is stored and reused across sessions
4. If additional permissions are needed mid-session, **step-up auth** is triggered

### Step-up auth

When a tool requires elevated permissions not granted in the initial OAuth flow:

1. Server signals that additional scope is required
2. Claude Code prompts the user to re-authorize with the expanded scope
3. After re-authorization, the original tool call is retried automatically

### OAuth discovery caching

Metadata is cached per server URL. If a remote server changes its OAuth
configuration, force a refresh by `/mcp disable <server>` then
`/mcp enable <server>` in the session, or by restarting Claude Code.

## Dynamic tool discovery (`list_changed`)

Servers that support `list_changed` update their tool list without a session
restart:

1. Server declares `{"tools": {"listChanged": true}}` in its capabilities response
2. When its tool set changes, it sends `notifications/tools/list_changed`
3. Claude Code refreshes its tool list from that server automatically
4. New tools become available immediately in the current session

The same pattern applies to `resources/list_changed` and
`prompts/list_changed`. Capabilities are declared by the server during
initialization; Claude Code subscribes automatically with no client-side
configuration.

## Troubleshooting scripts

### Server won't connect

```bash
# Verify server command is available
which bunx  # or npx, uvx, go

# Test server manually
bunx -y @upstash/context7-mcp  # Should start without error

# Validate JSON syntax
jq empty .mcp.json && echo "JSON is valid" || echo "JSON syntax error"
```

### Missing environment variables

```bash
# List all env vars referenced in .mcp.json
jq -r '.mcpServers[] | .env // {} | to_entries[] | "\(.key)=\(.value)"' .mcp.json

# Check which are set
jq -r '.mcpServers[] | .env // {} | keys[]' .mcp.json | while read var; do
  clean_var=$(echo "$var" | sed 's/\${//;s/}//')
  [ -z "${!clean_var}" ] && echo "MISSING: $clean_var" || echo "SET: $clean_var"
done
```

### OAuth remote server issues

| Symptom | Likely Cause | Action |
|---------|-------------|--------|
| Authorization prompt repeats | Token not persisted | Check token storage permissions |
| Step-up auth loop | Scope mismatch | Revoke and re-authorize |
| Discovery fails | Server down or URL wrong | Verify server URL and connectivity |
| Cache stale | Server changed OAuth config | Disable/enable server to refresh |

### SDK MCP server race condition (2.1.49/2.1.50)

When using `claude-agent-sdk` 0.1.39 with MCP servers, a known race condition in
SDK-based MCP servers causes `CLIConnectionError: ProcessTransport is not ready
for writing`. Workaround: use pre-computed context or static stdio servers
instead of SDK MCP servers.

## Configuration patterns

### Project-scoped (recommended)

Store in `.mcp.json` at project root. Add to `.gitignore` for personal configs
or track for team configs.

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

### User-scoped (personal)

For servers available everywhere, add to `~/.claude/settings.json`:

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

### Plugin-scoped

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
