# MCP Server Authoring — Reference

Deeper reference for the ordered build path in [SKILL.md](SKILL.md). Loaded on
demand; the SKILL body holds the procedure and the *why*.

## Primitives in full

| Primitive | Decorator | Use for | Notes |
|-----------|-----------|---------|-------|
| **Tool** | `@mcp.tool()` | Actions with side effects / computation the model invokes | Type hints define the input schema; the docstring is the description the model reads |
| **Resource** | `@mcp.resource("scheme://{id}")` | Read-only data the client can fetch by URI | Path params map to function args; the URI template is the addressing scheme |
| **Prompt** | `@mcp.prompt()` | Reusable prompt templates the client can surface | Returns a string or a list of messages |

Design rules that apply to every primitive:

- **Type hints are the contract.** Annotate every parameter and the return — the
  SDK derives the JSON schema from them. Prefer precise types (`Literal`, enums,
  `pydantic` models) over bare `dict`/`Any`.
- **Docstrings are user-facing.** The first line becomes the description the model
  selects on; write it as intent, not implementation.
- **Fail loudly.** Raise on bad input; let the SDK surface the error rather than
  returning a sentinel the model has to interpret.

## Standalone vs bundled FastMCP

| Package | Import | When |
|---------|--------|------|
| Official SDK (`mcp[cli]`) | `from mcp.server.fastmcp import FastMCP` | Default — bundled inspector (`mcp dev`), one dependency |
| Standalone (`fastmcp`) | `from fastmcp import FastMCP` | When you need a standalone-only feature |

Both expose the same high-level decorator API (`@mcp.tool()`, `@mcp.resource()`,
`@mcp.prompt()`, `mcp.run()`). Pin one in `pyproject.toml` so the import path is
stable; mixing them in one project is a source of confusing import errors.

## Transport & registration

| Transport | When | Run | Notes |
|-----------|------|-----|-------|
| **stdio** | Local servers the client launches as a subprocess | `mcp.run()` / `mcp.run(transport="stdio")` | No network, no auth, no port; the client owns the lifecycle |
| **streamable-http** | Remote / shared servers over HTTP | `mcp.run(transport="streamable-http")` | Pulls in auth, a bound port, and deployment; use only when the server must be shared |

Consumer-side registration of a stdio server (`.mcp.json`):

```json
{
  "mcpServers": {
    "my-server": {
      "command": "uvx",
      "args": ["my-server"],
      "env": { "MY_API_TOKEN": "${MY_API_TOKEN}" }
    }
  }
}
```

Reference secrets with `${VAR}` env indirection — never hardcode them. The
consumer side is covered by `agent-patterns-plugin:mcp-management`.

## Toolchain rationale

A common, well-supported Python toolchain for a server:

| Concern | Tool | Command | Why |
|---------|------|---------|-----|
| Deps / venv | `uv` + `pyproject.toml` + `uv.lock` | `uv sync --group dev` | Reproducible, fast; lockfile pins the exact tree |
| Lint + format | `ruff` | `uv run ruff check . && uv run ruff format .` | One tool for both, fast enough for pre-commit |
| Type check | `ty` (or `mypy`) | `uv run ty check .` | Type hints are already the tool schema — check them |
| Tests | `pytest` | `uv run pytest -m "not integration"` | Marker split keeps the fast gate deterministic |
| Release | release-please | automated on push to `main` | Conventional commits drive version + changelog |

**Integration marker convention**: tests that hit a live backend (a real API, a
database, a local model) are marked `integration` and excluded from the fast
quality gate so the inner loop stays deterministic. Run them explicitly with
`uv run pytest -m integration` in CI or before a release.

## Inspecting a server

```bash
uv run mcp dev src/my_server/__init__.py   # launch the SDK inspector UI
```

The inspector lists every registered tool/resource/prompt with its derived
schema, so you can confirm the model sees what you intended before wiring the
server into a client. A tool that shows an empty input schema in the inspector is
the signature of a missing type annotation.

## Packaging & distribution

- The `uv init --package` layout produces a `[project.scripts]` console-script
  entrypoint. Keep `main()` as the entrypoint target so `uvx <server>` and the
  `.mcp.json` `command` resolve the same way.
- Publish to PyPI (or an index) if the server is meant to be installed by name;
  otherwise a `uvx --from git+https://... my-server` reference works for a
  git-hosted server.
- Ship a `README.md` documenting the required env vars and the `.mcp.json`
  snippet a consumer pastes — that snippet is the server's real public API.
