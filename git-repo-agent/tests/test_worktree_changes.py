"""Regression tests for worktree change detection and safety-net commits.

Covers the data-loss bug where blueprint-driver phases wrote many files in
the onboarding worktree but didn't commit them; the old
``worktree_has_changes`` only inspected commits, reported "no changes", and
``cleanup_worktree --force`` then discarded the agent's work.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from git_repo_agent.worktree import (
    auto_commit_if_dirty,
    worktree_has_changes,
)


def _git_available() -> bool:
    return shutil.which("git") is not None


needs_git = pytest.mark.skipif(not _git_available(), reason="git not installed")


def _init_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-b", "main", str(path)], check=True, capture_output=True)
    subprocess.run(
        ["git", "-C", str(path), "config", "user.email", "test@example.com"],
        check=True, capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(path), "config", "user.name", "Test"],
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
