"""Orchestrator — core agent logic for git-repo-agent."""

import json
from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    SystemMessage,
    TextBlock,
    ToolUseBlock,
    query,
)
from rich.console import Console

from .agents.blueprint import definition as blueprint_definition
from .agents.configure import definition as configure_definition
from .agents.docs import definition as docs_definition
from .agents.quality import definition as quality_definition
from .agents.security import definition as security_definition
from .agents.test_runner import definition as test_runner_definition
from .tools.health_check import compute_health_score
from .tools.repo_analyzer import analyze_repo
from .tools.report import generate_report

console = Console()

_PROMPTS_DIR = Path(__file__).parent / "prompts"


def _load_prompt(name: str) -> str:
    """Load a prompt file from the prompts directory."""
    return (_PROMPTS_DIR / f"{name}.md").read_text(encoding="utf-8")


def _pre_compute_context(repo_path: Path) -> str:
    """Pre-compute repository analysis and health score.

    Returns a formatted string to embed in the agent prompt.
    See ADR-001 for why this replaces SDK MCP servers.
    """
    analysis = analyze_repo(repo_path)
    health = compute_health_score(repo_path)

    return (
        "## Pre-computed Repository Analysis\n\n"
        "The following data was computed before this session started. "
        "Use it to plan your work — no need to re-analyze.\n\n"
        "### repo_analyze result\n\n"
        f"```json\n{json.dumps(analysis, indent=2)}\n```\n\n"
        "### health_score result\n\n"
        f"```json\n{json.dumps(health, indent=2)}\n```\n"
    )


async def run_onboard(
    repo_path: Path,
    dry_run: bool = False,
    skip_ci: bool = False,
    skip_blueprint: bool = False,
    branch: str = "setup/onboard",
) -> None:
    """Run the onboarding workflow for a repository."""
    console.print(f"[bold]Git Repo Agent[/bold] — Onboarding [cyan]{repo_path}[/cyan]")
    if dry_run:
        console.print("[yellow]DRY RUN — no changes will be made[/yellow]")
    console.print()

    # Pre-compute analysis (see ADR-001)
    console.print("[dim]Analyzing repository...[/dim]")
    repo_context = _pre_compute_context(repo_path)

    # Build system prompt with embedded analysis
    system_prompt = (
        _load_prompt("orchestrator")
        + "\n\n"
        + _load_prompt("onboard")
        + "\n\n"
        + repo_context
    )

    # Build orchestrator options
    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        cwd=str(repo_path),
        max_turns=50,
        allowed_tools=[
            "Read",
            "Write",
            "Edit",
            "Bash",
            "Glob",
            "Grep",
            "Task",
            "AskUserQuestion",
            "TodoWrite",
        ],
        permission_mode="acceptEdits",
        agents={
            "blueprint": blueprint_definition,
            "configure": configure_definition,
            "docs": docs_definition,
            "quality": quality_definition,
            "security": security_definition,
            "test_runner": test_runner_definition,
        },
        env={
            "CLAUDECODE": "",
            "DRY_RUN": str(dry_run),
            "SKIP_CI": str(skip_ci),
            "SKIP_BLUEPRINT": str(skip_blueprint),
            "ONBOARD_BRANCH": branch,
        },
        stderr=lambda line: console.print(f"[dim red]STDERR: {line}[/dim red]"),
    )

    # Build the prompt
    prompt_parts = [
        f"Onboard the repository at {repo_path}.",
        "Repository analysis and health score are in your system prompt. Plan and execute the onboarding workflow.",
    ]
    if dry_run:
        prompt_parts.append("DRY RUN — report what you would do without making changes.")
    if skip_ci:
        prompt_parts.append("Skip CI/CD setup.")
    if skip_blueprint:
        prompt_parts.append("Skip blueprint initialization.")

    prompt = " ".join(prompt_parts)

    # Stream and display messages
    await _stream_messages(prompt, options, "Onboarding complete.")


async def run_maintain(
    repo_path: Path,
    fix: bool = False,
    report_only: bool = False,
    focus: str | None = None,
) -> None:
    """Run the maintenance workflow for a repository."""
    console.print(f"[bold]Git Repo Agent[/bold] — Maintaining [cyan]{repo_path}[/cyan]")
    if report_only:
        console.print("[yellow]REPORT ONLY — no changes will be made[/yellow]")
    elif fix:
        console.print("[green]FIX MODE — will auto-fix safe issues[/green]")
    if focus:
        console.print(f"[dim]Focus areas: {focus}[/dim]")
    console.print()

    # Pre-compute analysis (see ADR-001)
    console.print("[dim]Analyzing repository...[/dim]")
    repo_context = _pre_compute_context(repo_path)

    # Build system prompt with embedded analysis
    system_prompt = (
        _load_prompt("orchestrator")
        + "\n\n"
        + _load_prompt("maintain")
        + "\n\n"
        + repo_context
    )

    # Build orchestrator options
    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        cwd=str(repo_path),
        max_turns=50,
        allowed_tools=[
            "Read",
            "Write",
            "Edit",
            "Bash",
            "Glob",
            "Grep",
            "Task",
            "AskUserQuestion",
            "TodoWrite",
        ],
        permission_mode="acceptEdits",
        agents={
            "blueprint": blueprint_definition,
            "configure": configure_definition,
            "docs": docs_definition,
            "quality": quality_definition,
            "security": security_definition,
            "test_runner": test_runner_definition,
        },
        env={
            "CLAUDECODE": "",
            "FIX_MODE": str(fix),
            "REPORT_ONLY": str(report_only),
            "FOCUS_AREAS": focus or "",
        },
    )

    # Build the prompt
    prompt_parts = [
        f"Run maintenance checks on the repository at {repo_path}.",
        "Repository analysis and health score are in your system prompt. Execute the maintenance workflow.",
    ]
    if report_only:
        prompt_parts.append("REPORT ONLY — do not make any changes, just generate a report.")
    elif fix:
        prompt_parts.append("FIX MODE — apply safe auto-fixes for issues found.")
    if focus:
        prompt_parts.append(f"Focus on these categories: {focus}")

    prompt = " ".join(prompt_parts)

    await _stream_messages(prompt, options, "Maintenance complete.")


def run_health(repo_path: Path) -> None:
    """Quick health check — no subagents, no LLM calls, just tools."""
    console.print(f"[bold]Git Repo Agent[/bold] — Health Check [cyan]{repo_path}[/cyan]")
    console.print()

    scores = compute_health_score(repo_path)
    report = generate_report(scores, "terminal")
    console.print(report)


async def _stream_messages(
    prompt: str,
    options: ClaudeAgentOptions,
    completion_msg: str,
) -> None:
    """Stream and display messages from a query."""
    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    console.print(block.text)
                elif isinstance(block, ToolUseBlock):
                    console.print(
                        f"[dim]Tool: {block.name}[/dim]",
                        highlight=False,
                    )
        elif isinstance(message, ResultMessage):
            if message.is_error:
                console.print(f"[red]Error: {message.result}[/red]")
            else:
                console.print()
                console.print(f"[bold green]{completion_msg}[/bold green]")
                if message.total_cost_usd:
                    console.print(
                        f"[dim]Cost: ${message.total_cost_usd:.4f}[/dim]"
                    )
        elif isinstance(message, SystemMessage):
            if message.subtype == "init":
                session_id = message.data.get("session_id", "")
                console.print(f"[dim]Session: {session_id}[/dim]")
