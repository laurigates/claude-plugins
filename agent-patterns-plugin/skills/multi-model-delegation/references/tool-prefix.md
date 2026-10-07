# Multi-Model Delegation - Tool Prefix

How to derive the `mcp__<server>__<tool>` prefix for PAL's tools from the
server's registration. Open when a PAL tool name does not resolve.

## The Tool Prefix Is Derived, Not Fixed

PAL's tools are reachable as **`mcp__<server-name>__<tool>`**, where
`<server-name>` is the key the server is **registered under** — not the product
name, and not the binary. That key can live in any registration scope: a
project `.mcp.json`, a **user**-scope entry in `~/.claude.json`
(`claude mcp add -s user …`, which has no `.mcp.json` at all), or a local one.
So read the registration rather than a file — `claude mcp list` is
authoritative in every scope, and `claude mcp get` names the scope that owns it:

```bash
claude mcp list                 # "pal-mcp-server: pal-mcp-server  - ✔ Connected"
claude mcp get pal-mcp-server   # Scope: Project config (shared via .mcp.json)
```

With the common registration `pal-mcp-server`, `chat` is
`mcp__pal-mcp-server__chat`; a repo that registers the same binary under a
different key gets that key in the prefix instead. Every
`mcp__pal-mcp-server__*` name in SKILL.md assumes that registration — substitute
the key `claude mcp list` reports.

If a lookup under the correct prefix still finds nothing, see
[REFERENCE.md](../REFERENCE.md) — that message has a second cause.
