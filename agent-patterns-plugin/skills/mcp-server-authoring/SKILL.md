---
name: mcp-server-authoring
description: FastMCP authoring for Python MCP servers — tools, resources, prompts, TDD, release-please. Use when building or extending an MCP server, adding a tool/resource, or scaffolding a new server.
user-invocable: false
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(uv *), Bash(pytest *)
created: 2026-06-17
modified: 2026-06-17
reviewed: 2026-06-17
---

# MCP Server Authoring

Producer-side patterns for **building** a Python Model Context Protocol server
with the official SDK's `FastMCP` (or the standalone `fastmcp` package). The
shared conventions behind the portfolio's MCP servers — `kicad-mcp`,
`silverbucket-mcp`, `pal-mcp-server` (and the FVH sibling `podio-mcp`).

For *consuming* / installing servers into a project, this is the wrong skill —
see the table below.

## When to Use This Skill

| Use this skill when... | Use a different skill when... |
|------------------------|-------------------------------|
| Building or scaffolding a new MCP server | Installing an existing server into `.mcp.json` → `agent-patterns-plugin:mcp-management` |
| Adding a tool / resource / prompt to a server | Running MCP compliance checks on a project → `configure-plugin:configure-mcp` |
| Wiring a server's tests, lint, release-please | An agent calls 50+ MCP tools and needs the code-execution pattern → `agent-patterns-plugin:mcp-code-execution` |
| Choosing transport (stdio vs HTTP) for a server you own | Managing OAuth for a remote server you consume → `mcp-management` |

## Server skeleton (FastMCP)

`FastMCP` is bundled in the official `mcp` SDK; the standalone `fastmcp` package
(used by `kicad-mcp`) exposes the same high-level API.

```python
# from the bundled SDK (pal-mcp-server, silverbucket-mcp pin `mcp>=1.0`)
from mcp.server.fastmcp import FastMCP
# kicad-mcp pins the standalone package: from fastmcp import FastMCP

mcp = FastMCP("silverbucket")  # server name surfaced to the client


@mcp.tool()
def list_projects(active_only: bool = True) -> list[dict]:
    """List Silverbucket projects. Docstring becomes the tool description."""
    return _client.projects(active_only=active_only)


if __name__ == "__main__":
    mcp.run()  # defaults to stdio transport
```

Keep the entrypoint a thin shim: `FastMCP` instance + decorated functions +
`mcp.run()`. Business logic lives in plain, separately-tested modules the tools
call — the decorators are the MCP boundary, not where logic accretes.

## Tools, resources, prompts

| Primitive | Decorator | Use for | Notes |
|-----------|-----------|---------|-------|
| **Tool** | `@mcp.tool()` | Actions with side effects / computation the model invokes | Type hints define the input schema; the docstring is the description the model reads |
| **Resource** | `@mcp.resource("scheme://{id}")` | Read-only data the client can fetch by URI | Path params map to function args |
| **Prompt** | `@mcp.prompt()` | Reusable prompt templates the client can surface | Returns a string or message list |

- **Type hints are the contract.** Annotate every parameter and the return — the
  SDK derives the JSON schema from them. Prefer precise types (`Literal`, enums,
  `pydantic` models) over bare `dict`/`Any`.
- **Docstrings are user-facing.** The first line becomes the tool description the
  model selects on; write it as intent, not implementation.
- **Fail loudly.** Raise on bad input; let the SDK surface the error rather than
  returning a sentinel the model has to interpret.

## Transport & registration

| Transport | When | Run |
|-----------|------|-----|
| **stdio** | Local servers launched by the client (the default for all portfolio servers) | `mcp.run()` or `mcp.run(transport="stdio")` |
| **HTTP / SSE** | Remote / shared servers | `mcp.run(transport="streamable-http")` |

Consumers register a stdio server in `.mcp.json` with `command` + `args` and
`${VAR}` env references (never hardcoded secrets) — see `mcp-management` for the
consumer side.

## Portfolio conventions

Every MCP server here follows the same toolchain (matches `pal-mcp-server`'s
`CLAUDE.md` and the repo standards):

| Concern | Tool | Command |
|---------|------|---------|
| Deps / venv | `uv` + `pyproject.toml` + `uv.lock` | `uv sync --group dev` |
| Lint + format | `ruff` | `uv run ruff check . && uv run ruff format .` |
| Type check | `ty` / `mypy` | `uv run ty check .` |
| Tests | `pytest` | `uv run pytest -m "not integration"` |
| Release | release-please (conventional commits) | automated on push to `main` |

- **Conventional commits** drive release-please — `feat:` minor, `fix:` patch,
  `feat!:` major. Don't hand-edit `CHANGELOG.md` or the `version` field.
- **Integration tests that hit a live backend** (Ollama, a real API) are marked
  `integration` and excluded from the fast quality gate.

## TDD for a new tool

RED → GREEN → REFACTOR, testing the underlying function, not the decorator:

```python
# tests/test_projects.py
def test_list_projects_filters_inactive(fake_client):
    fake_client.seed([{"id": 1, "active": True}, {"id": 2, "active": False}])
    assert [p["id"] for p in list_projects(active_only=True)] == [1]
```

1. Write the failing test against the plain function.
2. Implement the minimum logic; decorate it with `@mcp.tool()`.
3. Refactor; keep the suite green. Add an `integration`-marked end-to-end test
   only for the live-backend path.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Fast quality gate | `uv run ruff check . && uv run pytest -m "not integration" -q` |
| Single tool's tests | `uv run pytest tests/test_<tool>.py -q` |
| Fail fast | `uv run pytest -x -q -m "not integration"` |
| Inspect a server's tools | `uv run mcp dev server.py` (SDK inspector) |

## Quick Reference

| Need | Pattern |
|------|---------|
| New action tool | `@mcp.tool()` on a typed, docstringed function |
| Read-only data by URI | `@mcp.resource("scheme://{id}")` |
| Reusable prompt | `@mcp.prompt()` returning a string/message list |
| Local launch | `mcp.run()` (stdio default) |
| Remote launch | `mcp.run(transport="streamable-http")` |
| Input schema | Type hints on every parameter |
| Tool description | First line of the docstring |

## Related

- `agent-patterns-plugin:mcp-management` — installing/configuring servers you *consume* (the inverse of this skill)
- `agent-patterns-plugin:mcp-code-execution` — the code-execution pattern when an agent drives many MCP tools
- `configure-plugin:configure-mcp` — project-level MCP compliance and `.mcp.json` setup
