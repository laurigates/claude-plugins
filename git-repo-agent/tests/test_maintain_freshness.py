"""Regression tests for issue #1358 — maintain pass operates on stale state.

When ``git-repo-agent maintain`` runs back-to-back with ``git-repo-agent
onboard`` (i.e. immediately after the onboard PR squash-merges), the
maintain pass analyzes the **pre-merge local working copy** and
re-suggests every fix the onboard PR just landed.

The fix is :func:`probe_base_freshness` plus an explicit ``base_ref``
parameter on :func:`create_worktree`: maintain now fetches origin and
branches off ``origin/<base>`` so the analysis reflects whatever has
just been merged remotely.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from git_repo_agent.worktree import (
    BaseFreshness,
    create_worktree,
    probe_base_freshness,
)


def _git_available() -> bool:
    return shutil.which("git") is not None


needs_git = pytest.mark.skipif(not _git_available(), reason="git not installed")


def _init_repo(path: Path) -> None:
    """Initialize a fresh repo with one commit on ``main``."""
    subprocess.run(
        ["git", "init", "-b", "main", str(path)],
        check=True, capture_output=True,
    )
    for key, value in [
        ("user.email", "test@example.com"),
        ("user.name", "Test"),
        ("commit.gpgsign", "false"),
    ]:
        subprocess.run(
            ["git", "-C", str(path), "config", key, value],
            check=True, capture_output=True,
        )
    (path / "README.md").write_text("init\n")
    subprocess.run(
        ["git", "-C", str(path), "add", "-A"],
        check=True, capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(path), "commit", "-m", "init"],
        check=True, capture_output=True,
    )


def _make_remote_with_extra_commits(
    tmp_path: Path, extra_commits: int = 0
) -> tuple[Path, Path]:
    """Create a bare ``remote`` and a ``local`` clone that may be behind.

    ``extra_commits`` is the number of commits added to the remote
    *after* the local clones it. ``> 0`` simulates the issue #1358 case
    where the onboard PR squash-merged on the remote while the local
    main hasn't been pulled.

    Returns ``(local_path, remote_path)``.
    """
    remote = tmp_path / "remote.git"
    upstream = tmp_path / "upstream"
    local = tmp_path / "local"

    # Build the upstream working copy, then push to a bare remote.
    _init_repo(upstream)
    subprocess.run(
        ["git", "init", "--bare", str(remote)],
        check=True, capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(upstream), "remote", "add", "origin", str(remote)],
        check=True, capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(upstream), "push", "-u", "origin", "main"],
        check=True, capture_output=True,
    )

    # Clone the local working copy.
    subprocess.run(
        ["git", "clone", str(remote), str(local)],
        check=True, capture_output=True,
    )
    # Match the test repo identity in the local clone.
    for key, value in [
        ("user.email", "test@example.com"),
        ("user.name", "Test"),
        ("commit.gpgsign", "false"),
    ]:
        subprocess.run(
            ["git", "-C", str(local), "config", key, value],
            check=True, capture_output=True,
        )

    # Now move the remote forward by N commits via the upstream working copy.
    for i in range(extra_commits):
        (upstream / f"file_{i}.txt").write_text(f"merged after clone {i}\n")
        subprocess.run(
            ["git", "-C", str(upstream), "add", "-A"],
            check=True, capture_output=True,
        )
        subprocess.run(
            [
                "git", "-C", str(upstream), "commit",
                "-m", f"feat: post-clone change {i}",
            ],
            check=True, capture_output=True,
        )
    if extra_commits:
        subprocess.run(
            ["git", "-C", str(upstream), "push", "origin", "main"],
            check=True, capture_output=True,
        )

    return local, remote


@needs_git
class TestProbeBaseFreshness:
    """Cover the three states of remote/fetch state."""

    def test_no_origin_remote_returns_local_only(self, tmp_path: Path):
        """Local-only repos have nothing to refresh — has_remote is False."""
        repo = tmp_path / "repo"
        _init_repo(repo)

        result = probe_base_freshness(repo, "main")
        assert isinstance(result, BaseFreshness)
        assert result.has_remote is False
        assert result.fetched is False
        assert result.behind == 0
        assert result.base_branch == "main"

    def test_clean_clone_reports_zero_behind(self, tmp_path: Path):
        """Right after `git clone`, local main matches origin/main."""
        local, _ = _make_remote_with_extra_commits(tmp_path, extra_commits=0)

        result = probe_base_freshness(local, "main")
        assert result.has_remote is True
        assert result.fetched is True
        assert result.behind == 0

    def test_stale_clone_reports_positive_behind(self, tmp_path: Path):
        """Issue #1358 repro: remote moved forward but local hasn't pulled."""
        local, _ = _make_remote_with_extra_commits(tmp_path, extra_commits=3)

        result = probe_base_freshness(local, "main")
        assert result.has_remote is True
        assert result.fetched is True
        assert result.behind == 3, (
            "Expected 3 commits behind origin/main — the remote moved "
            "forward by 3 commits while the local clone was untouched."
        )

    def test_probe_does_not_modify_local_main(self, tmp_path: Path):
        """Probe must fetch but NOT auto-merge. Caller decides."""
        local, _ = _make_remote_with_extra_commits(tmp_path, extra_commits=2)

        head_before = subprocess.run(
            ["git", "-C", str(local), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()

        probe_base_freshness(local, "main")

        head_after = subprocess.run(
            ["git", "-C", str(local), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        assert head_before == head_after


@needs_git
class TestCreateWorktreeWithBaseRef:
    """``create_worktree`` accepts an explicit base ref (issue #1358)."""

    def test_default_base_uses_current_head(self, tmp_path: Path):
        repo = tmp_path / "repo"
        _init_repo(repo)
        head = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()

        wt = create_worktree(repo, "feature/test")
        wt_head = subprocess.run(
            ["git", "-C", str(wt), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        assert wt_head == head

    def test_explicit_base_ref_used(self, tmp_path: Path):
        """Pinning base_ref forces the worktree to branch off that ref.

        Regression: issue #1358. Maintain must branch off origin/<base>,
        not local <base>, so a just-merged onboard PR is reflected even
        when the local main hasn't been pulled.
        """
        local, _ = _make_remote_with_extra_commits(tmp_path, extra_commits=2)

        local_head = subprocess.run(
            ["git", "-C", str(local), "rev-parse", "main"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        # Force the fetch via the probe helper, so origin/main is in the
        # local clone's ref database when create_worktree runs.
        probe_base_freshness(local, "main")
        origin_head = subprocess.run(
            ["git", "-C", str(local), "rev-parse", "origin/main"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        assert local_head != origin_head, (
            "Test setup invariant: local main must differ from origin/main"
        )

        wt = create_worktree(local, "maintain/test", base_ref="origin/main")
        wt_head = subprocess.run(
            ["git", "-C", str(wt), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        assert wt_head == origin_head, (
            "Worktree must be branched off origin/main, not local main"
        )
