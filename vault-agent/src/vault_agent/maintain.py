"""vault-agent maintain — orchestrate multiple modes in one worktree.

Runs the deterministic portions of ``lint``, ``links``, and ``stubs``
sequentially, sharing a single git worktree so everything lands as
distinct commits on one branch.

Read-only ``mocs`` analysis is appended to the summary.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from vault_agent.analyzers.audit import run_audit
from vault_agent.analyzers.vault_index import scan
from vault_agent.fixers.id_stripper import strip_legacy_id
from vault_agent.fixers.link_patcher import (
    BROKEN_LINK_REWRITES,
    apply_rewrites,
    summarize_rewrites,
    unqualify_kanban_links,
)
from vault_agent.fixers.stub_rewriter import rewrite_broken_redirects
from vault_agent.fixers.tag_normalizer import normalize_tags
from vault_agent.fixers.templater_cleaner import clean_templater_leakage
from vault_agent.mocs_mode import build_report as build_mocs_report
from vault_agent.orchestrator import commit_all, enter_worktree
from vault_agent.worktree import (
    WorktreeHandle,
    format_review_instructions,
    worktree_file_change_count,
)

AVAILABLE_MODES: tuple[str, ...] = ("lint", "links", "stubs", "mocs")


@dataclass
class MaintainResult:
    dry_run: bool
    modes_requested: list[str]
    commits: list[str]
    handle: WorktreeHandle | None
    mocs_summary: str


def _translate(handle: WorktreeHandle, vault: Path, paths: list[Path]) -> list[Path]:
    out: list[Path] = []
    for p in paths:
        try:
            rel = p.relative_to(vault)
        except ValueError:
            out.append(p)
            continue
        out.append(handle.worktree_path / rel)
    return out


def _run_lint_in(handle: WorktreeHandle, vault: Path) -> list[str]:
    audit = run_audit(vault)
    fm = audit.frontmatter
    commits: list[str] = []

    # 1) id: strip
    targets = _translate(handle, vault, list(fm.notes_with_legacy_id))
    changed = strip_legacy_id(targets)
    if changed:
        msg = f"fix(frontmatter): remove legacy id: field from {len(changed)} notes"
        if commit_all(handle, msg):
            commits.append(msg)

    # 2) Tag normalization
    legacy_moc_paths: list[Path] = []
    for note in audit.index.notes:
        if any(t in ("🗺️", "🗺") for t in note.tags):
            legacy_moc_paths.append(note.path)
    tag_paths = sorted(
        set(fm.notes_with_bare_placeholder)
        | set(fm.notes_with_null_tags)
        | set(legacy_moc_paths)
    )
    targets = _translate(handle, vault, tag_paths)
    results = normalize_tags(targets)
    c = sum(1 for r in results if r.changed)
    if c:
        msg = f"fix(tags): normalize bare 📝/🌱/🗺️/null in {c} notes"
        if commit_all(handle, msg):
            commits.append(msg)

    # 3) Templater cleanup
    targets = _translate(handle, vault, list(fm.notes_with_templater_leak))
    results_t = clean_templater_leakage(targets)
    c = sum(1 for r in results_t if r.changed)
    if c:
        msg = f"fix(templates): remove Templater leakage from {c} notes"
        if commit_all(handle, msg):
            commits.append(msg)

    return commits


def _run_links_in(handle: WorktreeHandle) -> list[str]:
    commits: list[str] = []
    wt_index = scan(handle.worktree_path)
    applicable = {
        old: new
        for old, new in BROKEN_LINK_REWRITES.items()
        if len(wt_index.resolve(new)) == 1
    }
    results = apply_rewrites(wt_index, applicable)
    totals = summarize_rewrites(results)
    for rule, count in totals.items():
        new = applicable[rule]
        msg = f"fix(links): rewrite {count} × [[{rule}]] → [[{new}]]"
        if commit_all(handle, msg):
            commits.append(msg)

    wt_index = scan(handle.worktree_path)
    kanban_results = unqualify_kanban_links(wt_index)
    c = sum(1 for r in kanban_results if r.changed)
    if c:
        msg = f"fix(links): unqualify [[Kanban/X]] → [[X]] in {c} notes"
        if commit_all(handle, msg):
            commits.append(msg)
    return commits


def _run_stubs_in(handle: WorktreeHandle) -> list[str]:
    commits: list[str] = []
    wt_index = scan(handle.worktree_path)
    results = rewrite_broken_redirects(wt_index)
    c = sum(1 for r in results if r.changed)
    if c:
        msg = f"fix(stubs): restore canonical redirect body in {c} FVH/z files"
        if commit_all(handle, msg):
            commits.append(msg)
    return commits


def run_maintain(
    vault: Path, *, modes: list[str], apply: bool = False
) -> MaintainResult:
    vault = Path(vault).expanduser().resolve()
    invalid = [m for m in modes if m not in AVAILABLE_MODES]
    if invalid:
        raise ValueError(
            f"Unknown modes: {invalid}. Available: {AVAILABLE_MODES}"
        )

    # MOCs is analysis-only — compute once regardless of apply.
    audit = run_audit(vault)
    mocs_summary_lines: list[str] = []
    if "mocs" in modes:
        report = build_mocs_report(audit.mocs)
        mocs_summary_lines.append(
            f"MOCs: {len(report.inventory)} total, "
            f"{len(report.legacy_tagged_mocs)} with legacy 🗺️ tag, "
            f"{len(report.missing_moc_candidates)} missing-MOC candidates."
        )

    if not apply:
        return MaintainResult(
            dry_run=True,
            modes_requested=modes,
            commits=[],
            handle=None,
            mocs_summary="\n".join(mocs_summary_lines),
        )

    handle = enter_worktree(vault)
    all_commits: list[str] = []

    if "lint" in modes:
        all_commits.extend(_run_lint_in(handle, vault))
    if "links" in modes:
        all_commits.extend(_run_links_in(handle))
    if "stubs" in modes:
        all_commits.extend(_run_stubs_in(handle))
    # mocs writes are deferred to the LLM-backed subagent.

    return MaintainResult(
        dry_run=False,
        modes_requested=modes,
        commits=all_commits,
        handle=handle,
        mocs_summary="\n".join(mocs_summary_lines),
    )


def render(result: MaintainResult) -> str:
    lines = [
        f"maintain: modes={','.join(result.modes_requested)}  "
        f"{'(dry-run)' if result.dry_run else '(applied)'}",
    ]
    if result.commits:
        lines.append("")
        lines.append(f"{len(result.commits)} commits:")
        for c in result.commits:
            lines.append(f"  • {c}")
    if result.handle is not None:
        lines.append("")
        lines.append(format_review_instructions(result.handle))
    if result.mocs_summary:
        lines.append("")
        lines.append(result.mocs_summary)
    return "\n".join(lines)
