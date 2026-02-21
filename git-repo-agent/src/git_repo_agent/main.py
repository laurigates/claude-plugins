"""CLI entry point for git-repo-agent."""

import asyncio
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console

app = typer.Typer(
    name="git-repo-agent",
    help="Claude Agent SDK app for repo onboarding and maintenance.",
)
console = Console()


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
) -> None:
    """Onboard a repository with blueprint structure and standards."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=1)

    from .orchestrator import run_onboard

    asyncio.run(
        run_onboard(
            repo_path=repo_path,
            dry_run=dry_run,
            skip_ci=skip_ci,
            skip_blueprint=skip_blueprint,
            branch=branch,
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
) -> None:
    """Run maintenance checks and optionally fix issues."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=1)

    from .orchestrator import run_maintain

    asyncio.run(
        run_maintain(
            repo_path=repo_path,
            fix=fix,
            report_only=report_only,
            focus=focus,
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
        raise typer.Exit(code=1)

    from .orchestrator import run_health

    run_health(repo_path=repo_path)


if __name__ == "__main__":
    app()
