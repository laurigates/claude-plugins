---
created: 2026-09-02
modified: 2026-09-02
reviewed: 2026-09-02
name: agent-cli-worktree-safety
description: Data-loss invariants for a CLI that runs an agent SDK in a git worktree then force-removes it. Use when building or reviewing such a CLI, or when an agent run reports "no changes" after writing files.
allowed-tools: Glob, Grep, Read, Edit, Write, Bash
model: opus
compatibility: claude-code
---

# Agent-CLI Worktree Safety

Data-loss prevention for CLIs that create a git worktree, run an LLM
orchestrator (`claude-agent-sdk` or similar) that writes files there, and then
clean up with `git worktree remove --force`.

## The core failure mode

Three independent mistakes compound into silent data loss:

1. **Driver phases write but never commit** — "the outer orchestrator handles git state".
2. **The outer orchestrator ends without committing** — it stalls on an interactive tool call that cannot render (see *Interactive tools in SDK subprocess mode* below), or simply finishes.
3. **The "has changes" check only counts commits** (`git log base..HEAD`), so it reports nothing to preserve — and cleanup force-removes the worktree.

Net result: many files are written, the user is told **"No changes were made"**,
and the work is destroyed. No error, no traceback. That user-visible message is
the diagnostic tell — if a run wrote files and reported no changes, check
invariant 1 before anything else.

## Required invariants

### 1. "Has changes" means commits OR a dirty tree

Any function deciding whether a worktree is worth preserving must return true
when the working tree is dirty, even with no commits beyond base:

```python
def worktree_has_changes(worktree_path, base_branch):
    commits = subprocess.run(
        ["git", "log", "--oneline", f"{base_branch}..HEAD"],
        cwd=worktree_path, capture_output=True, text=True,
    )
    if commits.stdout.strip():
        return True
    dirty = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=worktree_path, capture_output=True, text=True,
    )
    return bool(dirty.stdout.strip())
```

A commits-only check is a data-loss bug. `--porcelain` (not `git diff`) is
load-bearing: a brand-new file the agent created is **untracked**, and
`git diff` cannot see it.

If uncommitted files matter for the next operation — push, PR, cleanup — they
matter for this check.

### 2. Safety-net commit before any destructive cleanup

If the agent phase was supposed to commit and didn't, capture the work anyway:

```python
def auto_commit_if_dirty(worktree_path, message):
    status = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=worktree_path, capture_output=True, text=True, check=True,
    )
    if not status.stdout.strip():
        return False
    subprocess.run(["git", "add", "-A"], cwd=worktree_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", message],
        cwd=worktree_path, check=True, capture_output=True, text=True,
    )
    return True
```

Call it from every post-run path — interactive and non-interactive — with a
message naming the workflow, and print a warning so the user learns the safety
net fired. A silent safety net hides the bug it is compensating for.

### 3. Pre-validate before git touches the path

Typer's `exists=True, dir_okay=True` is not enough. Call explicit guards at the
top of every command that will later run `git rev-parse`, `git worktree add`,
or a domain operation:

```python
def _ensure_git_repo(path):
    inside = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        cwd=path, capture_output=True, text=True,
    )
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        raise typer.Exit(code=EXIT_CONFIG_ERROR)
    head = subprocess.run(
        ["git", "rev-parse", "--verify", "HEAD"],
        cwd=path, capture_output=True, text=True,
    )
    if head.returncode != 0:  # unborn HEAD — no commits yet
        raise typer.Exit(code=EXIT_CONFIG_ERROR)
```

**Unborn HEAD is its own failure class.** A fresh `git init` with no commits
passes `--is-inside-work-tree` but fails every downstream `rev-parse HEAD` and
`worktree add -b <br> <path> HEAD`. Check both, always.

Add a domain check beside it — an Obsidian vault wants `.obsidian/` or any
`*.md`; a code repo wants a language marker — so "pointed at the wrong
directory" is a friendly config error, not a `CalledProcessError` traceback.

### 4. Branch-name collisions are not free

Timestamp branch names (`%Y-%m-%dT%H-%M`) collide when two runs start in the
same minute. If `create_worktree` force-removes a pre-existing worktree at the
target path, the second run destroys the first run's uncommitted agent output.

Either use second granularity plus a short random suffix, or refuse:

```python
if worktree_path.exists():
    dirty = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=worktree_path, capture_output=True, text=True,
    )
    if dirty.returncode == 0 and dirty.stdout.strip():
        raise RuntimeError(
            f"Refusing to overwrite worktree at {worktree_path}: has "
            f"uncommitted changes from a concurrent or prior run."
        )
```

An advisory lock that only guards `--non-interactive` runs does not cover
interactive or concurrent invocations. Those need the in-tree probe.

## Interactive tools in SDK subprocess mode

When the SDK runs the CLI as a subprocess, stdin/stdout carry the SDK's JSON
protocol. An interactive tool call such as `AskUserQuestion` has no terminal to
reach: the call fires, nothing renders, and the model wraps up as if the user
declined. This is failure mode 2 above, and it is silent.

- **Do not rely on mid-pipeline interactive tool calls** in any driver flow.
- Use a two-phase pattern instead: the agent emits findings and stops → the host collects input (`console.input()`) → a second `client.query()` executes the selection.
- Remove the interactive tool from `allowed_tools` on paths that must not fail silently, so the attempt is an error rather than a shrug.

Worked example: [git-repo-agent ADR-003](https://github.com/laurigates/git-repo-agent/blob/main/docs/adr/003-switch-to-claude-sdk-client-for-interactive-workflows.md).

## Required tests

| Test | Verifies |
|------|----------|
| `test_worktree_has_changes_detects_untracked` | Dirty-tree detection covers "wrote files, never committed" |
| `test_auto_commit_if_dirty` | The safety net captures uncommitted state and leaves the tree clean |
| `test_create_worktree_refuses_to_overwrite_dirty` | Collision protection for same-minute runs |
| `test_cli_rejects_non_git_target` | Friendly config error, not a traceback |
| `test_cli_rejects_empty_git_repo` | Unborn-HEAD detection |
| `test_cli_rejects_non_domain_target` | Catches "pointed at the wrong directory" |

Reference layouts: [`git-repo-agent/tests/test_worktree_changes.py`](https://github.com/laurigates/git-repo-agent/blob/main/tests/test_worktree_changes.py) and [`vault-agent/tests/test_worktree.py`](https://github.com/laurigates/vault-agent/blob/main/tests/test_worktree.py) (`TestWorktreeCollisionSafety`).

## Checklist when adding a new agent CLI

- [ ] `_ensure_git_repo()` + a domain guard at the top of every write command
- [ ] "Has changes" covers uncommitted **and** untracked state
- [ ] Safety-net commit runs before any `cleanup_worktree(--force)` or push
- [ ] `create_worktree` refuses to force-remove a dirty pre-existing worktree
- [ ] A regression test for each of the six rows above
- [ ] Interactive flows use the two-phase pattern, not a mid-session interactive tool call

## Related

- `python-plugin:typer-cli-completion` — sibling convention for the same family of Typer CLIs
- `agent-patterns-plugin:parallel-agent-dispatch` — the orchestrator-side contract for worktree-isolated agents
- `git-plugin:git-coworker-check` — detecting a peer agent in a shared checkout before destructive git ops
