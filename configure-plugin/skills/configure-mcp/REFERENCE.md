# MCP Server Reference

## Server Configurations

**Core servers come from the policy.** The canonical `.mcp.json` entries for the core servers (`pal`, `context7`, `sequential-thinking`) are the `mcpServers` object of [`configure-plugin/policy/repo-baseline.json`](../../policy/repo-baseline.json). Copy each entry from there verbatim: add a missing one, and replace a `pal` entry in any other form (a bare `pal-mcp-server` command, a `uvx --from git+…` source) with the policy entry. The same policy's `settings.floor.enabledMcpjsonServers` lists the servers `.claude/settings.json` approves.

Use these JSON configurations when adding the other servers to `.mcp.json`:

```json
{
  "playwright": {
    "command": "bunx",
    "args": ["-y", "@playwright/mcp@latest"]
  },
  "github": {
    "command": "go",
    "args": [
      "run",
      "github.com/github/github-mcp-server/cmd/github-mcp-server@latest",
      "stdio"
    ]
  },
  "argocd-mcp": {
    "command": "bunx",
    "args": ["-y", "argocd-mcp@latest", "stdio"],
    "env": {
      "ARGOCD_SERVER": "${ARGOCD_SERVER}",
      "ARGOCD_AUTH_TOKEN": "${ARGOCD_AUTH_TOKEN}"
    }
  }
}
```

Optional per-server key `alwaysLoad` controls whether a server's tools load up
front or wait behind tool search. `"alwaysLoad": false` defers **all** of that
server's tools behind tool search (2.1.287). A tool that sets its own
`_meta['anthropic/alwaysLoad']` to false stays deferred even when its server is
set to `alwaysLoad` (2.1.285), so the server-level key cannot force such a tool
to load.

## Environment Variable Reference

| Server | Required Variables | Where to Set |
|--------|-------------------|--------------|
| `github` | `GITHUB_TOKEN` | `~/.api_tokens` |
| `argocd-mcp` | `ARGOCD_SERVER`, `ARGOCD_AUTH_TOKEN` | project `.env` |
| `sentry` | `SENTRY_AUTH_TOKEN` | `~/.api_tokens` |
| `pal` | Optional: the `${VAR}` keys in the policy entry's `env` (`GEMINI_API_KEY`, `OPENAI_API_KEY`); with neither set, PAL uses only the local endpoint its `CUSTOM_API_URL` names | `~/.api_tokens` |

Use `${VAR_NAME}` references in `.mcp.json` — never hardcode tokens. Claude Code expands variables in a server's `command`, `args`, `env`, `url` and `headers`, and its docs list only two forms, `${VAR}` and `${VAR:-default}`. Write `${VAR}`: a bare `$VAR` is not one of the expanded forms. An unset `${VAR}` with no default is passed to the server as the literal text.

## Available Servers (Full Registry)

**Context & Knowledge:**
- `context7` - Upstash context management (no env vars)

**AI Enhancement:**
- `sequential-thinking` - Enhanced reasoning with sequential thinking (no env vars)

**Testing & Automation:**
- `playwright` - Browser automation and testing (no env vars)

**Version Control:**
- `github` - GitHub API integration (requires `GITHUB_TOKEN`)

**Productivity:**
- `pal` - PAL (Provider Abstraction Layer) - Multi-provider LLM integration. Runs from PyPI as `uvx pal-mcp-server@latest`, so each launch resolves the latest release and nothing is installed beforehand. Takes provider keys and a local endpoint through `env` (see the env-var table). Entry: the policy's `mcpServers.pal`.

**Infrastructure & Monitoring:**
- `argocd-mcp` - ArgoCD GitOps deployment management (requires `ARGOCD_SERVER`, `ARGOCD_AUTH_TOKEN`)
- `sentry` - Sentry error tracking and monitoring (requires `SENTRY_AUTH_TOKEN`)

**Code intelligence** is no longer an MCP concern. Claude Code has a native LSP
client; language servers come from the official `*-lsp` plugins (`rust-analyzer-lsp`,
`typescript-lsp`, `pyright-lsp`, `gopls-lsp`, `clangd-lsp`, ...), enabled per user
rather than per project. Do not add an LSP bridge to `.mcp.json`.

Known trap: those plugins declare `lspServers` only in the marketplace's
`marketplace.json`, while the runtime reads it from the installed plugin's
`.claude-plugin/plugin.json` — so they install inert, with
`getAllLspServers returned 0 server(s)` and no warning. Upstream:
anthropics/claude-code#15148.

## Report Templates

### Compliance Report Format

```
MCP Configuration Report
========================
Project: [name]
Config file: .mcp.json

Installed Servers:
  github                    go run           [✅ CONFIGURED | ⚠️ NEEDS GITHUB_TOKEN]
  playwright                bunx             [✅ CONFIGURED]
  pal                       uvx              [✅ CONFIGURED | ⚠️ NOT POLICY FORM]
  context7                  bunx             [✅ CONFIGURED]
  sequential-thinking       npx              [✅ CONFIGURED]

Environment Variables:
  GITHUB_TOKEN              ~/.api_tokens    [✅ SET | ❌ MISSING]
  GEMINI_API_KEY            ~/.api_tokens    [✅ SET | ⚠️ UNSET (optional, pal)]

Git Tracking:
  .mcp.json                 .gitignore       [✅ IGNORED | ⚠️ TRACKED | ❌ NOT FOUND]

Overall: [X issues found]
```

### Completion Report Format

```
MCP Configuration Complete
==========================

Servers Added:
  ✅ github (requires GITHUB_TOKEN)
  ✅ playwright
  ✅ context7

Environment Variables:
  ⚠️ Set GITHUB_TOKEN in ~/.api_tokens or project .env

Git Tracking:
  ✅ .mcp.json added to .gitignore

Next Steps:
  1. Restart Claude Code to load new MCP servers
  2. Set required environment variables
  3. Verify servers are loaded (check status bar)
```

## Remote MCP Servers (HTTP+SSE with OAuth)

For remote servers using HTTP+SSE transport (Claude Code 2.1.50+):

```json
{
  "my-remote-server": {
    "url": "https://mcp.example.com/sse",
    "headers": {
      "Authorization": "Bearer ${MY_API_TOKEN}"
    }
  }
}
```

### OAuth Authentication Flow

1. Claude Code discovers OAuth metadata from `/.well-known/oauth-authorization-server` (cached per server URL)
2. User authorizes in the browser on first use
3. Token is persisted and reused across sessions
4. Step-up auth triggered mid-session when a tool requires additional scopes

### Remote Server Notes

- Use `${VAR_NAME}` in header values — never hardcode tokens
- Discovery metadata is cached; use `/mcp disable` + `/mcp enable` to force refresh
- Remote servers using OAuth do not need `env` block; use `headers` with Bearer token instead
- Step-up auth is automatic — Claude Code handles re-authorization prompts

## Standards Tracking Template

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  mcp: "2025.1"
  mcp_servers: ["github", "playwright", "context7"]
  mcp_project_scoped: true
```
