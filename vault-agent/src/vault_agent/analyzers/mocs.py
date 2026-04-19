"""Map-of-Content (MOC) inventory and coverage analysis.

A MOC in this vault is a note tagged ``📝/moc`` (or legacy ``🗺️``) that
links to related content. This analyzer answers:

  * What MOCs exist?
  * Which MOCs use the legacy ``🗺️`` tag and need re-tagging?
  * For each tag category (e.g. ``🛠️/``, ``🔌/``, ``☁️/``), how many
    notes have that tag but aren't linked from any MOC?
  * What topic clusters warrant new MOCs? (Categories with many unlinked
    notes and no MOC covering them.)
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from vault_agent.analyzers.vault_index import Note, VaultIndex

MOC_TAGS_CURRENT: frozenset[str] = frozenset({"📝/moc"})
MOC_TAGS_LEGACY: frozenset[str] = frozenset({"🗺️", "🗺"})

# Min notes in a category to warrant a MOC when one is missing.
NEW_MOC_THRESHOLD = 10


@dataclass
class MOC:
    path: Path
    basename: str
    tags: list[str]
    outgoing_links: list[str]  # wikilink targets
    has_legacy_tag: bool

    def to_dict(self) -> dict:
        return {
            "path": str(self.path),
            "basename": self.basename,
            "tags": self.tags,
            "outgoing_link_count": len(self.outgoing_links),
            "has_legacy_tag": self.has_legacy_tag,
        }


@dataclass
class CategoryCoverage:
    """Tag-category statistics."""

    category: str  # e.g. "🛠️", "🔌", "💻"
    tagged_note_count: int
    unlinked_note_count: int  # tagged notes not linked from any MOC
    sample_unlinked_paths: list[Path]

    def to_dict(self) -> dict:
        return {
            "category": self.category,
            "tagged_note_count": self.tagged_note_count,
            "unlinked_note_count": self.unlinked_note_count,
            "sample_unlinked_paths": [str(p) for p in self.sample_unlinked_paths],
        }


@dataclass
class MocReport:
    mocs: list[MOC] = field(default_factory=list)
    legacy_tagged_mocs: list[Path] = field(default_factory=list)
    coverage_by_category: list[CategoryCoverage] = field(default_factory=list)
    # Categories with >= NEW_MOC_THRESHOLD notes and no MOC whose basename
    # or title matches the category.
    missing_moc_candidates: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "moc_count": len(self.mocs),
            "mocs": [m.to_dict() for m in self.mocs],
            "legacy_tagged_mocs": [str(p) for p in self.legacy_tagged_mocs],
            "coverage_by_category": [c.to_dict() for c in self.coverage_by_category],
            "missing_moc_candidates": self.missing_moc_candidates,
        }


def _tag_category(tag: str) -> str | None:
    """Return the emoji-prefix category (``🛠️`` from ``🛠️/neovim``) or None."""
    if "/" not in tag:
        return None
    prefix = tag.split("/", 1)[0]
    # Category must start with a non-ASCII char (emoji)
    if prefix and not prefix[0].isascii():
        return prefix
    return None


def _is_moc(note: Note) -> tuple[bool, bool]:
    """Return (is_moc, has_legacy_tag)."""
    tags = set(note.tags)
    has_current = bool(tags & MOC_TAGS_CURRENT)
    has_legacy = bool(tags & MOC_TAGS_LEGACY)
    return (has_current or has_legacy, has_legacy)


def analyze_mocs(index: VaultIndex, *, sample_size: int = 10) -> MocReport:
    report = MocReport()

    # Pass 1: inventory MOCs.
    linked_from_moc: set[Path] = set()
    for note in index.notes:
        is_moc, has_legacy = _is_moc(note)
        if not is_moc:
            continue
        targets = [lnk.target for lnk in note.wikilinks]
        report.mocs.append(
            MOC(
                path=note.path,
                basename=note.basename,
                tags=note.tags,
                outgoing_links=targets,
                has_legacy_tag=has_legacy,
            )
        )
        if has_legacy:
            report.legacy_tagged_mocs.append(note.path)
        # Mark every note this MOC links to as "linked from a MOC".
        for lnk in note.wikilinks:
            for target_note in index.resolve(lnk.target):
                linked_from_moc.add(target_note.path)

    # Pass 2: per-category coverage.
    category_notes: dict[str, list[Note]] = {}
    for note in index.notes:
        for tag in note.tags:
            cat = _tag_category(tag)
            if cat:
                category_notes.setdefault(cat, []).append(note)
                break  # one category per note is enough for this summary

    for cat, notes in sorted(category_notes.items(), key=lambda kv: -len(kv[1])):
        unlinked = [n for n in notes if n.path not in linked_from_moc]
        report.coverage_by_category.append(
            CategoryCoverage(
                category=cat,
                tagged_note_count=len(notes),
                unlinked_note_count=len(unlinked),
                sample_unlinked_paths=[n.path for n in unlinked[:sample_size]],
            )
        )

    # Pass 3: categories that would benefit from a new MOC.
    moc_basenames_lower = {m.basename.lower() for m in report.mocs}
    for cov in report.coverage_by_category:
        if cov.unlinked_note_count < NEW_MOC_THRESHOLD:
            continue
        # Heuristic: does any existing MOC mention this category's first letter?
        # We're coarse here — the LLM makes the final call.
        has_relevant_moc = any(
            cov.category in (m.basename or "") or cov.category in " ".join(m.tags)
            for m in report.mocs
        )
        if not has_relevant_moc:
            report.missing_moc_candidates.append(cov.category)

    return report
