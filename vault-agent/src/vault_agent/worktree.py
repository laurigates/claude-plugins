"""Git worktree management for isolated vault-agent work.

Simpler than git-repo-agent's because vault-agent has no GitHub remote.
After a write run we leave the branch on disk and print the review/merge
commands for the user to run manually.
"""

from __future__ import annotations

import errno
import json
import logging
import os
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

_LOCK_RELATIVE = Path(".claude") / "worktrees" / ".vault-agent.lock"
_BRANCH_PREFIX = "vault-agent"


def timestamped_branch(prefix: str = _BRANCH_PREFIX) -> str:
    """UTC-timestamped branch name (no colons, filesystem-safe)."""
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M")
    return f"{prefix}/{stamp}"


# ---------------------------------------------------------------------------
# Advisory lock
# ---------------------------------------------------------------------------


def acquire_lock(vault_path: Path) -> Path | None:
    """Acquire the advisory lock for a non-interactive run."""
    lock_path = vault_path / _LOCK_RELATIVE
    lock_path.parent.mkdir(parents=True, exist_ok=True)

    payload = json.dumps(
        {"pid": os.getpid(), "started_at": datetime.now(timezone.utc).isoformat()}
    ).encode()

    try:
        fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        try:
            existing = json.loads(lock_path.read_text(encoding="utf-8"))
            pid = int(existing.get("pid", 0))
        except (ValueError, OSError):
            pid = 0
        if pid > 0 and _pid_alive(pid):
            return None
        try:
            lock_path.unlink()
        except FileNotFoundError:
            pass
        try:
            fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            return None

    with os.fdopen(fd, "wb") as f:
        f.write(payload)
    return lock_path


def release_lock(lock_path: Path | None) -> None:
    if lock_path is None:
        return
    try:
        lock_path.unlink()
    except FileNotFoundError:
        pass
    except OSError as exc:
        logger.warning("Failed to release lock %s: %s", lock_path, exc)


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError as exc:
        return exc.errno == errno.EPERM
    return True


# ---------------------------------------------------------------------------
# Worktree creation / cleanup
# ---------------------------------------------------------------------------


@dataclass
class WorktreeHandle:
    """Result of create_worktree — paths and branch for later reporting."""

    repo_path: Path
    worktree_path: Path
    branch: str
    base_branch: str


def get_base_branch(vault_path: Path) -> str:
    """Current branch of the main checkout."""
    return subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=vault_path,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def create_worktree(vault_path: Path, branch: str) -> WorktreeHandle:
    """Create an isolated worktree on ``branch`` branched off HEAD.

    Removes any stale *clean* worktree at the same path and deletes any
    leftover branch of the same name. Refuses to remove a pre-existing
    worktree that has uncommitted or untracked changes, since branch names
    are minute-timestamped and two runs within the same minute would
    otherwise destroy the first's agent output.
    """
    worktree_path = vault_path / ".claude" / "worktrees" / branch.replace("/", "-")
    worktree_path.parent.mkdir(parents=True, exist_ok=True)
    base = get_base_branch(vault_path)

    if worktree_path.exists():
        dirty = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=worktree_path,
            capture_output=True,
            text=True,
        )
        if dirty.returncode == 0 and dirty.stdout.strip():
            raise RuntimeError(
                f"Refusing to overwrite worktree at {worktree_path}: it has "
                f"uncommitted changes from a concurrent or prior run. Review "
                f"with `git -C {worktree_path} status`, then commit or discard "
                f"before re-running."
            )
        subprocess.run(
            ["git", "worktree", "remove", "--force", str(worktree_path)],
            cwd=vault_path,
            capture_output=True,
            text=True,
        )

    subprocess.run(
        ["git", "branch", "-D", branch],
        cwd=vault_path,
        capture_output=True,
        text=True,
    )

    subprocess.run(
        ["git", "worktree", "add", "-b", branch, str(worktree_path), base],
        cwd=vault_path,
        capture_output=True,
        text=True,
        check=True,
    )

    logger.info("Created worktree at %s on %s (base: %s)", worktree_path, branch, base)
    return WorktreeHandle(
        repo_path=vault_path,
        worktree_path=worktree_path,
        branch=branch,
        base_branch=base,
    )


def worktree_commit_count(handle: WorktreeHandle) -> int:
    """How many commits has the worktree added on top of the base branch?"""
    result = subprocess.run(
        ["git", "rev-list", "--count", f"{handle.base_branch}..HEAD"],
        cwd=handle.worktree_path,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return 0
    try:
        return int(result.stdout.strip())
    except ValueError:
        return 0


def worktree_file_change_count(handle: WorktreeHandle) -> int:
    """How many files changed vs. the base branch?"""
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{handle.base_branch}..HEAD"],
        cwd=handle.worktree_path,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return 0
    return sum(1 for line in result.stdout.splitlines() if line.strip())


def cleanup_worktree(handle: WorktreeHandle) -> None:
    """Remove the worktree (branch stays). Safe if already removed."""
    subprocess.run(
        ["git", "worktree", "remove", "--force", str(handle.worktree_path)],
        cwd=handle.repo_path,
        capture_output=True,
        text=True,
    )


def format_review_instructions(handle: WorktreeHandle) -> str:
    """Render the review/merge command block shown after a write run."""
    commits = worktree_commit_count(handle)
    files = worktree_file_change_count(handle)
    return (
        f"✓ branch {handle.branch} ready ({commits} commits, {files} files changed)\n"
        f"  review:  git -C {handle.repo_path} diff {handle.base_branch} {handle.branch}\n"
        f"  merge:   git -C {handle.repo_path} merge --ff-only {handle.branch}"
    )
