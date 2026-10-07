# MCP Server Authoring — Progress Reporting from Long-Running Tools

Moved verbatim from [SKILL.md](../SKILL.md). Open when a tool can take more than a
few seconds (a model call, a subprocess, a crawl).

### Step 7 — Report progress from any tool that can run long

A tool that takes more than a few seconds — a model call, a subprocess, a crawl —
is a black box to the client. Take a `Context` and report:

```python
from mcp.server.fastmcp import Context

@mcp.tool()
async def analyze(path: str, ctx: Context) -> str:
    """Analyze a repository."""
    files = discover(path)
    for i, f in enumerate(files, 1):
        await ctx.report_progress(i, len(files), f"analyzing {f.name}")   # message shows in the client
        await inspect(f)
    return summarize(files)
```

**Why it is not cosmetic**: progress notifications reset the client's **idle
timeout**. A tool that emits nothing can be aborted for idleness *while it is
still working* (Claude Code: 30 min stdio, 5 min HTTP/SSE). For a single long
`await` with no natural increments, spawn a task that re-reports elapsed time on
an interval — a heartbeat is both a status line and a keepalive.

**What the user actually sees** (verified against Claude Code 2.1.207 — behavior,
not a documented contract): the `message` is rendered on the in-flight tool row,
whitespace-collapsed and truncated at 200 chars.

| You send | Client shows |
|---|---|
| `message` + `progress`/`total` | `analyzing auth.py (42%)` |
| `message` only | `analyzing auth.py` |
| `progress` only | `Processing… 7` |
| nothing | `Calling <server>…` ← the black box |

**Report cost back in the *result*, not the progress line.** Progress reaches only
the user's terminal; **nothing can reach the calling model mid-call**. Token counts,
elapsed time, and anything the agent should reason about must ride back in the tool
result (or its `_meta`), or the agent stays blind to what its own delegation cost.

**Don't reach for the other channels**: `notifications/message` (the `logging`
capability) is *silently dropped* by Claude Code — no handler is registered. For
stdio servers, plain **stderr** is the debug path (`claude --debug mcp`).

`ctx.report_progress` no-ops when the client sends no `progressToken`, so it is
always safe to call. Keep it best-effort: a failed notification must never fail the
tool call it describes.
