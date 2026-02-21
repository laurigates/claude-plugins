"""Orchestrator — core agent logic for git-repo-agent."""

from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    SystemMessage,
    TextBlock,
    ToolUseBlock,
    create_sdk_mcp_server,
    query,
)
from rich.console import Console

from .agents.blueprint import definition as blueprint_definition
from .agents.configure import definition as configure_definition
from .agents.docs import definition as docs_definition
from .agents.quality import definition as quality_definition
from .agents.security import definition as security_definition
from .agents.test_runner import definition as test_runner_definition
from .tools.health_check import compute_health_score, health_score
from .tools.repo_analyzer import repo_analyze
from .tools.report import generate_report, report_generate

console = Console()

_PROMPTS_DIR = Path(__file__).parent / "prompts"


def _load_prompt(name: str) -> str:
    """Load a prompt file from the prompts directory."""
    return (_PROMPTS_DIR / f"{name}.md").read_text(encoding="utf-8")


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

    # Create custom MCP server with tools
    tools_server = create_sdk_mcp_server(
        name="repo-tools",
        version="1.0.0",
        tools=[repo_analyze, health_score, report_generate],
    )

    # Build system prompt
    system_prompt = _load_prompt("orchestrator") + "\n\n" + _load_prompt("onboard")

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
            "mcp__repo-tools__repo_analyze",
            "mcp__repo-tools__health_score",
            "mcp__repo-tools__report_generate",
        ],
        permission_mode="acceptEdits",
        mcp_servers={"repo-tools": tools_server},
        agents={
            "blueprint": blueprint_definition,
            "configure": configure_definition,
            "docs": docs_definition,
            "quality": quality_definition,
            "security": security_definition,
            "test_runner": test_runner_definition,
        },
        env={
            "DRY_RUN": str(dry_run),
            "SKIP_CI": str(skip_ci),
            "SKIP_BLUEPRINT": str(skip_blueprint),
            "ONBOARD_BRANCH": branch,
        },
    )

    # Build the prompt
    prompt_parts = [
        f"Onboard the repository at {repo_path}.",
        "Start by analyzing the repo with repo_analyze, then plan and execute the onboarding workflow.",
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

    # Create custom MCP server with tools
    tools_server = create_sdk_mcp_server(
        name="repo-tools",
        version="1.0.0",
        tools=[repo_analyze, health_score, report_generate],
    )

    # Build system prompt
    system_prompt = _load_prompt("orchestrator") + "\n\n" + _load_prompt("maintain")

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
            "mcp__repo-tools__repo_analyze",
            "mcp__repo-tools__health_score",
            "mcp__repo-tools__report_generate",
        ],
        permission_mode="acceptEdits",
        mcp_servers={"repo-tools": tools_server},
        agents={
            "blueprint": blueprint_definition,
            "configure": configure_definition,
            "docs": docs_definition,
            "quality": quality_definition,
            "security": security_definition,
            "test_runner": test_runner_definition,
        },
        env={
            "FIX_MODE": str(fix),
            "REPORT_ONLY": str(report_only),
            "FOCUS_AREAS": focus or "",
        },
    )

    # Build the prompt
    prompt_parts = [
        f"Run maintenance checks on the repository at {repo_path}.",
        "Start by analyzing the repo with repo_analyze and health_score, then execute the maintenance workflow.",
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
