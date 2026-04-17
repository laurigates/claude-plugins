"""CLI entry point for vault-agent."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

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
from .reporting import render_json, render_markdown, render_terminal
from .maintain import run_maintain, render as render_maintain, AVAILABLE_MODES
from .mocs_mode import render_report as render_mocs_report
from .mocs_mode import run_mocs
from .stubs_mode import render_apply as render_stubs_apply
from .stubs_mode import render_dry_run as render_stubs_dry_run
from .stubs_mode import run_stubs

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
) -> None:
    """Mechanical fixes: bare emoji tags, legacy id:, Templater leakage."""
    result = run_lint(vault, apply=not dry_run)
    if result.dry_run:
        typer.echo(render_lint_dry_run(result.plan))
    else:
        typer.echo(render_lint_apply(result))


@app.command()
def links(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    dry_run: bool = typer.Option(True, "--dry-run/--fix", help="Preview or apply fixes."),
) -> None:
    """Broken-wikilink repair and cross-namespace ambiguity resolution."""
    result = run_links(vault, apply=not dry_run)
    if result.dry_run:
        typer.echo(render_links_dry_run(result.plan))
    else:
        typer.echo(render_links_apply(result))


@app.command()
def stubs(
    vault: Path = typer.Argument(..., exists=True, file_okay=False, dir_okay=True),
    dry_run: bool = typer.Option(True, "--dry-run/--fix", help="Preview or apply fixes."),
) -> None:
    """Classify FVH/z stubs; fix broken_redirects; report stale_duplicates."""
    result = run_stubs(vault, apply=not dry_run)
    if result.dry_run:
        typer.echo(render_stubs_dry_run(result.plan))
    else:
        typer.echo(render_stubs_apply(result))


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
) -> None:
    """Run multiple modes sequentially in a single worktree."""
    mode_list = [m.strip() for m in modes.split(",") if m.strip()]
    result = run_maintain(vault, modes=mode_list, apply=not dry_run)
    typer.echo(render_maintain(result))


if __name__ == "__main__":
    app()
