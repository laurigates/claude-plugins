# ADR-003: Switch from query() to ClaudeSDKClient for Interactive Workflows

- **Status:** Accepted
- **Date:** 2026-03-12
- **Deciders:** @laurigates

## Context

The git-repo-agent orchestrator uses the Claude Agent SDK to run workflows (onboard,
maintain, diagnose). Previously, the `_stream_messages()` helper used the SDK's `query()`
function — a unidirectional, fire-and-forget API designed for one-shot queries.

### The Problem

The `maintain` workflow has an interactive step (Step 3) that uses `AskUserQuestion` to
present findings and let the user choose which fixes to apply. After the user responds,
Steps 4–6 should execute (apply fixes, record health history, generate report).

When running via `query()`, the session ends immediately after `AskUserQuestion` tool
calls. Steps 4–6 are skipped entirely.

**Root cause:** `AskUserQuestion` does not work when the Claude Code CLI runs as an SDK
subprocess. The CLI's stdin/stdout are piped for the SDK protocol (JSON messages), so the
CLI cannot prompt the user through the terminal. The tool returns empty/fails silently,
and the model wraps up.

Switching from `query()` to `ClaudeSDKClient` (keeping the connection open) did not fix
this — `AskUserQuestion` still cannot interact with the user through piped I/O regardless
of transport mode.

### Evidence

Observed output from `git-repo-agent maintain` (both with `query()` and `ClaudeSDKClient`):

```
Tool: AskUserQuestion
Tool: AskUserQuestion
Maintenance complete.
Cost: $0.2258
```

The agent called `AskUserQuestion` twice — no questions were displayed, no user input was
collected. The session ended after Step 3 without reaching Steps 4–6.

## Decision

**Replace `AskUserQuestion` with a two-phase Python-orchestrated interaction pattern
using `ClaudeSDKClient`.**

Instead of having the agent handle user interaction (which doesn't work in SDK subprocess
mode), split the workflow into two phases with Python handling the user prompt between
them:

1. **Phase 1** — Agent analyzes and outputs numbered findings, then stops
2. **Python interlude** — `rich.console.input()` prompts the user for selections
3. **Phase 2** — Agent receives user selections via `client.query()` follow-up, executes
   fixes, records health history, generates report

### Implementation

Three coordinated changes:

**`orchestrator.py`** — new `_stream_interactive()` function:

```python
async def _stream_interactive(prompt, options, completion_msg):
    async with ClaudeSDKClient(options) as client:
        # Phase 1: Analysis
        await client.query(prompt)
        async for message in client.receive_response():
            _display_message(message)

        # Python prompts user
        user_input = console.input("Select fixes to apply: ")

        # Phase 2: Execution with user selections
        await client.query(f"The user selected: {user_input}. Execute Steps 4-6.")
        async for message in client.receive_response():
            _display_message(message, completion_msg)
```

`run_maintain()` routes to `_stream_interactive()` for interactive mode, `_stream_messages()`
for auto-fix and report-only modes. `AskUserQuestion` is removed from `allowed_tools`
in interactive mode.

**`maintain.md`** — Step 3 updated:

- Output numbered findings list (no `AskUserQuestion`)
- End response after presenting findings
- Step 4 updated to expect follow-up message with user selections

**`orchestrator.md`** — `AskUserQuestion` remains in available tools list (used by
non-interactive modes and other workflows).

## Alternatives Considered

### 1. Switch to ClaudeSDKClient only (keep AskUserQuestion)

- **Tried and rejected:** `ClaudeSDKClient` keeps the connection open but
  `AskUserQuestion` still cannot interact with the user when the CLI runs as a subprocess
  with piped I/O. The tool fails silently regardless of transport mode.

### 2. Strengthen the prompt to prevent early termination

- **Rejected:** The `maintain.md` prompt already had explicit instructions ("you MUST
  proceed to Step 4"). The model stops because `AskUserQuestion` returns empty, not
  because of insufficient instruction.

### 3. Pre-collect user preferences via CLI flags

- **Rejected:** Users need to see findings before selecting fixes. This would create a
  two-step CLI workflow that the interactive mode already solves in one step.

### 4. SDK MCP server for user interaction

- **Rejected:** SDK MCP servers have the stdin race condition documented in ADR-001. Even
  if `ClaudeSDKClient` avoids the race, adding MCP server complexity for a single
  `input()` call is over-engineered.

## Consequences

### Positive

- Interactive mode works: user sees findings, selects fixes, agent executes them
- User prompt is native Python (rich console) — always works, no SDK dependency
- `ClaudeSDKClient` enables the two-phase pattern via `client.query()` follow-ups
- Same `_stream_messages()` function handles non-interactive workflows unchanged

### Negative

- Interactive flow is split across Python and agent — the agent must output findings in a
  specific numbered format for the Python prompt to make sense
- Two `receive_response()` loops mean two ResultMessages (two cost entries)

### Neutral

- `AskUserQuestion` remains available for non-interactive modes and other workflows
  (onboard, diagnose) where it may be used as a no-op safety valve
- The monkey-patch for `parse_message` applies equally to `ClaudeSDKClient`
- `run_health()` is unaffected — uses direct Python calls

## Relationship to ADR-001

ADR-001 worked around `end_input()` by pre-computing MCP tool results before launching
the agent. This ADR addresses a related but distinct issue: `AskUserQuestion` (and likely
all interactive CLI tools) do not work in SDK subprocess mode because the CLI cannot
access the terminal. The solution follows the same principle — move interaction out of the
agent and into the Python orchestrator.

## Revision 2026-04-12: Two separate sessions, not one multi-turn session

The single-client two-phase pattern regressed. Observed symptom: after the user
selected fixes at the Python prompt, Phase 2 ran but made no tool calls — the
agent emitted a brief terminal response and `ResultMessage`, leaving the
worktree empty. Cost: $3.11 for an analysis-only run that looked successful.

Root cause: the Phase 1 system prompt (`maintain.md` Step 3) anchored the
agent on "end your response after presenting findings". When Phase 2's
follow-up `client.query()` arrived on the same `ClaudeSDKClient`, the model's
prior turn dominated — it summarized and stopped again instead of executing.
Embedded findings still lived in the conversation history, but the "stop"
instruction from the system prompt overrode the follow-up user message in
practice.

The fix is to use **two separate `ClaudeSDKClient` sessions**:

1. Phase 1 runs to `ResultMessage` and the client is torn down. The collected
   assistant text (findings list) is saved in Python.
2. Python prompts the user for selections via `rich.console.input()`.
3. Phase 2 opens a **new** client whose system prompt includes a
   "Phase 2 Override (execution)" section that negates the "stop" directive,
   and whose user prompt embeds the Phase 1 findings list verbatim plus the
   user's selections. The agent starts cold with unambiguous instructions to
   execute tool calls.

Implementation lives in `orchestrator.py`:
- `_build_phase2_prompt(findings_text, user_selection, branch)` — builds the
  user prompt.
- `_phase2_system_prompt(base)` — appends the override block to the system
  prompt.
- `_stream_interactive()` — two `async with ClaudeSDKClient(...)` blocks
  instead of one multi-turn block.

Also silenced a spurious `Task exception was never retrieved:
ProcessError(exit code -15)` warning: the subprocess transport's `close()`
terminates the CLI with SIGTERM after a 5s grace period, and the read
generator's final `_process.wait()` raises `ProcessError` into an
async-generator finalizer that no one awaits. The orchestrator now monkey-
patches `_read_messages_impl` to swallow `exit_code == -15` specifically
(other exit codes still propagate).

## Re-evaluation Triggers

- If `claude-agent-sdk` adds a callback mechanism for `AskUserQuestion` (allowing the SDK
  host to handle user prompts programmatically)
- If `ClaudeSDKClient` introduces breaking changes to its API
- If the maintain workflow is restructured to not require interactive input
