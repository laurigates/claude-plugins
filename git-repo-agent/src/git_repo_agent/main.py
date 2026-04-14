"""CLI entry point for git-repo-agent."""

import asyncio
import sys
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console

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

app = typer.Typer(
    name="git-repo-agent",
    help="Claude Agent SDK app for repo onboarding and maintenance.",
)
console = Console()


def _build_ni_config(
    *,
    non_interactive: bool,
    auto_pr: str,
    auto_issues: str,
    on_duplicate: str,
    refresh_base: bool,
    max_cost_usd: Optional[float],
    log_format: Optional[str],
    notify: str,
) -> Optional[NonInteractiveConfig]:
    """Validate non-interactive flags and return a config, or None if interactive."""
    stdin_tty = sys.stdin.isatty()
    stdout_tty = sys.stdout.isatty()

    # Refuse silent breakage: if stdin isn't a TTY and the caller didn't opt in,
    # exit loudly rather than letting console.input() eat an empty string.
    if not stdin_tty and not non_interactive:
        console.print(
            "[red]Error:[/red] stdin is not a TTY. "
            "Pass [bold]--non-interactive[/bold] to enable scheduled / headless "
            "execution and declare how PR / issue decisions should be made "
            "(e.g. --auto-pr=on-changes, --auto-issues=on-findings).",
        )
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    if not non_interactive:
        return None

    # Default log format: plain when stdout isn't a TTY.
    effective_log_format = log_format or ("text" if stdout_tty else "plain")

    try:
        return NonInteractiveConfig.build(
            auto_pr=auto_pr,
            auto_issues=auto_issues,
            on_duplicate=on_duplicate,
            refresh_base=refresh_base,
            max_cost_usd=max_cost_usd,
            log_format=effective_log_format,
            notify=notify,
        )
    except NonInteractiveUsageError as exc:
        console.print(f"[red]Error:[/red] {exc}")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)


def _dispatch(coro) -> None:
    """Run an async orchestrator coroutine and map exceptions to exit codes."""
    try:
        asyncio.run(coro)
    except LockedError as exc:
        console.print(f"[yellow]{exc}[/yellow]")
        raise typer.Exit(code=EXIT_LOCKED)
    except HookBlockedError as exc:
        console.print(f"[red]Blocked by safety hook:[/red] {exc}", style="bold")
        raise typer.Exit(code=EXIT_HOOK_BLOCKED)
    except NonInteractiveUsageError as exc:
        console.print(f"[red]Error:[/red] {exc}")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)
    except typer.Exit:
        raise
    except Exception as exc:  # pragma: no cover - defensive
        console.print(f"[red]Unexpected error:[/red] {exc}")
        raise typer.Exit(code=EXIT_RUNTIME_ERROR)
    raise typer.Exit(code=EXIT_SUCCESS)


@app.command()
def onboard(
    repo: str = typer.Argument(
        ".",
        help="Path to the repository to onboard.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Preview analysis without making changes.",
    ),
    skip_ci: bool = typer.Option(
        False,
        "--skip-ci",
        help="Skip CI/CD workflow setup.",
    ),
    skip_blueprint: bool = typer.Option(
        False,
        "--skip-blueprint",
        help="Skip blueprint initialization.",
    ),
    branch: str = typer.Option(
        "setup/onboard",
        "--branch",
        help="Branch name for onboarding changes.",
    ),
    non_interactive: bool = typer.Option(
        False, "--non-interactive",
        help="Run without prompting (required when stdin is not a TTY).",
    ),
    auto_pr: str = typer.Option(
        "on-changes", "--auto-pr",
        help="Non-interactive PR policy: always, never, on-changes.",
    ),
    auto_issues: str = typer.Option(
        "never", "--auto-issues",
        help="Non-interactive issue policy (unused by onboard): always, never, on-findings.",
    ),
    on_duplicate: str = typer.Option(
        "skip", "--on-duplicate",
        help="Policy if an open PR on the same branch prefix exists: skip, append, new.",
    ),
    refresh_base: bool = typer.Option(
        False, "--refresh-base/--no-refresh-base",
        help="git fetch + fast-forward the base branch before starting.",
    ),
    max_cost_usd: Optional[float] = typer.Option(
        None, "--max-cost-usd",
        help="Warn if session cost exceeds this amount.",
    ),
    log_format: Optional[str] = typer.Option(
        None, "--log-format",
        help="Output format: text, json, plain. Default: plain when not a TTY.",
    ),
) -> None:
    """Onboard a repository with blueprint structure and standards."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    ni = _build_ni_config(
        non_interactive=non_interactive,
        auto_pr=auto_pr,
        auto_issues=auto_issues,
        on_duplicate=on_duplicate,
        refresh_base=refresh_base,
        max_cost_usd=max_cost_usd,
        log_format=log_format,
        notify="none",
    )

    from .orchestrator import run_onboard

    _dispatch(
        run_onboard(
            repo_path=repo_path,
            dry_run=dry_run,
            skip_ci=skip_ci,
            skip_blueprint=skip_blueprint,
            branch=branch,
            non_interactive=ni,
        )
    )


@app.command()
def maintain(
    repo: str = typer.Argument(
        ".",
        help="Path to the repository to maintain.",
    ),
    fix: bool = typer.Option(
        False,
        "--fix",
        help="Auto-fix issues found.",
    ),
    report_only: bool = typer.Option(
        False,
        "--report-only",
        help="Generate report without making changes.",
    ),
    focus: Optional[str] = typer.Option(
        None,
        "--focus",
        help="Comma-separated areas to focus on (docs,tests,security).",
    ),
    non_interactive: bool = typer.Option(
        False, "--non-interactive",
        help="Run without prompting (required when stdin is not a TTY).",
    ),
    auto_pr: str = typer.Option(
        "on-changes", "--auto-pr",
        help="Non-interactive PR policy: always, never, on-changes.",
    ),
    auto_issues: str = typer.Option(
        "on-findings", "--auto-issues",
        help="Non-interactive issue policy (report-only): always, never, on-findings.",
    ),
    on_duplicate: str = typer.Option(
        "skip", "--on-duplicate",
        help="Policy if an open PR exists for the same workflow: skip, append, new.",
    ),
    refresh_base: bool = typer.Option(
        False, "--refresh-base/--no-refresh-base",
        help="git fetch + fast-forward the base branch before starting.",
    ),
    max_cost_usd: Optional[float] = typer.Option(
        None, "--max-cost-usd",
        help="Warn if session cost exceeds this amount.",
    ),
    log_format: Optional[str] = typer.Option(
        None, "--log-format",
        help="Output format: text, json, plain. Default: plain when not a TTY.",
    ),
) -> None:
    """Run maintenance checks and optionally fix issues."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    ni = _build_ni_config(
        non_interactive=non_interactive,
        auto_pr=auto_pr,
        auto_issues=auto_issues,
        on_duplicate=on_duplicate,
        refresh_base=refresh_base,
        max_cost_usd=max_cost_usd,
        log_format=log_format,
        notify="none",
    )

    # The two-phase interactive maintain flow cannot run without a human.
    if ni is not None and not (fix or report_only):
        console.print(
            "[red]Error:[/red] non-interactive `maintain` requires either "
            "[bold]--fix[/bold] or [bold]--report-only[/bold]. The default "
            "interactive flow needs a human to select fixes."
        )
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    from .orchestrator import run_maintain

    _dispatch(
        run_maintain(
            repo_path=repo_path,
            fix=fix,
            report_only=report_only,
            focus=focus,
            non_interactive=ni,
        )
    )


@app.command()
def diagnose(
    repo: str = typer.Argument(
        ".",
        help="Path to the repository to diagnose.",
    ),
    sources: Optional[str] = typer.Option(
        None,
        "--sources",
        help="Comma-separated diagnostic sources (kubectl,argocd,actions,packages). Default: auto-detect.",
    ),
    create_issue: bool = typer.Option(
        False,
        "--create-issue",
        help="Create a GitHub issue with aggregated diagnostics.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Collect and display diagnostics without creating issues.",
    ),
    namespace: Optional[str] = typer.Option(
        None,
        "--namespace",
        help="Kubernetes namespace for kubectl/argocd queries.",
    ),
    app_name: Optional[str] = typer.Option(
        None,
        "--app",
        help="ArgoCD application name.",
    ),
    non_interactive: bool = typer.Option(
        False, "--non-interactive",
        help="Run without prompting (required when stdin is not a TTY).",
    ),
    auto_issues: str = typer.Option(
        "on-findings", "--auto-issues",
        help="Non-interactive issue policy: always, never, on-findings.",
    ),
    max_cost_usd: Optional[float] = typer.Option(
        None, "--max-cost-usd",
        help="Warn if session cost exceeds this amount.",
    ),
    log_format: Optional[str] = typer.Option(
        None, "--log-format",
        help="Output format: text, json, plain. Default: plain when not a TTY.",
    ),
) -> None:
    """Diagnose pipeline failures and optionally create a GitHub issue."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    ni = _build_ni_config(
        non_interactive=non_interactive,
        auto_pr="never",
        auto_issues=auto_issues,
        on_duplicate="skip",
        refresh_base=False,
        max_cost_usd=max_cost_usd,
        log_format=log_format,
        notify="none",
    )

    from .orchestrator import run_diagnose

    _dispatch(
        run_diagnose(
            repo_path=repo_path,
            sources=sources,
            create_issue=create_issue,
            dry_run=dry_run,
            namespace=namespace,
            app_name=app_name,
            non_interactive=ni,
        )
    )


@app.command()
def health(
    repo: str = typer.Argument(
        ".",
        help="Path to the repository to check.",
    ),
) -> None:
    """Quick health score for a repository."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    from .orchestrator import run_health

    run_health(repo_path=repo_path)


@app.command()
def attributes(
    repo: str = typer.Argument(
        ".",
        help="Path to the repository to analyze.",
    ),
    output: Optional[str] = typer.Option(
        None,
        "--output",
        help="Write JSON output to file.",
    ),
    fmt: str = typer.Option(
        "terminal",
        "--format",
        help="Output format: terminal, json, or routing.",
    ),
) -> None:
    """Collect structured codebase health attributes with severity and actions."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    from .tools.attributes import (
        collect_attributes,
        format_attributes_terminal,
        format_routing_instructions,
        route_from_attributes,
    )

    data = collect_attributes(repo_path)

    if fmt == "terminal":
        console.print(format_attributes_terminal(data))
    elif fmt == "routing":
        priorities = route_from_attributes(data["attributes"])
        console.print(format_routing_instructions(priorities))
    else:
        import json as _json

        console.print(_json.dumps(data, indent=2))

    if output:
        import json as _json

        Path(output).write_text(_json.dumps(data, indent=2), encoding="utf-8")
        console.print(f"[dim]Written to {output}[/dim]")


@app.command()
def route(
    repo: str = typer.Argument(
        ".",
        help="Path to the repository to analyze.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Show routing plan without executing.",
    ),
    focus: Optional[str] = typer.Option(
        None,
        "--focus",
        help="Comma-separated categories to focus on.",
    ),
    min_severity: str = typer.Option(
        "medium",
        "--min-severity",
        help="Minimum severity threshold: critical, high, medium, low.",
    ),
) -> None:
    """Route to agents based on attribute analysis."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    from .tools.attributes import (
        collect_attributes,
        format_routing_instructions,
        route_from_attributes,
    )

    data = collect_attributes(repo_path)
    attrs = data["attributes"]

    # Filter by focus categories
    if focus:
        focus_cats = {c.strip() for c in focus.split(",")}
        attrs = [a for a in attrs if a.get("category") in focus_cats]

    priorities = route_from_attributes(attrs, min_severity=min_severity)
    console.print(format_routing_instructions(priorities))

    if dry_run or not priorities:
        return

    # Non-dry-run: run maintain with attribute-driven priorities
    from .orchestrator import run_maintain

    asyncio.run(
        run_maintain(
            repo_path=repo_path,
            fix=True,
            focus=focus,
        )
    )


if __name__ == "__main__":
    app()
