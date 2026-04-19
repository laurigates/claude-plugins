"""Orchestrator — wires pre-computed audit + worktree + SDK session.

The pure-Python deterministic modes (see ``fixers/``) bypass the LLM
entirely and call ``apply_deterministic_fixes`` on a worktree. When a mode
has judgment work (stubs content merge, MOC proposals, link
re-writing with guessed canonical targets), ``run_mode_with_sdk`` opens a
``ClaudeSDKClient`` session, registers the subagent definitions from
``agents/__init__.py``, wires the safety hook as a ``PreToolUse``
validator, and streams messages to the console.

Two SDK-level monkeypatches are applied at import time:

  * ``parse_message`` — the SDK raises ``MessageParseError`` for unknown
    message types (e.g. ``rate_limit_event`` in 0.1.39). We convert those
    to ``SystemMessage`` so the async generator keeps going.

  * ``SubprocessCLITransport._read_messages_impl`` — suppresses the
    SIGTERM-on-close exit-code-15 ``ProcessError`` that otherwise lands
    in a GC'd async-generator finalizer with no one awaiting it.
"""

from __future__ import annotations

import json
import logging
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional

from vault_agent.analyzers.audit import VaultAudit, run_audit
from vault_agent.worktree import (
    WorktreeHandle,
    cleanup_worktree,
    create_worktree,
    format_review_instructions,
    timestamped_branch,
    worktree_file_change_count,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# SDK monkeypatches (imported lazily so tests that don't invoke the SDK
# don't require the patched module to be present).
# ---------------------------------------------------------------------------


_SDK_PATCHED = False


def _patch_sdk_once() -> None:
    """Apply the two resilience patches to the Claude Agent SDK.

    Idempotent — safe to call repeatedly. Called from ``run_mode_with_sdk``
    before opening a session so tests that never touch the SDK pay zero
    import cost.
    """
    global _SDK_PATCHED
    if _SDK_PATCHED:
        return

    import claude_agent_sdk._internal.client as _sdk_client
    import claude_agent_sdk._internal.message_parser as _msg_parser
    import claude_agent_sdk._internal.transport.subprocess_cli as _sdk_subprocess
    from claude_agent_sdk import SystemMessage

    _original_parse_message = _msg_parser.parse_message

    def _resilient_parse_message(data):
        try:
            return _original_parse_message(data)
        except Exception as exc:
            if "Unknown message type" in str(exc):
                msg_type = (
                    data.get("type", "unknown") if isinstance(data, dict) else "unknown"
                )
                logger.debug("Skipping unrecognized SDK message type: %s", msg_type)
                return SystemMessage(
                    subtype=msg_type, data=data if isinstance(data, dict) else {}
                )
            raise

    _msg_parser.parse_message = _resilient_parse_message
    _sdk_client.parse_message = _resilient_parse_message

    _original_read_messages_impl = (
        _sdk_subprocess.SubprocessCLITransport._read_messages_impl
    )

    async def _quiet_read_messages_impl(self):
        try:
            async for data in _original_read_messages_impl(self):
                yield data
        except Exception as exc:
            exit_code = getattr(exc, "exit_code", None)
            if exit_code == -15:
                logger.debug("Suppressing SIGTERM-on-close ProcessError: %s", exc)
                return
            raise

    _sdk_subprocess.SubprocessCLITransport._read_messages_impl = (
        _quiet_read_messages_impl
    )

    _SDK_PATCHED = True


# ---------------------------------------------------------------------------
# Result shape
# ---------------------------------------------------------------------------


@dataclass
class OrchestratorResult:
    """What happened in a run."""

    mode: str
    dry_run: bool
    audit: VaultAudit
    handle: WorktreeHandle | None  # None in dry-run
    commits_made: int
    files_changed: int
    summary: str
    report_section: str = ""  # LLM-emitted ## Run summary block, if any


# ---------------------------------------------------------------------------
# System-prompt assembly
# ---------------------------------------------------------------------------


def build_system_prompt(mode: str, audit: VaultAudit) -> str:
    """Combine the orchestrator prompt + mode prompt + compiled skills + audit.

    The audit is embedded as a fenced JSON block so the LLM can reference
    it without another tool call (ADR-001 pre-compute pattern).
    """
    prompts_dir = Path(__file__).parent / "prompts"
    base = (prompts_dir / "orchestrator.md").read_text(encoding="utf-8")

    mode_file = prompts_dir / f"{mode.replace('-', '_')}.md"
    if mode_file.exists():
        base += "\n\n---\n\n" + mode_file.read_text(encoding="utf-8")

    compact = _compact_audit_for_prompt(audit)
    base += "\n\n---\n\n## Pre-computed audit\n\n```json\n"
    base += json.dumps(compact, indent=2, default=str)
    base += "\n```\n"
    return base


def _compact_audit_for_prompt(audit: VaultAudit, sample: int = 30) -> dict:
    """Shrink the full audit dict down to something that fits in a prompt.

    Keeps counts and the first ``sample`` items in each list so the LLM
    sees concrete examples without the whole vault's path list.
    """
    full = audit.to_dict()

    def trim(obj):
        if isinstance(obj, list):
            if len(obj) > sample:
                return obj[:sample] + [f"... (+{len(obj) - sample} more)"]
            return obj
        if isinstance(obj, dict):
            return {k: trim(v) for k, v in obj.items()}
        return obj

    return trim(full)


# ---------------------------------------------------------------------------
# Worktree helpers
# ---------------------------------------------------------------------------


def enter_worktree(vault: Path, *, prefix: str = "vault-agent") -> WorktreeHandle:
    """Create a fresh worktree for a write run."""
    branch = timestamped_branch(prefix)
    return create_worktree(vault, branch)


def commit_all(
    handle: WorktreeHandle, message: str, *, paths: list[Path] | None = None
) -> bool:
    """Stage and commit. Returns True if a commit was made."""
    if paths:
        rels = [str(p.relative_to(handle.worktree_path)) for p in paths]
        subprocess.run(
            ["git", "add", "--", *rels], cwd=handle.worktree_path, check=True
        )
    else:
        subprocess.run(["git", "add", "-A"], cwd=handle.worktree_path, check=True)

    status = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=handle.worktree_path,
        capture_output=True,
        text=True,
    )
    if not status.stdout.strip():
        return False

    subprocess.run(
        ["git", "commit", "-m", message],
        cwd=handle.worktree_path,
        check=True,
        capture_output=True,
    )
    return True


def finalize_run(
    handle: WorktreeHandle,
    *,
    commits_made: int,
    mode: str,
    audit: VaultAudit,
    summary: str,
    report_section: str = "",
) -> OrchestratorResult:
    """Compose a result object + the review-commands banner."""
    files_changed = worktree_file_change_count(handle)
    return OrchestratorResult(
        mode=mode,
        dry_run=False,
        audit=audit,
        handle=handle,
        commits_made=commits_made,
        files_changed=files_changed,
        summary=summary,
        report_section=report_section,
    )


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------


def preflight(vault: Path) -> VaultAudit:
    """Run the pure-Python audit. Shared by every mode."""
    return run_audit(vault)


def render_banner(result: OrchestratorResult) -> str:
    """Banner shown at the end of a write run."""
    if result.handle is None:
        return f"(dry-run) no changes. Audit: health={result.audit.health.total}/100"
    lines = [format_review_instructions(result.handle), "", result.summary]
    if result.report_section:
        lines.extend(["", result.report_section])
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Message display helpers (SDK mode)
# ---------------------------------------------------------------------------


def _tool_detail(name: str, inputs: dict) -> str:
    """Extract a short human-readable detail from a tool call's inputs."""
    if name == "Bash":
        cmd = inputs.get("command", "")
        if len(cmd) > 120:
            cmd = cmd[:117] + "..."
        return cmd
    if name in ("Read", "Edit", "Write"):
        return inputs.get("file_path", "")
    if name == "Glob":
        return inputs.get("pattern", "")
    if name == "Grep":
        pattern = inputs.get("pattern", "")
        path = inputs.get("path", "")
        return f"{pattern} in {path}" if path else pattern
    if name in ("Task", "Agent"):
        return inputs.get("description", "")
    if name == "TodoWrite":
        return ""
    for v in inputs.values():
        if isinstance(v, str) and 0 < len(v) <= 80:
            return v
    return ""


def _display_message(
    message: Any,
    console,
    collected: list[str] | None = None,
    completion_msg: Optional[str] = None,
) -> None:
    """Render a streamed SDK message to the console.

    Imports SDK types lazily so this module still imports cleanly when the
    SDK is missing (tests and pure-Python paths).
    """
    from claude_agent_sdk import (
        AssistantMessage,
        ResultMessage,
        SystemMessage,
        TextBlock,
        ToolUseBlock,
    )

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
                        f"[dim]Tool: {block.name} → {detail}[/dim]", highlight=False
                    )
                else:
                    console.print(f"[dim]Tool: {block.name}[/dim]", highlight=False)
    elif isinstance(message, ResultMessage):
        if message.is_error:
            console.print(f"[red]Error: {message.result}[/red]")
        elif completion_msg:
            console.print(f"[bold green]{completion_msg}[/bold green]")
        if getattr(message, "total_cost_usd", None):
            console.print(f"[dim]Cost: ${message.total_cost_usd:.4f}[/dim]")
    elif isinstance(message, SystemMessage):
        if message.subtype == "init":
            session_id = message.data.get("session_id", "") if hasattr(message, "data") else ""
            if session_id:
                console.print(f"[dim]Session: {session_id}[/dim]")


def _extract_report_section(collected: list[str]) -> str:
    """Find the ``## Run summary`` block the orchestrator prompts the LLM to emit.

    Returns the full block (from ``## Run summary`` to end-of-text or next
    top-level heading), or the empty string if the LLM never emitted one.
    """
    text = "\n".join(collected)
    marker = "## Run summary"
    idx = text.find(marker)
    if idx < 0:
        return ""
    tail = text[idx:]
    # Stop at the next top-level heading (== not ###).
    lines = tail.splitlines()
    out: list[str] = []
    for i, line in enumerate(lines):
        if i > 0 and line.startswith("## ") and not line.startswith("## Run summary"):
            break
        out.append(line)
    return "\n".join(out).strip()


# ---------------------------------------------------------------------------
# SDK session loop
# ---------------------------------------------------------------------------


def _build_safety_hook_callback():
    """Wrap ``hooks.safety.validate_tool_use`` as an SDK-compatible callback.

    The SDK hook signature is ``(input_dict, tool_use_id, context) -> awaitable``;
    our validator is sync and takes ``(tool_name, tool_input)``. Adapt here
    and translate blocks to the PreToolUse ``permissionDecision`` schema.
    """
    from vault_agent.hooks.safety import validate_tool_use
    from vault_agent.non_interactive import HookBlockedError

    async def _callback(input_data: dict, _tool_use_id, _context) -> dict:
        tool_name = input_data.get("tool_name", "") or ""
        tool_input = input_data.get("tool_input", {}) or {}
        decision = validate_tool_use(tool_name, tool_input)
        if decision.allow:
            return {}
        # Per SDK: block + reason so the agent sees a tool error and
        # the caller can inspect the transcript. Raise on critical blocks
        # so _run_write_mode maps to EXIT_HOOK_BLOCKED.
        raise HookBlockedError(
            f"safety hook refused {tool_name}: {decision.reason}"
        )

    return _callback


def _has_sdk_work(mode: str, audit: VaultAudit) -> bool:
    """True when ``mode`` has judgment work the deterministic path can't handle."""
    if mode == "stubs":
        return any(
            c.cls.value == "stale_duplicate" for c in audit.stubs.classifications
        )
    if mode == "mocs":
        # mocs has SDK work if there are missing-MOC candidates OR any
        # existing MOC has orphans. The deterministic path covers neither.
        if audit.mocs.missing_moc_candidates:
            return True
        return any(
            cov.unlinked_note_count > 0 for cov in audit.mocs.coverage_by_category
        )
    if mode == "links":
        # Only the "low-leverage" targets that the rule table doesn't cover
        # need the LLM. Handled by #1073.
        from vault_agent.fixers.link_patcher import BROKEN_LINK_REWRITES

        rule_table = set(BROKEN_LINK_REWRITES.keys())
        top_broken = {t for t, _ in audit.links.top_broken(20) if t not in rule_table}
        return len(top_broken) >= 3  # threshold: 3+ refs per #1073
    if mode == "lint":
        return False  # pure deterministic
    if mode == "maintain":
        return (
            _has_sdk_work("stubs", audit)
            or _has_sdk_work("mocs", audit)
            or _has_sdk_work("links", audit)
        )
    return False


async def run_mode_with_sdk(
    vault: Path,
    mode: str,
    *,
    apply: bool,
    handle: Optional[WorktreeHandle] = None,
    max_cost_usd: Optional[float] = None,
    console=None,
) -> OrchestratorResult:
    """Open a ``ClaudeSDKClient`` session for the subagent-backed portion of ``mode``.

    Caller is responsible for acquiring the lock and creating the worktree
    first. When ``handle is None`` this function creates one. The pure-Python
    deterministic fixes must run *before* this so the LLM sees an audit that
    reflects the already-fixed state.

    Returns an ``OrchestratorResult`` with the handle (so the caller can print
    the review/merge banner). Raises ``HookBlockedError`` if the safety hook
    rejects a critical operation.
    """
    _patch_sdk_once()

    from claude_agent_sdk import (
        ClaudeAgentOptions,
        ClaudeSDKClient,
        HookMatcher,
    )
    from rich.console import Console

    from vault_agent.agents import ALL_DEFINITIONS

    if console is None:
        console = Console()

    vault = Path(vault).expanduser().resolve()
    audit = preflight(vault)

    own_worktree = handle is None
    if apply and handle is None:
        handle = enter_worktree(vault)
    work_dir = handle.worktree_path if handle is not None else vault

    system_prompt = build_system_prompt(mode, audit)

    allowed_tools = [
        "Read", "Write", "Edit", "Bash", "Glob", "Grep", "TodoWrite", "Task",
    ]

    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        cwd=str(work_dir),
        max_turns=60,
        allowed_tools=allowed_tools,
        permission_mode="acceptEdits",
        agents={name: defn for name, defn in ALL_DEFINITIONS.items() if defn is not None},
        hooks={
            "PreToolUse": [
                HookMatcher(
                    matcher="Write|Edit|NotebookEdit|Bash",
                    hooks=[_build_safety_hook_callback()],
                )
            ]
        },
        env={
            "VAULT_AGENT_MODE": mode,
            "VAULT_AGENT_WORKTREE": str(work_dir),
            "VAULT_AGENT_BRANCH": handle.branch if handle is not None else "",
            "VAULT_AGENT_DRY_RUN": str(not apply),
        },
        stderr=lambda line: console.print(f"[dim red]STDERR: {line}[/dim red]"),
    )

    prompt = (
        f"Run the `{mode}` maintenance mode against the vault at {work_dir}. "
        "The pre-computed audit is in your system prompt. "
        "Delegate to the appropriate subagent via the Task tool. "
        f"You are working in a git worktree on branch '{handle.branch if handle else '(no worktree)'}'. "
        "Commit each fix category with a conventional-commit message. "
        "Do NOT create new branches, do NOT push. "
        "Emit a final `## Run summary` block with the commits made, files changed, "
        "and remaining issues for manual follow-up."
    )
    if not apply:
        prompt += " DRY RUN — report the plan without writing any file."

    collected: list[str] = []
    completion_msg = f"{mode} mode complete."

    async with ClaudeSDKClient(options) as client:
        await client.query(prompt)
        async for message in client.receive_response():
            _display_message(message, console, collected, completion_msg)

    report_section = _extract_report_section(collected)
    summary = f"mode={mode} branch={handle.branch if handle else '-'}"

    if handle is None:
        return OrchestratorResult(
            mode=mode,
            dry_run=not apply,
            audit=audit,
            handle=None,
            commits_made=0,
            files_changed=0,
            summary=summary,
            report_section=report_section,
        )

    from vault_agent.worktree import worktree_commit_count

    return OrchestratorResult(
        mode=mode,
        dry_run=not apply,
        audit=audit,
        handle=handle,
        commits_made=worktree_commit_count(handle),
        files_changed=worktree_file_change_count(handle),
        summary=summary,
        report_section=report_section,
    )
