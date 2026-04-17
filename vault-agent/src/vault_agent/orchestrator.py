"""Orchestrator — wires pre-computed audit + worktree + SDK session.

Actual LLM invocation via ``claude_agent_sdk`` happens in ``run_llm_mode``.
Pure-Python deterministic modes (see ``fixers/``) bypass the LLM entirely
and call ``apply_deterministic_fixes`` on a worktree.
"""

from __future__ import annotations

import json
import logging
import subprocess
from dataclasses import dataclass
from pathlib import Path

from vault_agent.analyzers.audit import VaultAudit, run_audit
from vault_agent.worktree import (
    WorktreeHandle,
    cleanup_worktree,
    create_worktree,
    format_review_instructions,
    timestamped_branch,
)

logger = logging.getLogger(__name__)


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

    # Embed the audit (trimmed for size — we keep counts + samples, not
    # every path).
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


def commit_all(handle: WorktreeHandle, message: str, *, paths: list[Path] | None = None) -> bool:
    """Stage and commit. Returns True if a commit was made."""
    if paths:
        rels = [str(p.relative_to(handle.worktree_path)) for p in paths]
        subprocess.run(["git", "add", "--", *rels], cwd=handle.worktree_path, check=True)
    else:
        subprocess.run(["git", "add", "-A"], cwd=handle.worktree_path, check=True)

    # Check if anything is actually staged.
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
) -> OrchestratorResult:
    """Compose a result object + the review-commands banner."""
    from vault_agent.worktree import worktree_file_change_count

    files_changed = worktree_file_change_count(handle)
    return OrchestratorResult(
        mode=mode,
        dry_run=False,
        audit=audit,
        handle=handle,
        commits_made=commits_made,
        files_changed=files_changed,
        summary=summary,
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
    return format_review_instructions(result.handle) + "\n\n" + result.summary
