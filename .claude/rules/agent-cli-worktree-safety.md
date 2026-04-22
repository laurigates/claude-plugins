---
paths:
  - "git-repo-agent/**"
  - "vault-agent/**"
---

# Agent-CLI Worktree Safety

Data-loss prevention patterns for Python SDK agent CLIs (`git-repo-agent`, `vault-agent`, and any future sibling project built on `claude-agent-sdk` + Typer + git worktrees).

## The Core Failure Mode

These CLIs create a git worktree, invoke `ClaudeAgentOptions` to run an LLM orchestrator that writes files there, then clean up with `git worktree remove --force`. Three independent mistakes compound into silent data loss:

1. **Driver phases write but don't commit** ("the outer orchestrator handles git state").
2. **The outer orchestrator stalls** on `AskUserQuestion` (silently fails in SDK subprocess mode — see ADR-003) or otherwise ends without committing.
3. **`worktree_has_changes` only checks commits** (`git log base..HEAD`), so it reports "no changes", and `cleanup_worktree` then force-removes the worktree.

Net result: many files are written, the user sees "No changes were made", and the work is destroyed.

## Required Invariants

### 1. "Has changes" means commits OR dirty tree

Any function used to decide whether a worktree is worth preserving **must** return true if the working tree is dirty, even when there are no commits beyond base:

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

A commits-only check is a data-loss bug. If uncommitted files matter for the next operation (push, PR, cleanup), they matter for the "has changes" check.

### 2. Safety-net commit before any destructive cleanup

If the agent phase was supposed to commit but didn't, capture the work anyway before moving on:

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

Call this from the post-run PR path (both interactive and non-interactive) with a clear message like `"chore({workflow}): commit remaining changes from agent run"` and print a warning so the user knows the safety net caught something.

### 3. Pre-validate before git touches the path

Typer's `exists=True, dir_okay=True` is not enough. Add explicit helpers and call them at the top of every command that will eventually run `git rev-parse`, `git worktree add`, or project-domain operations:

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

Add project-domain checks too (Obsidian vault → `.obsidian/` or any `*.md`; code repo → language marker). Print a friendly message; exit with `EXIT_CONFIG_ERROR`, not a traceback.

**Unborn HEAD is its own failure class.** A fresh `git init` with no commits passes `--is-inside-work-tree` but fails every `rev-parse HEAD` and `worktree add -b <br> <path> HEAD` downstream. Always check both.

### 4. Branch-name collisions are not free

Timestamp-based branch names (`%Y-%m-%dT%H-%M`) collide when two runs start inside the same minute. If `create_worktree` force-removes a pre-existing worktree at the target path, the second run destroys the first's uncommitted agent output.

Either:
- Use second-granularity plus a short random suffix, or
- Before removing a pre-existing worktree, probe `git status --porcelain` in it and **refuse** if dirty:

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

The advisory lock in `worktree.py::acquire_lock` only guards `--non-interactive` runs. Interactive and concurrent invocations need in-tree protection.

## AskUserQuestion in SDK subprocess mode

When `ClaudeAgentOptions` runs the CLI as an SDK subprocess, stdin/stdout carry the SDK JSON protocol. `AskUserQuestion` has no terminal to reach; the tool call fires, nothing renders, the model wraps up as if the user declined.

- **Do not rely on `AskUserQuestion` for mid-pipeline interaction** in any onboard/maintain flow.
- Use the two-phase interaction pattern (ADR-003): agent outputs findings and stops → Python collects input via `console.input()` → second `client.query()` executes the selection.
- Remove `AskUserQuestion` from `allowed_tools` for paths that don't want silent failure.

See [`git-repo-agent/docs/adr/003`](../../git-repo-agent/docs/) for the canonical write-up.

## Required Tests

Every agent CLI must have regression tests for:

| Test | Verifies |
|------|----------|
| `test_worktree_has_changes_detects_untracked` | Dirty-tree detection covers the blueprint-driver-style "wrote files, never committed" case |
| `test_auto_commit_if_dirty` | Safety-net commit captures uncommitted state and leaves the tree clean |
| `test_create_worktree_refuses_to_overwrite_dirty` | Collision protection for same-minute runs |
| `test_cli_rejects_non_git_target` | Friendly config error instead of `CalledProcessError` trace |
| `test_cli_rejects_empty_git_repo` | Unborn-HEAD detection |
| `test_cli_rejects_non_domain_target` (vault-agent: not a vault; git-repo-agent: N/A, domain is git) | Catches "pointed at the wrong directory" |

Mirror the layouts in `git-repo-agent/tests/test_worktree_changes.py` and `vault-agent/tests/test_worktree.py::TestWorktreeCollisionSafety`.

## Checklist When Adding a New Agent CLI

- [ ] `_ensure_<domain>()` + `_ensure_git_repo()` called at the top of every write command
- [ ] `worktree_has_changes` covers uncommitted + untracked state
- [ ] `auto_commit_if_dirty` runs before any `cleanup_worktree(--force)` or push
- [ ] `create_worktree` refuses to force-remove a dirty pre-existing worktree
- [ ] Regression tests for each of the six rows above
- [ ] Interactive flows use the ADR-003 two-phase pattern instead of mid-session `AskUserQuestion`
