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

Do not name a server `anthropic-skills`: that name is reserved, and a server
registered under it lists no skills or prompts (2.1.283).

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

#### Smoke-testing a stdio server by hand

Keep stdin open until every response you need has arrived. A stdio server reads
JSON-RPC from stdin and shuts down at EOF, so a burst pipe —
`printf '%s\n' '<initialize>' '<initialized>' '<tools/list>' | server` — closes
input right after the last write. The `initialize` reply usually makes it back;
the `tools/list` reply often does not, or comes back with **0 tools**, because
the server was already exiting when it got there.

Hold input open with a `sleep` between and after the messages:

```bash
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
INITED='{"jsonrpc":"2.0","method":"notifications/initialized"}'
LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

{ printf '%s\n' "$INIT" "$INITED"; sleep 3; printf '%s\n' "$LIST"; sleep 8; } \
  | uvx <server-package> --transport stdio
```

Lengthen the trailing `sleep` for a slow-starting server, or read responses one
at a time from a client that keeps the pipe open.

A 0-tool `tools/list`, or a request that never gets a response, after a burst
`printf … |` pipe proves nothing about the server. Re-run with input held open
before concluding it exposes no tools. Observed 2026-10-05: a server that
returned 0 tools to the burst pipe listed all 24 when stdin was held open
(laurigates/mcu-tinkering-lab#711). This is the false-negative shape catalogued
in `agent-patterns-plugin:tool-result-traps` — an empty result read as an
absent one.

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

### Client behaviors that look like server bugs

| Symptom | Cause / fix |
|---------|-------------|
| Tool description or server instructions cut off | Capped at 2,048 chars; raise with `CLAUDE_CODE_MAX_MCP_DESCRIPTION_LENGTH` (2.1.280) |
| Server instructions missing from the context budget | `/context` shows MCP server instructions as their own row (2.1.283) |
| Image returned by a tool needed as a file | Images from MCP tools are also saved to a file (2.1.283) |
| Same remote server connected twice | Fixed for the same server spelled with different URLs (2.1.281) |
| Stateless remote server unusable after a brief 404 | Fixed; it recovers (2.1.283) |
| claude.ai connector ignores `MCP_CONNECT_TIMEOUT_MS` | Set `MCP_CONNECTION_NONBLOCKING=0` (2.1.281) |
| Server asks the user to open a URL | URL-mode elicitation, supported on 2026-07-28 protocol connections (2.1.281) |
| Progress lost on a backgrounded tool call | Progress notifications are now kept (2.1.283) |
| Stdio server process left behind at exit | Servers still starting at session end are cleaned up (2.1.283) |

### SDK MCP server race condition (2.1.49/2.1.50)

When using `claude-agent-sdk` 0.1.39 with MCP servers, a known race condition in
SDK-based MCP servers causes `CLIConnectionError: ProcessTransport is not ready
for writing`. Workaround: use pre-computed context or static stdio servers
instead of SDK MCP servers.

Since 2.1.274, a `"type": "sdk"` entry in `.mcp.json`, settings, a plugin or an agent file is skipped with a warning (only an SDK host application can register in-process servers), and Bedrock, Vertex, Foundry and telemetry-disabled installs use the v2 MCP client with direct HTTP servers (opt out: `MCP_SDK_GENERATION=v1` or `MCP_PROTOCOL_NEGOTIATION=legacy`).

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
