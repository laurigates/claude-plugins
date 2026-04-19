"""Non-interactive run configuration and exit-code contract.

See ``docs/adr/0002-worktree-without-pr.md``. Because vault-agent has no
GitHub remote to push to, the non-interactive policy is simpler than
git-repo-agent's — there are no auto-pr / auto-issues decisions, only
whether to write (``--fix``) or report (``--dry-run``).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

# Exit codes.
EXIT_SUCCESS = 0
EXIT_RUNTIME_ERROR = 1
EXIT_CONFIG_ERROR = 2
EXIT_LOCKED = 3
EXIT_HOOK_BLOCKED = 4


class NonInteractiveUsageError(ValueError):
    """Raised when non-interactive flags are inconsistent or unsupported."""


class LockedError(RuntimeError):
    """Raised when another vault-agent run holds the vault lock."""


class HookBlockedError(RuntimeError):
    """Raised when a safety hook blocked a critical operation."""


LogFormat = Literal["text", "json", "plain"]

_LOG_FMT_VALUES = {"text", "json", "plain"}


@dataclass(frozen=True)
class NonInteractiveConfig:
    """Validated policy for a non-interactive vault-agent run."""

    apply: bool
    max_cost_usd: float | None
    log_format: LogFormat

    @classmethod
    def build(
        cls,
        *,
        apply: bool,
        max_cost_usd: float | None,
        log_format: str,
    ) -> "NonInteractiveConfig":
        if log_format not in _LOG_FMT_VALUES:
            raise NonInteractiveUsageError(
                f"--log-format must be one of {sorted(_LOG_FMT_VALUES)}, got {log_format!r}"
            )
        if max_cost_usd is not None and max_cost_usd <= 0:
            raise NonInteractiveUsageError("--max-cost-usd must be positive")
        return cls(
            apply=apply,
            max_cost_usd=max_cost_usd,
            log_format=log_format,  # type: ignore[arg-type]
        )
