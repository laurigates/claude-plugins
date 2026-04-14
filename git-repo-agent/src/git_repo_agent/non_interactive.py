"""Non-interactive run configuration and exit-code contract.

See ``docs/adr/005-non-interactive-scheduled-execution.md`` for the full
contract. The key idea is that a caller running git-repo-agent from a
scheduled job (Claude Code desktop schedules, cron, GitHub Actions, …)
declares up front what the agent should do with every decision point —
we never silently skip a prompt.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

# Exit codes. See ADR-005.
EXIT_SUCCESS = 0
EXIT_RUNTIME_ERROR = 1
EXIT_CONFIG_ERROR = 2
EXIT_LOCKED = 3
EXIT_HOOK_BLOCKED = 4


class NonInteractiveUsageError(ValueError):
    """Raised when non-interactive flags are inconsistent or unsupported."""


class LockedError(RuntimeError):
    """Raised when another git-repo-agent run holds the repo lock."""


class HookBlockedError(RuntimeError):
    """Raised when a safety hook blocked a critical operation."""


AutoPr = Literal["always", "never", "on-changes"]
AutoIssues = Literal["always", "never", "on-findings"]
OnDuplicate = Literal["skip", "append", "new"]
LogFormat = Literal["text", "json", "plain"]
Notify = Literal["none", "pr-comment", "issue"]

_AUTO_PR_VALUES = {"always", "never", "on-changes"}
_AUTO_ISSUES_VALUES = {"always", "never", "on-findings"}
_ON_DUP_VALUES = {"skip", "append", "new"}
_LOG_FMT_VALUES = {"text", "json", "plain"}
_NOTIFY_VALUES = {"none", "pr-comment", "issue"}


@dataclass(frozen=True)
class NonInteractiveConfig:
    """Validated policy for a non-interactive run."""

    auto_pr: AutoPr
    auto_issues: AutoIssues
    on_duplicate: OnDuplicate
    refresh_base: bool
    max_cost_usd: float | None
    log_format: LogFormat
    notify: Notify

    @classmethod
    def build(
        cls,
        *,
        auto_pr: str,
        auto_issues: str,
        on_duplicate: str,
        refresh_base: bool,
        max_cost_usd: float | None,
        log_format: str,
        notify: str,
    ) -> "NonInteractiveConfig":
        _check(auto_pr, _AUTO_PR_VALUES, "--auto-pr")
        _check(auto_issues, _AUTO_ISSUES_VALUES, "--auto-issues")
        _check(on_duplicate, _ON_DUP_VALUES, "--on-duplicate")
        _check(log_format, _LOG_FMT_VALUES, "--log-format")
        _check(notify, _NOTIFY_VALUES, "--notify")
        if max_cost_usd is not None and max_cost_usd <= 0:
            raise NonInteractiveUsageError("--max-cost-usd must be positive")
        return cls(
            auto_pr=auto_pr,  # type: ignore[arg-type]
            auto_issues=auto_issues,  # type: ignore[arg-type]
            on_duplicate=on_duplicate,  # type: ignore[arg-type]
            refresh_base=refresh_base,
            max_cost_usd=max_cost_usd,
            log_format=log_format,  # type: ignore[arg-type]
            notify=notify,  # type: ignore[arg-type]
        )


def _check(value: str, allowed: set[str], flag: str) -> None:
    if value not in allowed:
        raise NonInteractiveUsageError(
            f"{flag} must be one of {sorted(allowed)}, got {value!r}"
        )
