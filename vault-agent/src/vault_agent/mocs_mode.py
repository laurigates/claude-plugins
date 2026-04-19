"""vault-agent mocs — Map-of-Content analysis and curation.

Deterministic portions:
  * Detect legacy `🗺️` → `📝/moc` fixups (overlap with ``vault-agent lint``;
    we report but delegate the write to the lint pass so the diff stays
    clean).
  * Identify categories without a MOC that exceed the threshold.

Non-deterministic (require LLM judgment — deferred to the mocs subagent):
  * Creating a new MOC with curated section structure
  * Linking orphan notes into existing MOCs
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from vault_agent.analyzers.audit import VaultAudit, run_audit
from vault_agent.analyzers.mocs import MocReport


@dataclass
class MocsReport:
    inventory: list[tuple[str, Path, bool]]  # (basename, path, has_legacy_tag)
    legacy_tagged_mocs: list[Path]
    missing_moc_candidates: list[str]
    coverage: list[tuple[str, int, int]]  # (category, tagged, unlinked)

    def to_dict(self) -> dict:
        return {
            "inventory": [(n, str(p), legacy) for n, p, legacy in self.inventory],
            "legacy_tagged_mocs": [str(p) for p in self.legacy_tagged_mocs],
            "missing_moc_candidates": self.missing_moc_candidates,
            "coverage": self.coverage,
        }


def build_report(mocs: MocReport) -> MocsReport:
    inventory = [(m.basename, m.path, m.has_legacy_tag) for m in mocs.mocs]
    coverage = [
        (c.category, c.tagged_note_count, c.unlinked_note_count)
        for c in mocs.coverage_by_category
    ]
    return MocsReport(
        inventory=inventory,
        legacy_tagged_mocs=list(mocs.legacy_tagged_mocs),
        missing_moc_candidates=list(mocs.missing_moc_candidates),
        coverage=coverage,
    )


def run_mocs(vault: Path) -> tuple[VaultAudit, MocsReport]:
    """Read-only: produce a MOC report. No writes in this mode (yet)."""
    vault = Path(vault).expanduser().resolve()
    audit = run_audit(vault)
    return audit, build_report(audit.mocs)


def render_report(report: MocsReport) -> str:
    lines = [
        "MOC analysis (read-only).",
        "",
        f"MOCs found: {len(report.inventory)}",
    ]
    for name, path, is_legacy in report.inventory:
        flag = "  ⚠️ legacy tag" if is_legacy else ""
        lines.append(f"  {name}{flag}")
    lines.append("")

    if report.legacy_tagged_mocs:
        lines.append(
            f"Legacy-tagged MOCs (🗺️ → 📝/moc via `vault-agent lint --fix`): "
            f"{len(report.legacy_tagged_mocs)}"
        )
        lines.append("")

    if report.coverage:
        lines.append("Coverage by tag category:")
        lines.append("  category  tagged  unlinked")
        for cat, tagged, unlinked in report.coverage:
            lines.append(f"  {cat}        {tagged:>5}  {unlinked:>5}")
        lines.append("")

    if report.missing_moc_candidates:
        lines.append(
            f"Categories that may warrant a new MOC (≥10 unlinked notes, "
            f"no covering MOC): {len(report.missing_moc_candidates)}"
        )
        for cat in report.missing_moc_candidates:
            lines.append(f"  {cat}")
        lines.append("")
        lines.append(
            "Proposing and creating MOCs requires LLM judgment — "
            "deferred to the vault-mocs subagent."
        )

    return "\n".join(lines)
