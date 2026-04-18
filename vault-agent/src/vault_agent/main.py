"""CLI entry point for vault-agent."""

from __future__ import annotations

import json
import signal
import sys
from pathlib import Path
from typing import Any, Callable, Optional

import typer
from rich.console import Console

from . import __version__
from .analyzers.audit import run_audit
from .lint import render_apply as render_lint_apply
from .lint import render_dry_run as render_lint_dry_run
from .lint import run_lint
from .links_mode import render_apply as render_links_apply
from .links_mode import render_dry_run as render_links_dry_run
from .links_mode import run_links
from .maintain import AVAILABLE_MODES, render as render_maintain, run_maintain
from .mocs_mode import render_report as render_mocs_report
from .mocs_mode import run_mocs
from .non_interactive import (
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
from .reporting import render_json, render_markdown, render_terminal
from .stubs_mode import render_apply as render_stubs_apply
from .stubs_mode import render_dry_run as render_stubs_dry_run
from .stubs_mode import run_stubs
from .worktree import acquire_lock, release_lock

app = typer.Typer(
    name="vault-agent",
    help="Claude Agent SDK app for Obsidian vault maintenance.",
    no_args_is_help=True,
)
console = Console()


def _version_callback(value: bool) -> None:
    if value:
        console.print(f"vault-agent {__version__}")
        raise typer.Exit()


@app.callback()
def main(
    version: Optional[bool] = typer.Option(
        None,
        "--version",
        callback=_version_callback,
        is_eager=True,
        help="Show version and exit.",
    ),
) -> None:
    """vault-agent — maintain an Obsidian vault."""


# ---------------------------------------------------------------------------
# Non-interactive plumbing
# ---------------------------------------------------------------------------


def _build_ni_config(
    *,
    non_interactive: bool,
    apply: bool,
    max_cost_usd: Optional[float],
    log_format: Optional[str],
) -> Optional[NonInteractiveConfig]:
    """Validate non-interactive flags and return a config, or None if interactive.

    Refuses to proceed when stdin is not a TTY and ``--non-interactive`` was
    not passed: this is silent-breakage prevention for scheduled / headless
    runs that would otherwise hang on a ``console.input()`` call.
    """
    stdin_tty = sys.stdin.isatty()
    stdout_tty = sys.stdout.isatty()

    if not stdin_tty and not non_interactive:
        console.print(
            "[red]Error:[/red] stdin is not a TTY. "
            "Pass [bold]--non-interactive[/bold] to run in scheduled / headless mode."
        )
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    if not non_interactive:
        return None

    effective_log_format = log_format or ("text" if stdout_tty else "plain")

    try:
        return NonInteractiveConfig.build(
            apply=apply,
            max_cost_usd=max_cost_usd,
            log_format=effective_log_format,
        )
    except NonInteractiveUsageError as exc:
        console.print(f"[red]Error:[/red] {exc}")
        raise typer.Exit(code=EXIT_CONFIG_ERROR) from exc


def _install_cleanup_handler(cleanup: Callable[[], None]):
    """Install SIGTERM/SIGINT handlers that invoke ``cleanup`` then re-raise.

    Returns a token the caller must pass to ``_restore_handlers`` to revert.
    """
    prev_term = signal.getsignal(signal.SIGTERM)
    prev_int = signal.getsignal(signal.SIGINT)

    def _handler(signum, _frame):
        try:
            cleanup()
        finally:
            signal.signal(signum, signal.SIG_DFL)
            import os

            os.kill(os.getpid(), signum)

    signal.signal(signal.SIGTERM, _handler)
    signal.signal(signal.SIGINT, _handler)
    return (prev_term, prev_int)


def _restore_handlers(token) -> None:
    prev_term, prev_int = token
    signal.signal(signal.SIGTERM, prev_term)
    signal.signal(signal.SIGINT, prev_int)


def _emit_summary(payload: dict[str, Any], log_format: Optional[str]) -> None:
    """Emit a single-line JSON summary when ``log_format == 'json'``.

    For non-JSON formats we emit nothing — the human-readable banner that
    each mode renders is enough context for a user reading the terminal.
    """
    if log_format != "json":
        return
    sys.stdout.write(json.dumps(payload, default=str) + "\n")
    sys.stdout.flush()


def _run_write_mode(
    *,
    mode: str,
    vault: Path,
    apply: bool,
    ni: Optional[NonInteractiveConfig],
    action: Callable[[], Any],
    summary_payload: Callable[[Any], dict[str, Any]],
    render: Callable[[Any], str],
) -> None:
    """Shared runner: lock → signals → action → render → summary → release.

    ``action`` performs the actual work (calls ``run_lint`` / ``run_links`` etc.)
    and returns the mode's result object. ``summary_payload`` builds the dict
    emitted on ``--log-format=json``. ``render`` turns the result into a
    terminal-friendly string.

    The lock is only acquired for write runs (``apply and ni is not None``):
    the lock exists to prevent two scheduled jobs from racing on the same
    worktree, which is irrelevant in dry-run or interactive use.
    """
    lock_path: Optional[Path] = None
    cleanup_token = None
    log_format = ni.log_format if ni is not None else None

    need_lock = apply and ni is not None
    if need_lock:
        lock_path = acquire_lock(vault)
        if lock_path is None:
            console.print(
                f"[yellow]Another vault-agent run holds the lock at "
                f"{vault / '.claude' / 'worktrees' / '.vault-agent.lock'}[/yellow]"
            )
            raise typer.Exit(code=EXIT_LOCKED)

        def _cleanup() -> None:
            release_lock(lock_path)

        cleanup_token = _install_cleanup_handler(_cleanup)

    try:
        result = action()
        typer.echo(render(result))
        _emit_summary({"mode": mode, **summary_payload(result)}, log_format)
    except LockedError as exc:
        console.print(f"[yellow]{exc}[/yellow]")
        raise typer.Exit(code=EXIT_LOCKED) from exc
    except HookBlockedError as exc:
        console.print(f"[red]Blocked by safety hook:[/red] {exc}", style="bold")
        raise typer.Exit(code=EXIT_HOOK_BLOCKED) from exc
    except NonInteractiveUsageError as exc:
        console.print(f"[red]Error:[/red] {exc}")
        raise typer.Exit(code=EXIT_CONFIG_ERROR) from exc
    except typer.Exit:
        raise
    except Exception as exc:  # noqa: BLE001 — last-resort mapper to EXIT_RUNTIME_ERROR
        console.print(f"[red]Unexpected error:[/red] {exc}")
        raise typer.Exit(code=EXIT_RUNTIME_ERROR) from exc
    finally:
        if cleanup_token is not None:
            _restore_handlers(cleanup_token)
        release_lock(lock_path)


def _handle_result(handle) -> dict[str, Any]:
    """Extract branch / commits / files from a worktree handle, if present."""
    if handle is None:
        return {"branch": None, "files_changed": 0}
    from .worktree import worktree_commit_count, worktree_file_change_count

    return {
        "branch": handle.branch,
        "files_changed": worktree_file_change_count(handle),
        "commits": worktree_commit_count(handle),
    }


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


@app.command()
def analyze(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    format: str = typer.Option("text", "--format", help="text | json | markdown"),
) -> None:
    """Run all read-only analyzers and emit a report. No LLM."""
    audit = run_audit(vault)
    if format == "json":
        typer.echo(render_json(audit))
    elif format == "markdown" or format == "md":
        typer.echo(render_markdown(audit))
    else:
        render_terminal(audit, console)


@app.command()
def health(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
) -> None:
    """Compute the vault health score (0-100). No LLM."""
    audit = run_audit(vault)
    h = audit.health
    console.print(
        f"[bold]{h.total}[/bold]/100 "
        f"(tags={h.tags} links={h.links} orphans={h.orphans} "
        f"stubs={h.stubs} mocs={h.mocs})"
    )


@app.command()
def report(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    format: str = typer.Option("md", "--format", help="md | json"),
) -> None:
    """Emit a formatted report from the latest analysis."""
    audit = run_audit(vault)
    if format == "json":
        typer.echo(render_json(audit))
    else:
        typer.echo(render_markdown(audit))


@app.command()
def lint(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    dry_run: bool = typer.Option(True, "--dry-run/--fix", help="Preview or apply fixes."),
    non_interactive: bool = typer.Option(
        False, "--non-interactive",
        help="Run without prompting (required when stdin is not a TTY).",
    ),
    max_cost_usd: Optional[float] = typer.Option(
        None, "--max-cost-usd",
        help="Warn if session cost exceeds this amount (enforced when SDK session runs).",
    ),
    log_format: Optional[str] = typer.Option(
        None, "--log-format",
        help="Output format: text, json, plain. Default: plain when not a TTY.",
    ),
) -> None:
    """Mechanical fixes: bare emoji tags, legacy id:, Templater leakage."""
    ni = _build_ni_config(
        non_interactive=non_interactive,
        apply=not dry_run,
        max_cost_usd=max_cost_usd,
        log_format=log_format,
    )
    _run_write_mode(
        mode="lint",
        vault=vault,
        apply=not dry_run,
        ni=ni,
        action=lambda: run_lint(vault, apply=not dry_run),
        summary_payload=lambda r: {
            "dry_run": r.dry_run,
            "health_before": r.audit.health.total,
            **_handle_result(r.handle),
        },
        render=lambda r: render_lint_dry_run(r.plan) if r.dry_run else render_lint_apply(r),
    )


@app.command()
def links(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    dry_run: bool = typer.Option(True, "--dry-run/--fix", help="Preview or apply fixes."),
    non_interactive: bool = typer.Option(
        False, "--non-interactive",
        help="Run without prompting (required when stdin is not a TTY).",
    ),
    max_cost_usd: Optional[float] = typer.Option(
        None, "--max-cost-usd",
        help="Warn if session cost exceeds this amount (enforced when SDK session runs).",
    ),
    log_format: Optional[str] = typer.Option(
        None, "--log-format",
        help="Output format: text, json, plain. Default: plain when not a TTY.",
    ),
) -> None:
    """Broken-wikilink repair and cross-namespace ambiguity resolution."""
    ni = _build_ni_config(
        non_interactive=non_interactive,
        apply=not dry_run,
        max_cost_usd=max_cost_usd,
        log_format=log_format,
    )
    _run_write_mode(
        mode="links",
        vault=vault,
        apply=not dry_run,
        ni=ni,
        action=lambda: run_links(vault, apply=not dry_run),
        summary_payload=lambda r: {
            "dry_run": r.dry_run,
            "health_before": r.audit.health.total,
            **_handle_result(r.handle),
        },
        render=lambda r: render_links_dry_run(r.plan) if r.dry_run else render_links_apply(r),
    )


@app.command()
def stubs(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    dry_run: bool = typer.Option(True, "--dry-run/--fix", help="Preview or apply fixes."),
    non_interactive: bool = typer.Option(
        False, "--non-interactive",
        help="Run without prompting (required when stdin is not a TTY).",
    ),
    max_cost_usd: Optional[float] = typer.Option(
        None, "--max-cost-usd",
        help="Warn if session cost exceeds this amount (enforced when SDK session runs).",
    ),
    log_format: Optional[str] = typer.Option(
        None, "--log-format",
        help="Output format: text, json, plain. Default: plain when not a TTY.",
    ),
) -> None:
    """Classify FVH/z stubs; fix broken_redirects; report stale_duplicates."""
    ni = _build_ni_config(
        non_interactive=non_interactive,
        apply=not dry_run,
        max_cost_usd=max_cost_usd,
        log_format=log_format,
    )
    _run_write_mode(
        mode="stubs",
        vault=vault,
        apply=not dry_run,
        ni=ni,
        action=lambda: run_stubs(vault, apply=not dry_run),
        summary_payload=lambda r: {
            "dry_run": r.dry_run,
            "health_before": r.audit.health.total,
            **_handle_result(r.handle),
        },
        render=lambda r: render_stubs_dry_run(r.plan) if r.dry_run else render_stubs_apply(r),
    )


@app.command()
def mocs(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    dry_run: bool = typer.Option(
        True, "--dry-run/--fix", help="Read-only in the deterministic path."
    ),
) -> None:
    """MOC analysis: inventory, coverage, missing-MOC candidates."""
    _, report = run_mocs(vault)
    typer.echo(render_mocs_report(report))


@app.command()
def maintain(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    modes: str = typer.Option(
        "lint,links,stubs,mocs",
        "--modes",
        help=f"Comma-separated modes. Available: {','.join(AVAILABLE_MODES)}",
    ),
    dry_run: bool = typer.Option(True, "--dry-run/--fix", help="Preview or apply fixes."),
    non_interactive: bool = typer.Option(
        False, "--non-interactive",
        help="Run without prompting (required when stdin is not a TTY).",
    ),
    max_cost_usd: Optional[float] = typer.Option(
        None, "--max-cost-usd",
        help="Warn if session cost exceeds this amount (enforced when SDK session runs).",
    ),
    log_format: Optional[str] = typer.Option(
        None, "--log-format",
        help="Output format: text, json, plain. Default: plain when not a TTY.",
    ),
) -> None:
    """Run multiple modes sequentially in a single worktree."""
    mode_list = [m.strip() for m in modes.split(",") if m.strip()]
    ni = _build_ni_config(
        non_interactive=non_interactive,
        apply=not dry_run,
        max_cost_usd=max_cost_usd,
        log_format=log_format,
    )
    _run_write_mode(
        mode="maintain",
        vault=vault,
        apply=not dry_run,
        ni=ni,
        action=lambda: run_maintain(vault, modes=mode_list, apply=not dry_run),
        summary_payload=lambda r: {
            "dry_run": r.dry_run,
            "modes": r.modes_requested,
            "commit_count": len(r.commits),
            **_handle_result(r.handle),
        },
        render=render_maintain,
    )


if __name__ == "__main__":
    app()
