"""Tests for NonInteractiveConfig, lock acquisition, and branch naming."""

from pathlib import Path

import pytest

from git_repo_agent.non_interactive import (
    EXIT_CONFIG_ERROR,
    EXIT_HOOK_BLOCKED,
    EXIT_LOCKED,
    EXIT_RUNTIME_ERROR,
    EXIT_SUCCESS,
    NonInteractiveConfig,
    NonInteractiveUsageError,
)
from git_repo_agent.worktree import (
    acquire_lock,
    release_lock,
    timestamped_branch,
)


class TestExitCodes:
    def test_contract(self):
        # ADR-005 contract: these are part of the public API.
        assert (EXIT_SUCCESS, EXIT_RUNTIME_ERROR, EXIT_CONFIG_ERROR,
                EXIT_LOCKED, EXIT_HOOK_BLOCKED) == (0, 1, 2, 3, 4)


class TestNonInteractiveConfig:
    def _build(self, **over):
        defaults = dict(
            auto_pr="on-changes",
            auto_issues="on-findings",
            on_duplicate="skip",
            refresh_base=False,
            max_cost_usd=None,
            log_format="plain",
            notify="none",
        )
        defaults.update(over)
        return NonInteractiveConfig.build(**defaults)

    def test_happy_path(self):
        cfg = self._build()
        assert cfg.auto_pr == "on-changes"
        assert cfg.log_format == "plain"

    def test_invalid_auto_pr(self):
        with pytest.raises(NonInteractiveUsageError, match="--auto-pr"):
            self._build(auto_pr="maybe")

    def test_invalid_auto_issues(self):
        with pytest.raises(NonInteractiveUsageError, match="--auto-issues"):
            self._build(auto_issues="whenever")

    def test_invalid_log_format(self):
        with pytest.raises(NonInteractiveUsageError, match="--log-format"):
            self._build(log_format="yaml")

    def test_invalid_on_duplicate(self):
        with pytest.raises(NonInteractiveUsageError, match="--on-duplicate"):
            self._build(on_duplicate="replace")

    def test_negative_cost(self):
        with pytest.raises(NonInteractiveUsageError, match="positive"):
            self._build(max_cost_usd=-1.0)

    def test_frozen(self):
        cfg = self._build()
        with pytest.raises(Exception):
            cfg.auto_pr = "always"  # type: ignore[misc]


class TestLock:
    def test_acquire_and_release(self, tmp_path: Path):
        lock = acquire_lock(tmp_path)
        assert lock is not None
        assert lock.exists()
        release_lock(lock)
        assert not lock.exists()

    def test_double_acquire_fails(self, tmp_path: Path):
        lock1 = acquire_lock(tmp_path)
        assert lock1 is not None
        try:
            lock2 = acquire_lock(tmp_path)
            assert lock2 is None  # live holder present
        finally:
            release_lock(lock1)

    def test_stale_lock_reclaimed(self, tmp_path: Path):
        # Create a stale lock pointing at a PID unlikely to exist.
        lock_dir = tmp_path / ".claude" / "worktrees"
        lock_dir.mkdir(parents=True)
        lock_path = lock_dir / ".git-repo-agent.lock"
        # PID 2^31-1 virtually never exists.
        lock_path.write_text('{"pid": 2147483646, "started_at": "stale"}')
        acquired = acquire_lock(tmp_path)
        assert acquired is not None
        release_lock(acquired)

    def test_release_none_is_safe(self):
        release_lock(None)  # should not raise


class TestTimestampedBranch:
    def test_format(self):
        b = timestamped_branch("maintain")
        assert b.startswith("maintain/")
        # YYYY-MM-DDTHH-MM -> 16 chars
        suffix = b[len("maintain/"):]
        assert len(suffix) == 16
        assert suffix[4] == "-" and suffix[7] == "-" and suffix[10] == "T"

    def test_uniqueness_prefix(self):
        assert timestamped_branch("maintain").startswith("maintain/")
        assert timestamped_branch("setup").startswith("setup/")
