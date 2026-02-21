"""Orchestrator — core agent logic for git-repo-agent."""

from pathlib import Path

from claude_agent_sdk import (
    AgentDefinition,
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
from .tools.repo_analyzer import repo_analyze

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

    # Create custom MCP server with repo_analyze tool
    tools_server = create_sdk_mcp_server(
        name="repo-tools",
        version="1.0.0",
        tools=[repo_analyze],
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
        ],
        permission_mode="acceptEdits",
        mcp_servers={"repo-tools": tools_server},
        agents={
            "blueprint": blueprint_definition,
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
                console.print("[bold green]Onboarding complete.[/bold green]")
                if message.total_cost_usd:
                    console.print(
                        f"[dim]Cost: ${message.total_cost_usd:.4f}[/dim]"
                    )
        elif isinstance(message, SystemMessage):
            if message.subtype == "init":
                session_id = message.data.get("session_id", "")
                console.print(f"[dim]Session: {session_id}[/dim]")
