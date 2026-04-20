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
blueprint_app = typer.Typer(
    name="blueprint",
    help="Blueprint lifecycle commands (status, upgrade, sync, scan).",
)
app.add_typer(blueprint_app, name="blueprint")
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


_VALID_LANGUAGES: tuple[str, ...] = (
    "python", "typescript", "javascript", "rust", "go", "default",
)
_VALID_VISIBILITIES: tuple[str, ...] = ("private", "public")


def _parse_csv(value: Optional[str]) -> tuple[str, ...]:
    if not value:
        return ()
    return tuple(part.strip() for part in value.split(",") if part.strip())


def _commit_if_dirty(repo_path: Path, message: str) -> bool:
    """Stage everything in ``repo_path`` and commit if anything changed.

    Returns ``True`` when a commit was created, ``False`` when the tree
    was clean. Used by ``new`` to turn post-genesis phases
    (``blueprint-init`` today; ``run_onboard`` in the future) into their
    own follow-up commits instead of amending the genesis commit.
    """
    import subprocess

    status = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=repo_path, capture_output=True, text=True, check=True,
    )
    if not status.stdout.strip():
        return False
    subprocess.run(["git", "add", "-A"], cwd=repo_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", message],
        cwd=repo_path, check=True, capture_output=True, text=True,
    )
    return True


def _print_new_plan(result, *, spec, remote_target: str | None) -> None:
    """Pretty-print the final summary after ``new`` completes (or dry-runs)."""
    console.print()
    console.print(f"[bold]Repo created:[/bold] {remote_target or '(local only)'}")
    console.print(f"[bold]Local path:[/bold]   {result.path}")
    console.print(f"[bold]Marketplace:[/bold]  laurigates/claude-plugins")
    plugin_lines = ", ".join(result.plugins)
    console.print(f"[bold]Plugins:[/bold]      {plugin_lines}")
    if spec.stack_indicators:
        console.print(
            f"[bold]Indicators:[/bold]   {', '.join(spec.stack_indicators)}"
        )
    if result.dry_run:
        console.print("[yellow]DRY RUN — no filesystem changes were made[/yellow]")
    else:
        console.print(f"[dim]Next:         cd {result.path} && claude[/dim]")


@app.command()
def new(
    idea: str = typer.Argument(
        ...,
        help="Short description of what you want to build (1-2 sentences).",
    ),
    name: Optional[str] = typer.Option(
        None,
        "--name",
        help=(
            "Human-readable project name; also drives the directory / repo slug. "
            "Inferred from the idea when omitted."
        ),
    ),
    language: Optional[str] = typer.Option(
        None,
        "--language",
        help=(
            "Primary language: python | typescript | javascript | rust | go | default. "
            "Inferred from the idea when omitted."
        ),
    ),
    stack_indicators: Optional[str] = typer.Option(
        None,
        "--stack-indicators",
        help=(
            "Comma-separated extra stack indicators (e.g. 'docker,github-actions'). "
            "Merged with --language to pick plugins."
        ),
    ),
    description: Optional[str] = typer.Option(
        None,
        "--description",
        help="Short description (defaults to the idea argument).",
    ),
    owner: Optional[str] = typer.Option(
        None,
        "--owner",
        help="GitHub owner for `gh repo create` (defaults to current gh user).",
    ),
    visibility: str = typer.Option(
        "private",
        "--visibility",
        help="GitHub visibility: private or public.",
    ),
    parent_dir: str = typer.Option(
        ".",
        "--parent-dir",
        help="Directory in which to create the new repo (default: current dir).",
    ),
    no_remote: bool = typer.Option(
        False,
        "--no-remote",
        help="Skip `gh repo create`; keep the repo local-only.",
    ),
    skip_blueprint: bool = typer.Option(
        False,
        "--skip-blueprint",
        help="Skip `blueprint-init` after genesis (faster, but the repo won't have the blueprint layout).",
    ),
    extra_plugins: Optional[str] = typer.Option(
        None,
        "--extra-plugins",
        help="Comma-separated plugins to enable beyond stack-recommended defaults.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Print the plan and exit without creating any files.",
    ),
) -> None:
    """Create a new repository from an idea: genesis + plugin enrollment + (optionally) gh repo create.

    When ``--name`` is omitted, the idea string is sent to Claude for intent
    parsing — one short SDK call that returns a ``NewProjectSpec`` (name,
    language, stack indicators). Any explicit flags (``--language``,
    ``--description``, ``--stack-indicators``) layer on top as overrides.

    If the Claude API is unreachable and ``--name`` was not provided, the
    command exits with an error rather than falling back to a guessed
    scaffold.
    """
    from pathlib import Path

    from .creator import (
        NewProjectSpec,
        create_repo,
        gh_current_user,
        gh_repo_create,
        slugify,
    )
    from .intent import IntentParseError, parse_intent

    if language is not None and language not in _VALID_LANGUAGES:
        console.print(
            f"[red]Error:[/red] --language must be one of {list(_VALID_LANGUAGES)}, "
            f"got {language!r}"
        )
        raise typer.Exit(code=EXIT_CONFIG_ERROR)
    if visibility not in _VALID_VISIBILITIES:
        console.print(
            f"[red]Error:[/red] --visibility must be one of "
            f"{list(_VALID_VISIBILITIES)}, got {visibility!r}"
        )
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    parent = Path(parent_dir).resolve()
    if not parent.is_dir():
        console.print(f"[red]Error:[/red] --parent-dir is not a directory: {parent}")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    # Intent parsing: when --name is absent we treat this as the user
    # asking us to infer the project shape from the idea string. Explicit
    # flags below will still override.
    spec: NewProjectSpec
    if name is None:
        console.print("[dim]Parsing project intent via Claude...[/dim]")
        try:
            spec = asyncio.run(parse_intent(idea))
        except IntentParseError as exc:
            console.print(f"[red]Error:[/red] {exc}")
            raise typer.Exit(code=EXIT_RUNTIME_ERROR)
    else:
        try:
            slug = slugify(name)
        except ValueError as exc:
            console.print(f"[red]Error:[/red] {exc}")
            raise typer.Exit(code=EXIT_CONFIG_ERROR)
        spec = NewProjectSpec(
            name=name,
            slug=slug,
            description=description or idea,
            idea=idea,
            language=language or "default",
            stack_indicators=(),
            extra_plugins=(),
        )

    # Apply explicit overrides on top of the (possibly inferred) spec.
    effective_language = (language or spec.language).lower()
    effective_description = description or spec.description
    indicators: list[str] = list(spec.stack_indicators)
    if effective_language != "default" and effective_language not in indicators:
        indicators.insert(0, effective_language)
    for extra in _parse_csv(stack_indicators):
        if extra not in indicators:
            indicators.append(extra)

    spec = NewProjectSpec(
        name=spec.name,
        slug=spec.slug,
        description=effective_description,
        idea=idea,
        language=effective_language,
        stack_indicators=tuple(indicators),
        extra_plugins=_parse_csv(extra_plugins),
    )

    try:
        result = create_repo(spec=spec, parent_dir=parent, dry_run=dry_run)
    except FileExistsError as exc:
        console.print(f"[red]Error:[/red] {exc}")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)
    except FileNotFoundError as exc:
        console.print(f"[red]Error:[/red] {exc}")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    # After genesis: run blueprint-init so the repo has a blueprint layout
    # on day one. We run only the `init` phase (see ADR-007) — the derive-*
    # phases would have nothing to mine in a brand-new repo.
    if not dry_run and not skip_blueprint:
        from .blueprint_driver import (
            BlueprintDriver,
            DriverOptions,
            NEW_PHASES,
        )

        console.print("[dim]Running blueprint-init...[/dim]")
        driver = BlueprintDriver(
            result.path,
            DriverOptions(dry_run=False, non_interactive=True),
        )
        driver_result = asyncio.run(driver.run(NEW_PHASES))
        if not driver_result.succeeded:
            failed = [p.name for p in driver_result.phases if p.status == "error"]
            console.print(
                f"[yellow]blueprint-init had failures: {failed}. "
                "Continuing — the repo is usable without it.[/yellow]"
            )
        # If blueprint-init wrote anything, capture it as a second commit so
        # the genesis commit stays focused on scaffolding the user asked for.
        _commit_if_dirty(
            result.path,
            message="chore: initialize blueprint layout",
        )

    remote_target: str | None = None
    if not dry_run and not no_remote:
        repo_owner = owner or gh_current_user()
        if not repo_owner:
            console.print(
                "[yellow]Warning:[/yellow] could not determine gh user for "
                "`gh repo create`. Pass --owner or --no-remote. Skipping remote."
            )
        else:
            try:
                remote_target = gh_repo_create(
                    repo_path=result.path,
                    owner=repo_owner,
                    slug=spec.slug,
                    description=spec.description,
                    visibility=visibility,
                )
            except Exception as exc:  # subprocess.CalledProcessError / FileNotFoundError
                console.print(
                    f"[red]Failed to create GitHub repo:[/red] {exc}. "
                    f"Local repo preserved at {result.path}."
                )
                raise typer.Exit(code=EXIT_RUNTIME_ERROR)

    _print_new_plan(result, spec=spec, remote_target=remote_target)


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
    """Bootstrap a repository: scaffold blueprint files, CI workflows, and standards, then commit on a setup branch and (per --auto-pr) open a PR."""
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
    """Scan the repo for maintenance issues (docs, tests, security, etc.). With --fix, applies fixes on a branch and (per --auto-pr) opens a PR; with --report-only, writes findings without code changes."""
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
    """Collect diagnostics from CI/CD, Kubernetes, ArgoCD, and package sources for recent failures; with --create-issue (and per --auto-issues), opens a GitHub issue aggregating the findings."""
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
        help="Print the routing plan and exit without running maintain --fix.",
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
    """Analyze repo health attributes and run maintenance fixes on the highest-priority issues.

    Collects structured health attributes, ranks them by severity (respecting
    --min-severity and --focus), prints the routing plan, and then runs
    `maintain --fix` scoped to those priorities. Use --dry-run to only print
    the plan without modifying the repository.

    Side effects (unless --dry-run): may modify files, create a branch, commit,
    and — per --auto-pr policy inherited by maintain — open a pull request.
    """
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


def _run_blueprint_mode(
    repo: str,
    mode: str | None = None,
    dry_run: bool = False,
    phases: "tuple | None" = None,
) -> None:
    """Shared dispatch for the blueprint lifecycle subcommands.

    Either ``mode`` (looked up in ``PHASE_REGISTRIES``) or ``phases``
    (explicit tuple) must be provided. Each mode runs a fixed sequence
    of compiled-skill phases via the ``BlueprintDriver`` state machine
    (see ADR-006). Unlike ``onboard`` these commands operate in-place on
    the target repository — no worktree, no PR — because they are
    typically run ad hoc to inspect or update the existing blueprint
    state.
    """
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    from .blueprint_driver import BlueprintDriver, DriverOptions, PHASE_REGISTRIES

    if phases is None:
        if mode is None:
            console.print("[red]Error:[/red] internal: mode or phases required")
            raise typer.Exit(code=EXIT_CONFIG_ERROR)
        phases = PHASE_REGISTRIES.get(mode)
        if phases is None:
            console.print(f"[red]Error:[/red] unknown blueprint mode '{mode}'")
            raise typer.Exit(code=EXIT_CONFIG_ERROR)

    driver = BlueprintDriver(
        repo_path,
        DriverOptions(dry_run=dry_run, non_interactive=True),
    )
    result = asyncio.run(driver.run(phases))
    if not result.succeeded:
        raise typer.Exit(code=EXIT_RUNTIME_ERROR)


@blueprint_app.command("status")
def blueprint_status(
    repo: str = typer.Argument(".", help="Path to the repository."),
) -> None:
    """Report blueprint version, document counts, and feature-tracker stats."""
    _run_blueprint_mode(repo, "status", dry_run=False)


@blueprint_app.command("upgrade")
def blueprint_upgrade(
    repo: str = typer.Argument(".", help="Path to the repository."),
    dry_run: bool = typer.Option(
        False, "--dry-run",
        help="Report what would change without writing files.",
    ),
) -> None:
    """Migrate the blueprint to the latest format version, then re-sync IDs."""
    _run_blueprint_mode(repo, "upgrade", dry_run=dry_run)


@blueprint_app.command("sync")
def blueprint_sync(
    repo: str = typer.Argument(".", help="Path to the repository."),
    dry_run: bool = typer.Option(
        False, "--dry-run",
        help="Report drift without regenerating stale content.",
    ),
) -> None:
    """Detect drift in generated blueprint content and regenerate stale files."""
    _run_blueprint_mode(repo, "sync", dry_run=dry_run)


@blueprint_app.command("scan")
def blueprint_scan(
    repo: str = typer.Argument(".", help="Path to the monorepo root."),
    dry_run: bool = typer.Option(
        False, "--dry-run",
        help="Preview workspace discovery without updating the root manifest.",
    ),
) -> None:
    """Refresh the monorepo root manifest's workspaces registry and portfolio rollup."""
    _run_blueprint_mode(repo, "scan", dry_run=dry_run)


# --- No-argument generators ------------------------------------------------


@blueprint_app.command("adr-list")
def blueprint_adr_list(
    repo: str = typer.Argument(".", help="Path to the repository."),
) -> None:
    """List every ADR as a markdown table (title, status, date, domain)."""
    _run_blueprint_mode(repo, "adr-list", dry_run=False)


@blueprint_app.command("derive-plans")
def blueprint_derive_plans(
    repo: str = typer.Argument(".", help="Path to the repository."),
    dry_run: bool = typer.Option(
        False, "--dry-run",
        help="Preview what would be derived without writing artifacts.",
    ),
) -> None:
    """Derive PRDs, ADRs, and PRPs from git history and existing docs."""
    _run_blueprint_mode(repo, "derive-plans", dry_run=dry_run)


@blueprint_app.command("generate-rules")
def blueprint_generate_rules(
    repo: str = typer.Argument(".", help="Path to the repository."),
    dry_run: bool = typer.Option(
        False, "--dry-run",
        help="Preview rules without writing them.",
    ),
) -> None:
    """Generate project rules under `.claude/rules/` from blueprint PRDs."""
    _run_blueprint_mode(repo, "generate-rules", dry_run=dry_run)


# --- Argument-taking factories --------------------------------------------


@blueprint_app.command("promote")
def blueprint_promote(
    target: str = typer.Argument(
        ..., help="Name of the skill, command, or rule to promote."
    ),
    repo: str = typer.Argument(".", help="Path to the repository."),
) -> None:
    """Promote a generated artifact to the custom layer to preserve edits."""
    from .blueprint_driver import make_promote_phase

    _run_blueprint_mode(repo, phases=(make_promote_phase(target),))


@blueprint_app.command("prp-create")
def blueprint_prp_create(
    feature: str = typer.Argument(
        ..., help="Feature slug, e.g. auth-oauth2 or api-rate-limiting."
    ),
    repo: str = typer.Argument(".", help="Path to the repository."),
) -> None:
    """Create a PRP with curated context and validation gates for a feature."""
    from .blueprint_driver import make_prp_create_phase

    _run_blueprint_mode(repo, phases=(make_prp_create_phase(feature),))


@blueprint_app.command("prp-execute")
def blueprint_prp_execute(
    prp_name: str = typer.Argument(
        ..., help="Name of the PRP to execute, e.g. feature-auth-oauth2."
    ),
    repo: str = typer.Argument(".", help="Path to the repository."),
) -> None:
    """Execute a PRP with the validation-loop TDD workflow."""
    from .blueprint_driver import make_prp_execute_phase

    _run_blueprint_mode(repo, phases=(make_prp_execute_phase(prp_name),))


@blueprint_app.command("work-order")
def blueprint_work_order(
    repo: str = typer.Argument(".", help="Path to the repository."),
    from_issue: Optional[int] = typer.Option(
        None, "--from-issue",
        help="Create a work order from an existing GitHub issue number.",
    ),
    no_publish: bool = typer.Option(
        False, "--no-publish",
        help="Keep the work order local; do not push or publish it.",
    ),
) -> None:
    """Create an isolated work order suitable for subagent execution."""
    from .blueprint_driver import make_work_order_phase

    _run_blueprint_mode(
        repo,
        phases=(make_work_order_phase(from_issue=from_issue, publish=not no_publish),),
    )


if __name__ == "__main__":
    app()
