"""vault-agent lint — deterministic, LLM-free frontmatter/tag cleanup.

Orchestrates the three fixers in a single worktree with per-category
conventional commits:

  1. fix(frontmatter): remove legacy id: field from N notes
  2. fix(tags): normalize bare 📝/🌱/🗺️/null in N notes
  3. fix(templates): remove Templater leakage in N notes

In ``--dry-run`` mode, prints the plan without touching the vault.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from vault_agent.analyzers.audit import VaultAudit, run_audit
from vault_agent.fixers.id_stripper import strip_legacy_id
from vault_agent.fixers.tag_normalizer import normalize_tags
from vault_agent.fixers.templater_cleaner import clean_templater_leakage
from vault_agent.orchestrator import commit_all, enter_worktree
from vault_agent.worktree import (
    WorktreeHandle,
    cleanup_worktree,
    format_review_instructions,
    worktree_commit_count,
    worktree_file_change_count,
)


@dataclass
class LintPlan:
    """Per-category list of target files, relative to vault root."""

    legacy_id: list[Path]
    tag_issues: list[Path]
    templater: list[Path]

    @property
    def total_files(self) -> int:
        all_paths = set(self.legacy_id) | set(self.tag_issues) | set(self.templater)
        return len(all_paths)


@dataclass
class LintResult:
    dry_run: bool
    plan: LintPlan
    audit: VaultAudit
    handle: WorktreeHandle | None
    commits: list[str]

    @property
    def files_changed(self) -> int:
        if self.handle is None:
            return 0
        return worktree_file_change_count(self.handle)


def _translate_paths(
    handle: WorktreeHandle | None, vault: Path, paths: list[Path]
) -> list[Path]:
    """If running in a worktree, translate vault-rooted paths into worktree paths."""
    if handle is None:
        return paths
    out: list[Path] = []
    for p in paths:
        try:
            rel = p.relative_to(vault)
        except ValueError:
            # Already inside the worktree, or unrelated path.
            out.append(p)
            continue
        out.append(handle.worktree_path / rel)
    return out


def plan_lint(audit: VaultAudit) -> LintPlan:
    fm = audit.frontmatter
    return LintPlan(
        legacy_id=list(fm.notes_with_legacy_id),
        # tag_issues: any note with bare placeholder, null, or legacy 🗺️
        tag_issues=sorted(
            set(fm.notes_with_bare_placeholder) | set(fm.notes_with_null_tags)
            # legacy-tag candidates come from the tag frequency map
        ),
        templater=list(fm.notes_with_templater_leak),
    )


def run_lint(vault: Path, *, apply: bool = False) -> LintResult:
    """Run lint. In ``apply=False`` mode, returns plan + empty commits."""
    vault = Path(vault).expanduser().resolve()
    audit = run_audit(vault)
    plan = plan_lint(audit)

    # Also include notes whose tag frequency map has the legacy MOC tag.
    # (The frontmatter analyzer records these under tag_frequency.)
    legacy_moc_candidates: list[Path] = []
    for note in audit.index.notes:
        if any(t in ("🗺️", "🗺") for t in note.tags):
            legacy_moc_candidates.append(note.path)
    # Merge into tag_issues without introducing duplicates.
    merged = sorted({*plan.tag_issues, *legacy_moc_candidates})
    plan = LintPlan(
        legacy_id=plan.legacy_id,
        tag_issues=merged,
        templater=plan.templater,
    )

    if not apply:
        return LintResult(
            dry_run=True, plan=plan, audit=audit, handle=None, commits=[]
        )

    handle = enter_worktree(vault)
    commits: list[str] = []

    # 1) Strip legacy id
    targets = _translate_paths(handle, vault, plan.legacy_id)
    changed = strip_legacy_id(targets)
    if changed and commit_all(
        handle,
        f"fix(frontmatter): remove legacy id: field from {len(changed)} notes",
    ):
        commits.append(f"fix(frontmatter): remove legacy id: field from {len(changed)} notes")

    # 2) Tags normalization
    targets = _translate_paths(handle, vault, plan.tag_issues)
    results = normalize_tags(targets)
    changed_count = sum(1 for r in results if r.changed)
    if changed_count and commit_all(
        handle,
        f"fix(tags): normalize bare 📝/🌱/🗺️/null in {changed_count} notes",
    ):
        commits.append(f"fix(tags): normalize bare 📝/🌱/🗺️/null in {changed_count} notes")

    # 3) Templater cleanup
    targets = _translate_paths(handle, vault, plan.templater)
    results_t = clean_templater_leakage(targets)
    changed_count = sum(1 for r in results_t if r.changed)
    if changed_count and commit_all(
        handle,
        f"fix(templates): remove Templater leakage from {changed_count} notes",
    ):
        commits.append(f"fix(templates): remove Templater leakage from {changed_count} notes")

    return LintResult(
        dry_run=False, plan=plan, audit=audit, handle=handle, commits=commits
    )


def render_dry_run(plan: LintPlan) -> str:
    return (
        "Dry run — no files touched.\n"
        f"  legacy id: field         : {len(plan.legacy_id)} notes\n"
        f"  tag normalization        : {len(plan.tag_issues)} notes\n"
        f"  Templater leakage        : {len(plan.templater)} notes\n"
        f"  unique files affected    : {plan.total_files}\n\n"
        f"Re-run with --fix to apply."
    )


def render_apply(result: LintResult) -> str:
    if not result.commits:
        return "Nothing to fix."
    lines = [
        f"Applied {len(result.commits)} commits:",
    ]
    for c in result.commits:
        lines.append(f"  • {c}")
    lines.append("")
    lines.append(format_review_instructions(result.handle))
    return "\n".join(lines)
