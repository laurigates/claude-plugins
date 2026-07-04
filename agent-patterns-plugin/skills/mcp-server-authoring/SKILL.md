---
name: mcp-server-authoring
description: FastMCP authoring for Python MCP servers — tools, resources, prompts, TDD, release-please. Use when building or extending an MCP server, adding a tool/resource, or scaffolding a new server.
user-invocable: false
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(uv *), Bash(pytest *)
created: 2026-06-17
modified: 2026-07-04
reviewed: 2026-07-04
---

# MCP Server Authoring

Producer-side patterns for **building** a Python Model Context Protocol server
with the official SDK's `FastMCP` (or the standalone `fastmcp` package). Applies
to any Python MCP server you own — the guidance is portfolio-independent.

For *consuming* / installing servers into a project, this is the wrong skill —
see the table below.

## When to Use This Skill

| Use this skill when... | Use a different skill when... |
|------------------------|-------------------------------|
| Building or scaffolding a new MCP server | Installing an existing server into `.mcp.json` → `agent-patterns-plugin:mcp-management` |
| Adding a tool / resource / prompt to a server | Running MCP compliance checks on a project → `configure-plugin:configure-mcp` |
| Wiring a server's tests, lint, release-please | An agent calls 50+ MCP tools and needs the code-execution pattern → `agent-patterns-plugin:mcp-code-execution` |
| Choosing transport (stdio vs HTTP) for a server you own | Managing OAuth for a remote server you consume → `mcp-management` |

## The Build Path

Build a server in this order. Each step's *why* is the load-bearing part — it is
what lets you generalize past the example.

### Step 1 — Scaffold the project

```bash
uv init --package my-server && cd my-server
uv add "mcp[cli]"          # bundled SDK; or `uv add fastmcp` for the standalone package
uv add --group dev pytest ruff ty
```

**Why `uv init --package`**: it lays down a `src/` package + `pyproject.toml`
with a console-script entrypoint, so the server installs as a real command
(`uvx my-server`) rather than a loose script. That is what a consumer's
`.mcp.json` will invoke.

**Why one dependency choice up front**: `FastMCP` ships two ways — bundled in the
official `mcp` SDK (`from mcp.server.fastmcp import FastMCP`) and as the
standalone `fastmcp` package (`from fastmcp import FastMCP`). They expose the
same high-level decorator API; pick one and pin it in `pyproject.toml` so the
import path is stable. Prefer the bundled SDK unless you need a standalone-only
feature.

### Step 2 — Write the entrypoint as a thin shim

```python
# src/my_server/__init__.py
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("my-server")  # the name surfaced to the client


def main() -> None:
    mcp.run()  # defaults to stdio transport
```

**Why a thin shim**: the `FastMCP` instance + `mcp.run()` is the MCP *boundary*,
not where logic lives. Keep business logic in plain, separately-tested modules
the tools call. Decorators that accrete logic become untestable — you end up
needing a live MCP client to exercise a pure computation.

### Step 3 — Add a tool

A tool is an action or computation the model invokes. Write it as a typed,
docstringed plain function, then decorate it:

```python
from my_server.catalog import list_items  # plain, tested module

@mcp.tool()
def list_catalog(active_only: bool = True) -> list[dict]:
    """List catalog items. The first docstring line becomes the tool description."""
    return list_items(active_only=active_only)
```

**Why type hints are the contract**: the SDK derives the tool's JSON input schema
from the annotations. Precise types (`Literal`, enums, `pydantic` models) give the
model a schema it can fill correctly; a bare `dict`/`Any` gives it nothing to
validate against.

**Why the docstring is user-facing**: the first line becomes the description the
model reads when *selecting* the tool. Write it as intent ("List catalog items"),
not implementation.

**Why you fail loudly**: raise on bad input and let the SDK surface the error.
Returning a sentinel (`None`, `{"error": ...}`) forces the model to interpret an
ad-hoc convention instead of seeing a clean error.

### Step 4 — Add resources and prompts (when they fit)

| Primitive | Decorator | Use for |
|-----------|-----------|---------|
| **Resource** | `@mcp.resource("scheme://{id}")` | Read-only data the client fetches by URI; path params map to function args |
| **Prompt** | `@mcp.prompt()` | Reusable prompt templates the client surfaces; returns a string or message list |

```python
@mcp.resource("item://{item_id}")
def get_item(item_id: str) -> dict:
    """Fetch one catalog item by id."""
    return load_item(item_id)
```

**Why the split matters**: a *tool* is a verb the model calls to act; a *resource*
is a noun the client reads by URI without model action. Modeling read-only data as
a resource keeps it out of the tool-selection surface, so the model isn't offered a
"tool" whose only job is to fetch. See `REFERENCE.md` for the full primitive table.

### Step 5 — Test the function, not the decorator (TDD)

RED → GREEN → REFACTOR against the underlying function:

```python
# tests/test_catalog.py
def test_list_catalog_filters_inactive(fake_store):
    fake_store.seed([{"id": 1, "active": True}, {"id": 2, "active": False}])
    assert [i["id"] for i in list_items(active_only=True)] == [1]
```

1. Write the failing test against the plain function.
2. Implement the minimum logic; decorate it with `@mcp.tool()`.
3. Refactor while green.

**Why test the plain function**: the decorator is a thin registration wrapper —
exercising it needs a live MCP session and tests the SDK, not your logic. Testing
the underlying function is fast and deterministic. Reserve a single
`integration`-marked end-to-end test for the live-backend path (a real API,
Ollama, a database), and exclude it from the fast quality gate.

### Step 6 — Wire lint, types, and release

| Concern | Tool | Command |
|---------|------|---------|
| Deps / venv | `uv` + `pyproject.toml` + `uv.lock` | `uv sync --group dev` |
| Lint + format | `ruff` | `uv run ruff check . && uv run ruff format .` |
| Type check | `ty` (or `mypy`) | `uv run ty check .` |
| Tests | `pytest` | `uv run pytest -m "not integration"` |
| Release | release-please (conventional commits) | automated on push to `main` |

**Why conventional commits**: they drive release-please's version bumps —
`feat:` minor, `fix:` patch, `feat!:` major. Hand-editing `CHANGELOG.md` or the
`version` field fights the automation; let the commit history be the source of
truth.

### Step 7 — Choose transport before you ship

| Transport | When | Run |
|-----------|------|-----|
| **stdio** | Local servers the client launches as a subprocess | `mcp.run()` or `mcp.run(transport="stdio")` |
| **HTTP** | Remote / shared servers reachable over the network | `mcp.run(transport="streamable-http")` |

**Why stdio is the default**: a locally-launched server needs no network, no auth,
and no port — the client owns its lifecycle over stdin/stdout. Reach for HTTP only
when the server must be *shared* (multiple clients, a remote host), which then pulls
in auth and deployment concerns stdio avoids. Consumers register a stdio server in
`.mcp.json` with `command` + `args` and `${VAR}` env references (never hardcoded
secrets) — see `mcp-management` for the consumer side.

## Shipping Checklist

Before a server is done, confirm each — the failure mode after each is what it
guards against:

- [ ] Entrypoint is a console script (`uvx <server>` runs it) — else a consumer's `.mcp.json` can't launch it.
- [ ] Every tool parameter and return is type-annotated — else the model gets an empty input schema.
- [ ] Every tool's first docstring line reads as intent — else tool selection degrades.
- [ ] Tools raise on bad input (no sentinel returns) — else errors reach the model as ambiguous data.
- [ ] Unit tests cover the plain functions; the live-backend path is a single `integration`-marked test — else the fast gate is slow and flaky.
- [ ] `uv run ruff check . && uv run pytest -m "not integration"` is green — the fast quality gate.
- [ ] Transport chosen deliberately (stdio unless the server must be shared).

For the full primitive/transport reference, packaging, and the SDK inspector, see
[REFERENCE.md](REFERENCE.md).

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
