"""vault-agent links — deterministic broken-wikilink repair.

Two deterministic passes:

  1. Rule-table rewrites (e.g. ``[[AnsibleFVH]]`` → ``[[Ansible]]``)
  2. Path-qualified Kanban link unqualification

Ambiguous cross-namespace targets are reported for user decision —
never auto-fixed. LLM-backed link reasoning (e.g. matching ``[[CICD]]``
to ``[[CI/CD]]``) is deferred to the vault-links subagent.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from vault_agent.analyzers.audit import VaultAudit, run_audit
from vault_agent.analyzers.vault_index import VaultIndex, scan
from vault_agent.fixers.link_patcher import (
    BROKEN_LINK_REWRITES,
    apply_rewrites,
    summarize_rewrites,
    unqualify_kanban_links,
)
from vault_agent.orchestrator import commit_all, enter_worktree
from vault_agent.worktree import (
    WorktreeHandle,
    format_review_instructions,
    worktree_file_change_count,
)


@dataclass
class LinksPlan:
    rewrites_available: dict[str, str]  # old → new (only applicable rules)
    kanban_candidates: int
    ambiguous_basenames: list[str]
    low_leverage_broken: list[tuple[str, int]]  # for reporting

    def to_dict(self) -> dict:
        return {
            "rewrites_available": self.rewrites_available,
            "kanban_candidates": self.kanban_candidates,
            "ambiguous_basenames": self.ambiguous_basenames,
            "low_leverage_broken": self.low_leverage_broken,
        }


@dataclass
class LinksResult:
    dry_run: bool
    plan: LinksPlan
    audit: VaultAudit
    handle: WorktreeHandle | None
    commits: list[str]


def plan_links(audit: VaultAudit) -> LinksPlan:
    index = audit.index
    # Only rules with a unique resolvable target.
    available = {
        old: new
        for old, new in BROKEN_LINK_REWRITES.items()
        if len(index.resolve(new)) == 1
    }
    # Count Kanban-qualified links that could be unqualified
    kanban_count = 0
    for note in index.notes:
        for link in note.wikilinks:
            if link.target.startswith("Kanban/"):
                basename = link.target.split("/", 1)[-1]
                if len(index.resolve(basename)) == 1:
                    kanban_count += 1
    return LinksPlan(
        rewrites_available=available,
        kanban_candidates=kanban_count,
        ambiguous_basenames=sorted(audit.links.ambiguous_basenames.keys()),
        low_leverage_broken=audit.links.top_broken(20),
    )


def _translate_worktree(
    handle: WorktreeHandle, vault_root: Path, index: VaultIndex
) -> VaultIndex:
    """Re-scan the worktree so subsequent writes target its paths."""
    return scan(handle.worktree_path)


def run_links(vault: Path, *, apply: bool = False) -> LinksResult:
    vault = Path(vault).expanduser().resolve()
    audit = run_audit(vault)
    plan = plan_links(audit)

    if not apply:
        return LinksResult(
            dry_run=True, plan=plan, audit=audit, handle=None, commits=[]
        )

    handle = enter_worktree(vault)
    # Re-scan inside the worktree so fixers write to the worktree's copies.
    wt_index = _translate_worktree(handle, vault, audit.index)
    commits: list[str] = []

    # Pass 1: rule-table rewrites
    results = apply_rewrites(wt_index, plan.rewrites_available)
    totals = summarize_rewrites(results)
    for rule, count in totals.items():
        new = plan.rewrites_available[rule]
        msg = f"fix(links): rewrite {count} × [[{rule}]] → [[{new}]]"
        if commit_all(handle, msg):
            commits.append(msg)

    # Pass 2: Kanban unqualification
    # Re-scan (previous pass modified files).
    wt_index = scan(handle.worktree_path)
    kanban_results = unqualify_kanban_links(wt_index)
    changed_count = sum(1 for r in kanban_results if r.changed)
    if changed_count:
        msg = f"fix(links): unqualify [[Kanban/X]] → [[X]] in {changed_count} notes"
        if commit_all(handle, msg):
            commits.append(msg)

    return LinksResult(
        dry_run=False, plan=plan, audit=audit, handle=handle, commits=commits
    )


def render_dry_run(plan: LinksPlan) -> str:
    lines = ["Dry run — no files touched.", ""]
    lines.append("Applicable rule-table rewrites:")
    if plan.rewrites_available:
        for old, new in plan.rewrites_available.items():
            lines.append(f"  [[{old}]] → [[{new}]]")
    else:
        lines.append("  (none apply in this vault)")
    lines.append("")
    lines.append(f"Kanban-qualified links to unqualify: {plan.kanban_candidates}")
    lines.append("")
    if plan.ambiguous_basenames:
        lines.append(
            f"Ambiguous basenames requiring user decision: {len(plan.ambiguous_basenames)}"
        )
        for bn in plan.ambiguous_basenames[:10]:
            lines.append(f"  [[{bn}]]")
        if len(plan.ambiguous_basenames) > 10:
            lines.append(f"  ... ({len(plan.ambiguous_basenames) - 10} more)")
        lines.append("")
    lines.append(
        "Low-leverage broken targets (for reference — not auto-fixed):"
    )
    excluded = set(plan.rewrites_available.keys())
    remaining = [(t, c) for t, c in plan.low_leverage_broken if t not in excluded]
    for target, count in remaining[:10]:
        lines.append(f"  [[{target}]] × {count}")
    lines.append("")
    lines.append("Re-run with --fix to apply the deterministic rewrites.")
    return "\n".join(lines)


def render_apply(result: LinksResult) -> str:
    if not result.commits:
        return "Nothing to fix."
    lines = [f"Applied {len(result.commits)} commits:"]
    for c in result.commits:
        lines.append(f"  • {c}")
    lines.append("")
    lines.append(format_review_instructions(result.handle))
    return "\n".join(lines)
