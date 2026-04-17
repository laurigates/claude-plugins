"""Composite 0–100 vault-health score.

Five equally-weighted sub-scores (each 0–20):

  * tags        — % of notes with clean tags (no bare placeholder, no legacy id:)
  * links       — 1 − (broken_links / total_links)
  * orphans     — 1 − (meaningful_orphans / total_meaningful_notes)
  * stubs       — % of FVH/z files classified as CLEAN_REDIRECT or FVH_ORIGINAL
  * mocs        — 1 − (unlinked_category_notes / total_category_notes)

Missing sub-scores contribute 0. An empty vault (0 notes) scores 100.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

from vault_agent.analyzers.frontmatter import FrontmatterReport
from vault_agent.analyzers.graph import GraphReport
from vault_agent.analyzers.links import LinkReport
from vault_agent.analyzers.mocs import MocReport
from vault_agent.analyzers.stubs import StubClass, StubReport


@dataclass
class HealthScore:
    tags: float
    links: float
    orphans: float
    stubs: float
    mocs: float
    total: float  # 0–100

    def to_dict(self) -> dict:
        return asdict(self)


def _ratio_score(numer: int, denom: int, *, max_points: float = 20.0) -> float:
    if denom <= 0:
        return max_points
    return max_points * max(0.0, 1.0 - numer / denom)


def compute_health(
    *,
    frontmatter: FrontmatterReport,
    links: LinkReport,
    graph: GraphReport,
    stubs: StubReport,
    mocs: MocReport,
) -> HealthScore:
    total_notes = frontmatter.total_notes
    # Notes with tag issues: union of bare-placeholder + legacy id + null tags.
    broken_tag_paths = set(
        frontmatter.notes_with_bare_placeholder
        + frontmatter.notes_with_legacy_id
        + frontmatter.notes_with_null_tags
        + frontmatter.notes_with_templater_leak
    )
    tag_score = _ratio_score(len(broken_tag_paths), total_notes)

    link_score = _ratio_score(links.broken_count, links.total_wikilinks)
    orphan_score = _ratio_score(len(graph.meaningful_orphans), total_notes)

    # Stubs: CLEAN_REDIRECT or FVH_ORIGINAL are "good". BROKEN_REDIRECT and
    # STALE_DUPLICATE count against the score.
    bad_stubs = sum(
        1
        for c in stubs.classifications
        if c.cls in (StubClass.BROKEN_REDIRECT, StubClass.STALE_DUPLICATE)
    )
    stub_score = _ratio_score(bad_stubs, stubs.total_stubs)

    total_category_notes = sum(c.tagged_note_count for c in mocs.coverage_by_category)
    unlinked_category_notes = sum(
        c.unlinked_note_count for c in mocs.coverage_by_category
    )
    moc_score = _ratio_score(unlinked_category_notes, total_category_notes)

    total = tag_score + link_score + orphan_score + stub_score + moc_score
    return HealthScore(
        tags=round(tag_score, 2),
        links=round(link_score, 2),
        orphans=round(orphan_score, 2),
        stubs=round(stub_score, 2),
        mocs=round(moc_score, 2),
        total=round(total, 2),
    )
