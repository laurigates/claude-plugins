# Agent-CLI Worktree Safety — Reference

Supporting material for [`agent-cli-worktree-safety`](SKILL.md), loaded on
demand: the Claude Agent SDK (Python) mechanics a CLI of this shape is built
on. The invariants that keep the worktree's contents safe stay in `SKILL.md`.

## `query()` vs `ClaudeSDKClient`

| | `query()` | `ClaudeSDKClient` |
|---|---|---|
| Transport | Unidirectional — closes stdin after prompt | Bidirectional — keeps connection open |
| Follow-up messages | Not supported | `await client.query(follow_up)` |
| Use for | One-shot queries, batch processing | Multi-turn, interactive workflows |

## Two-phase interaction pattern

For interactive workflows that need user input between analysis and execution:

```python
async def _stream_interactive(prompt, options, completion_msg):
    async with ClaudeSDKClient(options) as client:
        # Phase 1: Agent outputs findings and stops
        await client.query(prompt)
        async for msg in client.receive_response():
            display(msg)

        # Python collects user input (works because it's in the host process)
        user_input = console.input("Select fixes to apply (numbers, all, none): ")

        # Phase 2: Send selections, agent executes
        await client.query(f"User selected: {user_input}. Execute steps 4-6.")
        async for msg in client.receive_response():
            display(msg, completion_msg)
```

**Key requirements:**
- Remove `AskUserQuestion` from `allowed_tools` for interactive mode (prevents accidental use)
- Agent prompt must instruct the model to output findings and **stop** — not continue or ask questions
- Phase 2 prompt must tell the model exactly what to do with the user's selections

See [git-repo-agent ADR-003](https://github.com/laurigates/git-repo-agent/blob/main/docs/adr/003-switch-to-claude-sdk-client-for-interactive-workflows.md) for full context and alternatives considered.

## Worktree isolation is not supported by `ClaudeAgentOptions`

The `isolation: worktree` frontmatter field works for Claude Code plugin agents, but `ClaudeAgentOptions` (Python SDK) has no equivalent parameter. The workaround is to manage the worktree in Python before launching the agent:

```python
from pathlib import Path
import subprocess

def create_worktree(repo_path: Path, branch: str) -> Path:
    worktree_path = repo_path / ".worktrees" / branch.replace("/", "-")
    worktree_path.parent.mkdir(parents=True, exist_ok=True)
    base = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=repo_path, capture_output=True, text=True, check=True,
    ).stdout.strip()
    subprocess.run(
        ["git", "worktree", "add", "-b", branch, str(worktree_path), base],
        cwd=repo_path, check=True,
    )
    return worktree_path

# Set cwd to worktree so agent works in isolation
worktree_path = create_worktree(repo_path, "feature/my-branch")
options = ClaudeAgentOptions(cwd=str(worktree_path), ...)
```

**Instruct the agent not to create branches or push** — the orchestrator owns the worktree lifecycle:

```
"You are working in a git worktree on branch '{branch}'. Commit your changes
 directly to this branch. Do NOT create new branches or push."
```

**Post-workflow:** decide whether the worktree holds work with `SKILL.md` invariant 1's
`worktree_has_changes()` — commits **or** a dirty tree; a commits-only
`git log {base_branch}..HEAD` check is the data-loss bug this skill exists to
prevent — run invariant 2's safety-net commit, then offer to push and create a
PR.

See [git-repo-agent ADR-004](https://github.com/laurigates/git-repo-agent/blob/main/docs/adr/004-worktree-isolation-for-agent-changes.md) for full context.
