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
) -> None:
    """Diagnose pipeline failures and optionally create a GitHub issue."""
    repo_path = Path(repo).resolve()
    if not repo_path.is_dir():
        console.print(f"[red]Error:[/red] {repo_path} is not a directory")
        raise typer.Exit(code=1)

    from .orchestrator import run_diagnose

    asyncio.run(
        run_diagnose(
            repo_path=repo_path,
            sources=sources,
            create_issue=create_issue,
            dry_run=dry_run,
            namespace=namespace,
            app_name=app_name,
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
        raise typer.Exit(code=1)

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
        raise typer.Exit(code=1)

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
