"""Tests for worktree creation and review-instruction formatting.

These exercise the real ``git`` binary inside temp directories so they
double as smoke tests for the CLI's write path.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from vault_agent.worktree import (
    acquire_lock,
    create_worktree,
    cleanup_worktree,
    format_review_instructions,
    get_base_branch,
    release_lock,
    timestamped_branch,
    worktree_commit_count,
    worktree_file_change_count,
)


def _init_repo(path: Path) -> None:
    """Initialize a git repo with one commit on `main`."""
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=path, check=True)
    subprocess.run(
        ["git", "config", "user.email", "test@example.com"], cwd=path, check=True
    )
    subprocess.run(["git", "config", "user.name", "Test"], cwd=path, check=True)
    (path / "seed.md").write_text("# seed\n")
    subprocess.run(["git", "add", "."], cwd=path, check=True)
    subprocess.run(["git", "commit", "-qm", "initial"], cwd=path, check=True)


class TestTimestamp:
    def test_branch_format(self) -> None:
        branch = timestamped_branch()
        assert branch.startswith("vault-agent/")
        # Format: vault-agent/YYYY-MM-DDTHH-MM
        assert len(branch.split("/")[1]) == len("2026-04-17T14-00")

    def test_custom_prefix(self) -> None:
        branch = timestamped_branch("experimental")
        assert branch.startswith("experimental/")


class TestLock:
    def test_acquire_and_release(self, tmp_path: Path) -> None:
        lock = acquire_lock(tmp_path)
        assert lock is not None
        assert lock.exists()
        release_lock(lock)
        assert not lock.exists()

    def test_acquire_blocks_second_holder(self, tmp_path: Path) -> None:
        first = acquire_lock(tmp_path)
        second = acquire_lock(tmp_path)
        assert first is not None
        assert second is None  # live holder still owns it
        release_lock(first)


class TestWorktreeLifecycle:
    def test_create_and_cleanup(self, tmp_path: Path) -> None:
        _init_repo(tmp_path)
        branch = timestamped_branch()
        handle = create_worktree(tmp_path, branch)

        assert handle.branch == branch
        assert handle.base_branch == "main"
        assert handle.worktree_path.exists()
        assert (handle.worktree_path / "seed.md").read_text() == "# seed\n"
        assert worktree_commit_count(handle) == 0

        cleanup_worktree(handle)
        assert not handle.worktree_path.exists()

    def test_commits_and_files_counted(self, tmp_path: Path) -> None:
        _init_repo(tmp_path)
        handle = create_worktree(tmp_path, timestamped_branch())

        (handle.worktree_path / "new.md").write_text("# new\n")
        subprocess.run(
            ["git", "add", "new.md"], cwd=handle.worktree_path, check=True
        )
        subprocess.run(
            ["git", "commit", "-qm", "fix(lint): add new"],
            cwd=handle.worktree_path,
            check=True,
        )

        assert worktree_commit_count(handle) == 1
        assert worktree_file_change_count(handle) == 1

        text = format_review_instructions(handle)
        assert "1 commits" in text
        assert "1 files changed" in text
        assert handle.branch in text
        assert "diff" in text
        assert "merge" in text

        cleanup_worktree(handle)


class TestWorktreeCollisionSafety:
    """Regression: two runs in the same minute produce the same branch name.

    The old ``create_worktree`` force-removed any pre-existing worktree at
    the target path. If the first run had uncommitted agent output there,
    the second run would silently destroy it.
    """

    def test_refuses_to_overwrite_dirty_worktree(self, tmp_path: Path) -> None:
        _init_repo(tmp_path)
        branch = timestamped_branch()
        handle = create_worktree(tmp_path, branch)

        # Simulate agent output that wasn't committed yet.
        (handle.worktree_path / "agent-output.md").write_text("valuable work\n")

        with pytest.raises(RuntimeError, match="uncommitted changes"):
            create_worktree(tmp_path, branch)

        # Original work is preserved.
        assert (handle.worktree_path / "agent-output.md").exists()

    def test_overwrites_clean_worktree(self, tmp_path: Path) -> None:
        _init_repo(tmp_path)
        branch = timestamped_branch()
        create_worktree(tmp_path, branch)

        # Second call on a clean worktree is fine.
        handle2 = create_worktree(tmp_path, branch)
        assert handle2.worktree_path.exists()
