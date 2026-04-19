"""Unit tests for non-interactive configuration."""

from __future__ import annotations

import pytest

from vault_agent.non_interactive import (
    EXIT_CONFIG_ERROR,
    EXIT_HOOK_BLOCKED,
    EXIT_LOCKED,
    EXIT_RUNTIME_ERROR,
    EXIT_SUCCESS,
    HookBlockedError,
    LockedError,
    NonInteractiveConfig,
    NonInteractiveUsageError,
)


class TestExitCodes:
    def test_distinct(self) -> None:
        codes = {
            EXIT_SUCCESS,
            EXIT_RUNTIME_ERROR,
            EXIT_CONFIG_ERROR,
            EXIT_LOCKED,
            EXIT_HOOK_BLOCKED,
        }
        assert len(codes) == 5

    def test_success_is_zero(self) -> None:
        assert EXIT_SUCCESS == 0


class TestNonInteractiveConfig:
    def test_build_defaults(self) -> None:
        cfg = NonInteractiveConfig.build(
            apply=False, max_cost_usd=None, log_format="text"
        )
        assert cfg.apply is False
        assert cfg.max_cost_usd is None
        assert cfg.log_format == "text"

    def test_invalid_log_format(self) -> None:
        with pytest.raises(NonInteractiveUsageError):
            NonInteractiveConfig.build(
                apply=False, max_cost_usd=None, log_format="yaml"
            )

    def test_non_positive_cost(self) -> None:
        with pytest.raises(NonInteractiveUsageError):
            NonInteractiveConfig.build(
                apply=False, max_cost_usd=0.0, log_format="text"
            )

    def test_frozen(self) -> None:
        cfg = NonInteractiveConfig.build(
            apply=True, max_cost_usd=5.0, log_format="json"
        )
        with pytest.raises(Exception):
            cfg.apply = False  # type: ignore[misc]


class TestErrors:
    def test_locked_is_runtime(self) -> None:
        assert issubclass(LockedError, RuntimeError)

    def test_hook_blocked_is_runtime(self) -> None:
        assert issubclass(HookBlockedError, RuntimeError)
