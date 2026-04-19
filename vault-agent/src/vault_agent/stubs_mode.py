"""vault-agent stubs — FVH/z classification and redirect repair.

Deterministic: rewrite ``broken_redirect`` files to the canonical
redirect body.

Non-deterministic (report only in this mode): ``stale_duplicate`` files
need content merge judgment — handed off to the LLM-backed subagent
when invoked via ``vault-agent maintain``.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from vault_agent.analyzers.audit import VaultAudit, run_audit
from vault_agent.analyzers.stubs import StubClass
from vault_agent.analyzers.vault_index import scan
from vault_agent.fixers.stub_rewriter import rewrite_broken_redirects
from vault_agent.orchestrator import commit_all, enter_worktree
from vault_agent.worktree import WorktreeHandle, format_review_instructions


@dataclass
class StubsPlan:
    broken_redirects: list[Path]
    stale_duplicates: list[Path]  # reported, not auto-fixed
    clean_redirects: int
    fvh_originals: int


@dataclass
class StubsResult:
    dry_run: bool
    plan: StubsPlan
    audit: VaultAudit
    handle: WorktreeHandle | None
    commits: list[str]


def plan_stubs(audit: VaultAudit) -> StubsPlan:
    broken: list[Path] = []
    stale: list[Path] = []
    clean = 0
    original = 0
    for c in audit.stubs.classifications:
        if c.cls == StubClass.BROKEN_REDIRECT:
            broken.append(c.path)
        elif c.cls == StubClass.STALE_DUPLICATE:
            stale.append(c.path)
        elif c.cls == StubClass.CLEAN_REDIRECT:
            clean += 1
        elif c.cls == StubClass.FVH_ORIGINAL:
            original += 1
    return StubsPlan(
        broken_redirects=sorted(broken),
        stale_duplicates=sorted(stale),
        clean_redirects=clean,
        fvh_originals=original,
    )


def run_stubs(vault: Path, *, apply: bool = False) -> StubsResult:
    vault = Path(vault).expanduser().resolve()
    audit = run_audit(vault)
    plan = plan_stubs(audit)

    if not apply:
        return StubsResult(
            dry_run=True, plan=plan, audit=audit, handle=None, commits=[]
        )

    handle = enter_worktree(vault)
    commits: list[str] = []

    # Rewrite broken redirects inside the worktree.
    wt_index = scan(handle.worktree_path)
    results = rewrite_broken_redirects(wt_index)
    changed = sum(1 for r in results if r.changed)
    if changed:
        msg = f"fix(stubs): restore canonical redirect body in {changed} FVH/z files"
        if commit_all(handle, msg):
            commits.append(msg)

    return StubsResult(
        dry_run=False, plan=plan, audit=audit, handle=handle, commits=commits
    )


def render_dry_run(plan: StubsPlan) -> str:
    lines = [
        "Dry run — no files touched.",
        "",
        f"  clean_redirect  : {plan.clean_redirects} (OK, no action)",
        f"  fvh_original    : {plan.fvh_originals} (OK, no action)",
        f"  broken_redirect : {len(plan.broken_redirects)} (will rewrite to canonical body)",
        f"  stale_duplicate : {len(plan.stale_duplicates)} (needs LLM-backed content merge — not auto-fixed)",
        "",
    ]
    if plan.broken_redirects:
        lines.append("Broken redirects queued for rewrite:")
        for p in plan.broken_redirects[:10]:
            lines.append(f"  {p.name}")
        if len(plan.broken_redirects) > 10:
            lines.append(f"  ... ({len(plan.broken_redirects) - 10} more)")
        lines.append("")
    if plan.stale_duplicates:
        lines.append(
            "Stale duplicates (basename matches Zettelkasten note; "
            "content merge required):"
        )
        for p in plan.stale_duplicates[:10]:
            lines.append(f"  {p.name}")
        if len(plan.stale_duplicates) > 10:
            lines.append(f"  ... ({len(plan.stale_duplicates) - 10} more)")
        lines.append("")
    lines.append("Re-run with --fix to rewrite broken_redirects.")
    return "\n".join(lines)


def render_apply(result: StubsResult) -> str:
    if not result.commits:
        return "Nothing to fix deterministically."
    lines = [f"Applied {len(result.commits)} commits:"]
    for c in result.commits:
        lines.append(f"  • {c}")
    lines.append("")
    lines.append(format_review_instructions(result.handle))
    if result.plan.stale_duplicates:
        lines.append("")
        lines.append(
            f"Reminder: {len(result.plan.stale_duplicates)} stale_duplicate "
            "files still need per-file content-merge review (requires "
            "LLM-backed vault-stubs subagent)."
        )
    return "\n".join(lines)
