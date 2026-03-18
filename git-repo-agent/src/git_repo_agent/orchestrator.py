"""Orchestrator — core agent logic for git-repo-agent."""

import json
import logging
from datetime import date
from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ClaudeSDKClient,
    ResultMessage,
    SystemMessage,
    TextBlock,
    ToolUseBlock,
)
from rich.console import Console

logger = logging.getLogger(__name__)

# Patch SDK message parser to handle unknown message types gracefully.
# The SDK (0.1.39) raises MessageParseError for unrecognized types like
# "rate_limit_event", which crashes the async generator irrecoverably.
# Must patch both the module-level function AND the client's local binding,
# since client.py uses "from .message_parser import parse_message".
import claude_agent_sdk._internal.client as _sdk_client  # noqa: E402
import claude_agent_sdk._internal.message_parser as _msg_parser  # noqa: E402

_original_parse_message = _msg_parser.parse_message


def _resilient_parse_message(data):
    try:
        return _original_parse_message(data)
    except Exception as exc:
        if "Unknown message type" in str(exc):
            msg_type = data.get("type", "unknown") if isinstance(data, dict) else "unknown"
            logger.debug("Skipping unrecognized message type: %s", msg_type)
            return SystemMessage(subtype=msg_type, data=data if isinstance(data, dict) else {})
        raise


_msg_parser.parse_message = _resilient_parse_message
_sdk_client.parse_message = _resilient_parse_message

from .agents.blueprint import definition as blueprint_definition
from .agents.configure import definition as configure_definition
from .agents.diagnose import definition as diagnose_definition
from .agents.docs import definition as docs_definition
from .agents.quality import definition as quality_definition
from .agents.security import definition as security_definition
from .agents.test_runner import definition as test_runner_definition
from .tools.attributes import (
    collect_attributes,
    format_routing_instructions,
    route_from_attributes,
)
from .tools.health_check import compute_health_score
from .tools.pipeline_collector import collect_pipeline_diagnostics
from .tools.repo_analyzer import analyze_repo
from .tools.report import generate_report
from .worktree import (
    cleanup_worktree,
    create_github_issues,
    create_worktree,
    get_base_branch,
    parse_report_only_findings,
    push_and_create_pr,
    worktree_has_changes,
)

console = Console()

_PROMPTS_DIR = Path(__file__).parent / "prompts"


def _load_prompt(name: str) -> str:
    """Load a prompt file from the prompts directory."""
    return (_PROMPTS_DIR / f"{name}.md").read_text(encoding="utf-8")


def _pre_compute_context(repo_path: Path) -> str:
    """Pre-compute repository analysis, health score, and structured attributes.

    Returns a formatted string to embed in the agent prompt.
    See ADR-001 for why this replaces SDK MCP servers.
    """
    analysis = analyze_repo(repo_path)
    health = compute_health_score(repo_path)
    attr_data = collect_attributes(repo_path)

    # Compute routing priorities from attributes
    priorities = route_from_attributes(attr_data["attributes"])
    routing = format_routing_instructions(priorities)

    return (
        "## Pre-computed Repository Analysis\n\n"
        "The following data was computed before this session started. "
        "Use it to plan your work — no need to re-analyze.\n\n"
        "### repo_analyze result\n\n"
        f"```json\n{json.dumps(analysis, indent=2)}\n```\n\n"
        "### health_score result\n\n"
        f"```json\n{json.dumps(health, indent=2)}\n```\n\n"
        "### codebase_attributes result\n\n"
        f"```json\n{json.dumps(attr_data, indent=2)}\n```\n\n"
        f"{routing}\n"
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

    # Create worktree for isolated work (see ADR-004)
    base_branch = get_base_branch(repo_path)
    worktree_path = None
    work_dir = repo_path

    if not dry_run:
        console.print(f"[dim]Creating worktree on branch {branch}...[/dim]")
        worktree_path = create_worktree(repo_path, branch)
        work_dir = worktree_path
        console.print(f"[dim]Working in: {worktree_path}[/dim]")

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
        cwd=str(work_dir),
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

    # Build the prompt — agent should commit but NOT create branches (worktree handles that)
    prompt_parts = [
        f"Onboard the repository at {work_dir}.",
        "Repository analysis and health score are in your system prompt. Plan and execute the onboarding workflow.",
        f"You are working in a git worktree on branch '{branch}'.",
        "Commit your changes directly to this branch. Do NOT create new branches.",
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

    # Post-workflow: offer to create PR if worktree has changes
    if worktree_path and not dry_run:
        await _prompt_pr_creation(
            repo_path, worktree_path, branch, base_branch, "onboard"
        )


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

    # Interactive mode does not use AskUserQuestion — the orchestrator
    # handles user prompting in Python between two agent phases. See ADR-003.
    interactive = not fix and not report_only
    makes_changes = not report_only

    # Create worktree for isolated work when changes will be made (see ADR-004)
    base_branch = get_base_branch(repo_path)
    worktree_path = None
    work_dir = repo_path
    branch = f"maintain/{date.today().isoformat()}"

    if makes_changes:
        console.print(f"[dim]Creating worktree on branch {branch}...[/dim]")
        worktree_path = create_worktree(repo_path, branch)
        work_dir = worktree_path
        console.print(f"[dim]Working in: {worktree_path}[/dim]")

    # Build orchestrator options
    allowed_tools = [
        "Read",
        "Write",
        "Edit",
        "Bash",
        "Glob",
        "Grep",
        "Task",
        "TodoWrite",
    ]
    if not interactive:
        allowed_tools.append("AskUserQuestion")

    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        cwd=str(work_dir),
        max_turns=50,
        allowed_tools=allowed_tools,
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
        f"Run maintenance checks on the repository at {work_dir}.",
        "Repository analysis and health score are in your system prompt. Execute the maintenance workflow.",
    ]
    if report_only:
        prompt_parts.append("REPORT ONLY — do not make any changes, just generate a report.")
    elif fix:
        prompt_parts.append("FIX MODE — apply safe auto-fixes for issues found.")
        prompt_parts.append(
            f"You are working in a git worktree on branch '{branch}'. "
            "Commit your changes directly to this branch. Do NOT create new branches."
        )
    if focus:
        prompt_parts.append(f"Focus on these categories: {focus}")

    prompt = " ".join(prompt_parts)

    if interactive:
        collected = await _stream_interactive(
            prompt, options, "Maintenance complete.",
            worktree_branch=branch,
        )
    elif report_only:
        collected = await _stream_messages_collecting(
            prompt, options, "Maintenance complete.",
        )
    else:
        await _stream_messages(prompt, options, "Maintenance complete.")
        collected = ""

    # Post-workflow: offer to create PR if worktree has changes
    if worktree_path and makes_changes:
        await _prompt_pr_creation(
            repo_path, worktree_path, branch, base_branch, "maintain",
            agent_output=collected,
        )

    # Post-workflow: offer to create GitHub issues for report-only findings
    if report_only and collected:
        await _prompt_issue_creation(repo_path, collected)


async def run_diagnose(
    repo_path: Path,
    sources: str | None = None,
    create_issue: bool = False,
    dry_run: bool = False,
    namespace: str | None = None,
    app_name: str | None = None,
) -> None:
    """Run the pipeline diagnostics workflow for a repository."""
    console.print(f"[bold]Git Repo Agent[/bold] — Diagnosing [cyan]{repo_path}[/cyan]")
    if dry_run:
        console.print("[yellow]DRY RUN — diagnostics only, no issues created[/yellow]")
    if create_issue and not dry_run:
        console.print("[green]Will create GitHub issue with findings[/green]")
    if sources:
        console.print(f"[dim]Sources: {sources}[/dim]")
    console.print()

    # Pre-compute analysis and pipeline diagnostics (see ADR-001)
    console.print("[dim]Analyzing repository...[/dim]")
    analysis = analyze_repo(repo_path)

    console.print("[dim]Collecting pipeline diagnostics...[/dim]")
    source_list = [s.strip() for s in sources.split(",")] if sources else None
    diagnostics = collect_pipeline_diagnostics(
        repo_path,
        sources=source_list,
        namespace=namespace,
        app_name=app_name,
    )

    # Report available/unavailable sources
    available = diagnostics.get("available_sources", [])
    if available:
        console.print(f"[dim]Available sources: {', '.join(available)}[/dim]")
    else:
        console.print("[yellow]No CLI diagnostic sources detected[/yellow]")

    # Build pre-computed context
    context = (
        "## Pre-computed Repository Analysis\n\n"
        "The following data was computed before this session started.\n\n"
        "### repo_analyze result\n\n"
        f"```json\n{json.dumps(analysis, indent=2)}\n```\n\n"
        "## Pre-computed Pipeline Diagnostics\n\n"
        f"```json\n{json.dumps(diagnostics, indent=2)}\n```\n"
    )

    # Build system prompt with embedded analysis and diagnostics
    system_prompt = (
        _load_prompt("orchestrator")
        + "\n\n"
        + _load_prompt("diagnose_workflow")
        + "\n\n"
        + context
    )

    # Include GitHub MCP tools for issue creation
    allowed_tools = [
        "Read",
        "Bash",
        "Glob",
        "Grep",
        "Task",
        "AskUserQuestion",
        "TodoWrite",
        "mcp__github__issue_write",
        "mcp__github__issue_read",
        "mcp__github__list_issues",
        "mcp__github__search_issues",
    ]

    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        cwd=str(repo_path),
        max_turns=30,
        allowed_tools=allowed_tools,
        permission_mode="acceptEdits",
        agents={
            "diagnose": diagnose_definition,
        },
        env={
            "CLAUDECODE": "",
            "CREATE_ISSUE": str(create_issue),
            "DRY_RUN": str(dry_run),
            "DIAGNOSTIC_SOURCES": sources or "auto",
            "K8S_NAMESPACE": namespace or "",
            "ARGOCD_APP": app_name or "",
        },
    )

    # Build the prompt
    prompt_parts = [
        f"Run pipeline diagnostics for the repository at {repo_path}.",
        "Pipeline diagnostic data is in your system prompt.",
    ]
    if create_issue and not dry_run:
        prompt_parts.append(
            "Create a GitHub issue with the aggregated diagnostic findings."
        )
    if dry_run:
        prompt_parts.append(
            "DRY RUN — display diagnostics without creating issues."
        )

    prompt = " ".join(prompt_parts)

    await _stream_messages(prompt, options, "Diagnostics complete.")


def run_health(repo_path: Path) -> None:
    """Quick health check — no subagents, no LLM calls, just tools."""
    console.print(f"[bold]Git Repo Agent[/bold] — Health Check [cyan]{repo_path}[/cyan]")
    console.print()

    scores = compute_health_score(repo_path)
    report = generate_report(scores, "terminal")
    console.print(report)


def _tool_detail(name: str, inputs: dict) -> str:
    """Extract a short human-readable detail from a tool call's inputs."""
    if name == "Bash":
        cmd = inputs.get("command", "")
        if len(cmd) > 120:
            cmd = cmd[:117] + "..."
        return cmd
    if name == "Read":
        return inputs.get("file_path", "")
    if name in ("Edit", "Write"):
        return inputs.get("file_path", "")
    if name == "Glob":
        return inputs.get("pattern", "")
    if name == "Grep":
        pattern = inputs.get("pattern", "")
        path = inputs.get("path", "")
        if path:
            return f"{pattern} in {path}"
        return pattern
    if name == "Agent":
        return inputs.get("description", "")
    if name == "TodoWrite":
        return ""
    # Generic: show first string value if short enough
    for v in inputs.values():
        if isinstance(v, str) and 0 < len(v) <= 80:
            return v
    return ""


def _display_message(
    message: AssistantMessage | ResultMessage | SystemMessage,
    completion_msg: str | None = None,
    collected: list[str] | None = None,
) -> None:
    """Display a streamed SDK message to the console.

    If collected is provided, appends text content to the list for
    later processing (e.g., parsing report-only findings).
    """
    if isinstance(message, AssistantMessage):
        for block in message.content:
            if isinstance(block, TextBlock):
                console.print(block.text)
                if collected is not None:
                    collected.append(block.text)
            elif isinstance(block, ToolUseBlock):
                detail = _tool_detail(block.name, block.input)
                if detail:
                    console.print(
                        f"[dim]Tool: {block.name} → {detail}[/dim]",
                        highlight=False,
                    )
                else:
                    console.print(
                        f"[dim]Tool: {block.name}[/dim]",
                        highlight=False,
                    )
    elif isinstance(message, ResultMessage):
        if message.is_error:
            console.print(f"[red]Error: {message.result}[/red]")
        elif completion_msg:
            console.print()
            console.print(f"[bold green]{completion_msg}[/bold green]")
        if message.total_cost_usd:
            console.print(f"[dim]Cost: ${message.total_cost_usd:.4f}[/dim]")
    elif isinstance(message, SystemMessage):
        if message.subtype == "init":
            session_id = message.data.get("session_id", "")
            console.print(f"[dim]Session: {session_id}[/dim]")


async def _stream_messages(
    prompt: str,
    options: ClaudeAgentOptions,
    completion_msg: str,
) -> None:
    """Run a single-phase session using ClaudeSDKClient.

    See ADR-003 for why ClaudeSDKClient is used instead of query().
    """
    async with ClaudeSDKClient(options) as client:
        await client.query(prompt)

        async for message in client.receive_response():
            _display_message(message, completion_msg)


async def _stream_messages_collecting(
    prompt: str,
    options: ClaudeAgentOptions,
    completion_msg: str,
) -> str:
    """Like _stream_messages but also collects agent text output.

    Returns the concatenated text output for post-processing.
    """
    collected: list[str] = []
    async with ClaudeSDKClient(options) as client:
        await client.query(prompt)

        async for message in client.receive_response():
            _display_message(message, completion_msg, collected)

    return "\n".join(collected)


async def _stream_interactive(
    prompt: str,
    options: ClaudeAgentOptions,
    completion_msg: str,
    worktree_branch: str | None = None,
) -> str:
    """Run a two-phase interactive session using ClaudeSDKClient.

    Phase 1: Agent analyzes and presents numbered findings, then stops.
    Interlude: Python prompts the user for their selections via rich.
    Phase 2: Agent executes the selected fixes and generates a report.

    This replaces AskUserQuestion which does not work in SDK subprocess
    mode. See ADR-003.

    Returns concatenated agent text output for post-processing.
    """
    collected: list[str] = []
    async with ClaudeSDKClient(options) as client:
        # Phase 1: Analysis — agent presents findings and stops
        await client.query(prompt)

        async for message in client.receive_response():
            _display_message(message, collected=collected)

        # Prompt user for selections
        console.print()
        user_input = console.input(
            "[bold]Select fixes to apply[/bold] "
            "(comma-separated numbers, [green]all[/green], or [yellow]none[/yellow]): "
        )

        choice = user_input.strip().lower()
        if choice in ("none", "n", ""):
            console.print("[yellow]No fixes selected.[/yellow]")
            followup = (
                "The user chose not to apply any fixes. "
                "Skip Step 4. Proceed to Step 5 (record health history) "
                "and Step 6 (generate report)."
            )
        else:
            worktree_note = ""
            if worktree_branch:
                worktree_note = (
                    f" You are working in a git worktree on branch '{worktree_branch}'. "
                    "Commit your changes directly to this branch. Do NOT create new branches."
                )
            followup = (
                f"The user selected: {user_input}. "
                "Execute the selected fixes (Step 4), then record health "
                f"history (Step 5) and generate the maintenance report (Step 6).{worktree_note}"
            )

        # Phase 2: Execution
        await client.query(followup)

        async for message in client.receive_response():
            _display_message(message, completion_msg, collected)

    return "\n".join(collected)


def _extract_report_section(agent_output: str) -> str:
    """Extract the maintenance report from agent output.

    Looks for markdown report sections (## headers and content) in the
    collected agent output. Returns the report text, or empty string.
    """
    if not agent_output:
        return ""

    lines = agent_output.splitlines()
    report_lines: list[str] = []
    capturing = False

    for line in lines:
        # Start capturing at report-like headings
        if line.startswith("## ") or line.startswith("# Maintenance") or line.startswith("# Health"):
            capturing = True
        if capturing:
            report_lines.append(line)

    return "\n".join(report_lines).strip()


def _build_pr_content(workflow: str, agent_output: str) -> tuple[str, str]:
    """Build PR title and body from workflow type and agent output.

    Returns (title, body) tuple.
    """
    report = _extract_report_section(agent_output)

    # Build a descriptive title from the report if possible
    pr_title = f"chore: {workflow} repository"

    if report:
        pr_body = (
            f"## Maintenance Report\n\n"
            f"{report}\n\n"
            f"---\n\n"
            f"## Test plan\n\n"
            f"- [ ] Review changes in the diff\n"
            f"- [ ] Verify CI passes\n\n"
            f"\U0001f916 Generated with git-repo-agent"
        )
    else:
        pr_body = (
            f"## Summary\n\n"
            f"- Automated {workflow} via git-repo-agent\n\n"
            f"## Test plan\n\n"
            f"- [ ] Review changes in the diff\n"
            f"- [ ] Verify CI passes\n\n"
            f"\U0001f916 Generated with git-repo-agent"
        )

    return pr_title, pr_body


async def _prompt_pr_creation(
    repo_path: Path,
    worktree_path: Path,
    branch: str,
    base_branch: str,
    workflow: str,
    agent_output: str = "",
) -> None:
    """Check for changes in the worktree and offer to create a PR."""
    if not worktree_has_changes(worktree_path, base_branch):
        console.print("[dim]No changes were made in the worktree.[/dim]")
        cleanup_worktree(repo_path, worktree_path)
        return

    console.print()
    console.print(f"[bold]Changes committed on branch [cyan]{branch}[/cyan][/bold]")
    create_pr = console.input(
        "[bold]Create a pull request?[/bold] ([green]yes[/green]/[yellow]no[/yellow]): "
    ).strip().lower()

    if create_pr in ("yes", "y"):
        pr_title, pr_body = _build_pr_content(workflow, agent_output)
        console.print("[dim]Pushing branch and creating PR...[/dim]")
        pr_url = push_and_create_pr(
            worktree_path, branch, base_branch, pr_title, pr_body,
        )
        if pr_url:
            console.print(f"[bold green]PR created:[/bold green] {pr_url}")
        else:
            console.print("[red]Failed to create PR. Push branch manually:[/red]")
            console.print(f"  cd {worktree_path} && git push -u origin {branch}")
    else:
        console.print(
            f"[dim]Worktree preserved at: {worktree_path}[/dim]\n"
            f"[dim]Branch: {branch}[/dim]\n"
            f"[dim]To create a PR later: cd {worktree_path} && git push -u origin {branch} && gh pr create[/dim]"
        )


async def _prompt_issue_creation(
    repo_path: Path,
    agent_output: str,
) -> None:
    """Parse report-only findings and offer to create GitHub issues."""
    findings = parse_report_only_findings(agent_output)

    if not findings:
        return

    console.print()
    console.print(
        f"[bold]Found {len(findings)} report-only finding(s)[/bold] "
        "that could be tracked as GitHub issues:"
    )
    for i, f in enumerate(findings, 1):
        console.print(f"  {i}. {f['title']}")

    create_issues = console.input(
        "\n[bold]Create GitHub issues?[/bold] "
        "([green]all[/green], comma-separated numbers, or [yellow]none[/yellow]): "
    ).strip().lower()

    if create_issues in ("none", "n", ""):
        console.print("[yellow]No issues created.[/yellow]")
        return

    if create_issues in ("all", "a"):
        selected = findings
    else:
        indices = []
        for part in create_issues.split(","):
            part = part.strip()
            if part.isdigit():
                idx = int(part) - 1
                if 0 <= idx < len(findings):
                    indices.append(idx)
        selected = [findings[i] for i in indices]

    if not selected:
        console.print("[yellow]No valid selections.[/yellow]")
        return

    console.print(f"[dim]Creating {len(selected)} GitHub issue(s)...[/dim]")
    urls = create_github_issues(repo_path, selected)

    for url in urls:
        console.print(f"  [green]Created:[/green] {url}")

    if len(urls) < len(selected):
        console.print(
            f"[yellow]{len(selected) - len(urls)} issue(s) failed to create.[/yellow]"
        )
