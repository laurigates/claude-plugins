"""Regression tests for worktree change detection and safety-net commits.

Covers the data-loss bug where blueprint-driver phases wrote many files in
the onboarding worktree but didn't commit them; the old
``worktree_has_changes`` only inspected commits, reported "no changes", and
``cleanup_worktree --force`` then discarded the agent's work.

Also covers issue #1260: agent escaped worktree via `cd <repo> && git commit`,
landing commits on the parent's default branch instead of the worktree branch.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from git_repo_agent.orchestrator import _snapshot_parent_sha, _warn_if_parent_moved
from git_repo_agent.worktree import (
    auto_commit_if_dirty,
    worktree_has_changes,
)


def _git_available() -> bool:
    return shutil.which("git") is not None


needs_git = pytest.mark.skipif(not _git_available(), reason="git not installed")


def _init_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-b", "main", str(path)], check=True, capture_output=True)
    for key, value in [
        ("user.email", "test@example.com"),
        ("user.name", "Test"),
        ("commit.gpgsign", "false"),  # override global signing in test environments
    ]:
        subprocess.run(
            ["git", "-C", str(path), "config", key, value],
            check=True, capture_output=True,
        )
    (path / "README.md").write_text("init\n")
    subprocess.run(["git", "-C", str(path), "add", "-A"], check=True, capture_output=True)
    subprocess.run(
        ["git", "-C", str(path), "commit", "-m", "init"],
        check=True, capture_output=True,
    )


@needs_git
class TestWorktreeHasChanges:
    def test_clean_tree_returns_false(self, tmp_path: Path):
        repo = tmp_path / "repo"
        _init_repo(repo)
        assert worktree_has_changes(repo, "main") is False

    def test_untracked_file_counts_as_changes(self, tmp_path: Path):
        """Regression: blueprint driver writes untracked files. Old impl missed this."""
        repo = tmp_path / "repo"
        _init_repo(repo)
        (repo / "new_file.md").write_text("content\n")
        assert worktree_has_changes(repo, "main") is True

    def test_modified_tracked_file_counts_as_changes(self, tmp_path: Path):
        repo = tmp_path / "repo"
        _init_repo(repo)
        (repo / "README.md").write_text("modified\n")
        assert worktree_has_changes(repo, "main") is True

    def test_commit_beyond_base_counts_as_changes(self, tmp_path: Path):
        repo = tmp_path / "repo"
        _init_repo(repo)
        subprocess.run(
            ["git", "-C", str(repo), "checkout", "-b", "feature"],
            check=True, capture_output=True,
        )
        (repo / "new_file.md").write_text("content\n")
        subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True, capture_output=True)
        subprocess.run(
            ["git", "-C", str(repo), "commit", "-m", "feat: add file"],
            check=True, capture_output=True,
        )
        assert worktree_has_changes(repo, "main") is True


@needs_git
class TestAutoCommitIfDirty:
    def test_clean_tree_returns_false(self, tmp_path: Path):
        repo = tmp_path / "repo"
        _init_repo(repo)
        assert auto_commit_if_dirty(repo, "chore: noop") is False

    def test_dirty_tree_gets_committed(self, tmp_path: Path):
        repo = tmp_path / "repo"
        _init_repo(repo)
        (repo / "blueprint.json").write_text("{}\n")
        (repo / "README.md").write_text("updated\n")

        assert auto_commit_if_dirty(repo, "chore: safety-net") is True

        log = subprocess.run(
            ["git", "-C", str(repo), "log", "--oneline"],
            check=True, capture_output=True, text=True,
        )
        assert "chore: safety-net" in log.stdout
        status = subprocess.run(
            ["git", "-C", str(repo), "status", "--porcelain"],
            check=True, capture_output=True, text=True,
        )
        assert status.stdout.strip() == ""


@needs_git
class TestParentBranchIntegrity:
    """Regression tests for issue #1260: agent escaped worktree and committed
    to parent main instead of the worktree branch.

    The `_warn_if_parent_moved` guard detects the invariant violation and
    warns the user before cleanup destroys the evidence.
    """

    def test_snapshot_returns_head_sha(self, tmp_path: Path):
        repo = tmp_path / "repo"
        _init_repo(repo)
        sha = _snapshot_parent_sha(repo)
        expected = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        assert sha == expected
        assert len(sha) == 40

    def test_warn_returns_true_when_parent_unchanged(self, tmp_path: Path):
        repo = tmp_path / "repo"
        _init_repo(repo)
        sha = _snapshot_parent_sha(repo)
        assert _warn_if_parent_moved(repo, sha, "main", "maintain/2026-05-07") is True

    def test_warn_returns_false_when_parent_moved(self, tmp_path: Path):
        """Regression: agent ran `cd <repo> && git commit`, moving parent HEAD."""
        repo = tmp_path / "repo"
        _init_repo(repo)
        sha_before = _snapshot_parent_sha(repo)

        # Simulate the agent escaping the worktree and committing to parent main.
        (repo / "escaped.txt").write_text("written by agent outside worktree\n")
        subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True, capture_output=True)
        subprocess.run(
            ["git", "-C", str(repo), "commit", "-m", "oops: commit on wrong branch"],
            check=True, capture_output=True,
        )

        assert _warn_if_parent_moved(repo, sha_before, "main", "maintain/2026-05-07") is False

    def test_worktree_commit_does_not_affect_parent(self, tmp_path: Path):
        """Regression: commits inside a git worktree must not move the parent HEAD."""
        repo = tmp_path / "repo"
        _init_repo(repo)
        sha_before = _snapshot_parent_sha(repo)

        # Create a real git worktree on a feature branch.
        worktree = tmp_path / "worktree"
        subprocess.run(
            ["git", "-C", str(repo), "worktree", "add", "-b", "maintain/test", str(worktree)],
            check=True, capture_output=True,
        )

        # Commit inside the worktree (the correct pattern).
        (worktree / "fix.txt").write_text("fix applied in worktree\n")
        subprocess.run(["git", "-C", str(worktree), "add", "-A"], check=True, capture_output=True)
        subprocess.run(
            ["git", "-C", str(worktree), "commit", "-m", "fix: applied in worktree"],
            check=True, capture_output=True,
        )

        # Parent HEAD must not have moved.
        assert _warn_if_parent_moved(repo, sha_before, "main", "maintain/test") is True
