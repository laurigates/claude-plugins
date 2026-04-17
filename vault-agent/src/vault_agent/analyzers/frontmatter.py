"""Frontmatter & tag analyzers.

Detects the pain points found by the LakuVault audit:
  * bare placeholder tags (``📝``, ``🌱``, ``📝/🌱``)
  * legacy ``id:`` fields
  * ``null`` tag values
  * missing frontmatter
  * over/under-tagging
  * taxonomy duplicates (e.g. ``🔍/security`` vs ``🔒/security``)
  * Templater leakage (``<% tp.file.cursor(1) %>``, ``{{title}}``)
  * FVH notes missing ``context: fvh``
  * corrupted emoji bytes (``\\ufffd``)
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from vault_agent.analyzers.vault_index import Note, VaultIndex

# Tag value treated as a no-op placeholder when it appears alone (no /subcategory).
_BARE_PLACEHOLDERS: frozenset[str] = frozenset({"📝", "🌱", "📝/🌱"})

# Legacy tag emoji that should map to the current scheme.
_LEGACY_TAG_MAP: dict[str, str] = {
    "🗺️": "📝/moc",
    "🗺": "📝/moc",
}

# Templater patterns that should never appear in committed notes.
_TEMPLATER_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"<%\s*tp\."),
    re.compile(r"\{\{title\}\}"),
    re.compile(r"\{\{date\}\}"),
)

# Replacement character produced when UTF-8 bytes fail to decode.
_UNICODE_REPLACEMENT = "\ufffd"


@dataclass
class NoteIssue:
    """One problem found on one note."""

    path: Path
    kind: str  # e.g. "bare-placeholder-tag", "legacy-id-field"
    detail: str

    def to_dict(self) -> dict:
        return {"path": str(self.path), "kind": self.kind, "detail": self.detail}


@dataclass
class FrontmatterReport:
    total_notes: int = 0
    notes_without_frontmatter: list[Path] = field(default_factory=list)
    notes_with_legacy_id: list[Path] = field(default_factory=list)
    notes_with_bare_placeholder: list[Path] = field(default_factory=list)
    notes_with_null_tags: list[Path] = field(default_factory=list)
    notes_with_no_tags: list[Path] = field(default_factory=list)
    notes_over_tagged: list[Path] = field(default_factory=list)  # > 5 tags
    notes_with_templater_leak: list[Path] = field(default_factory=list)
    notes_with_corrupt_emoji: list[Path] = field(default_factory=list)
    fvh_notes_missing_context: list[Path] = field(default_factory=list)
    # Tag string → count of notes using it (across whole vault)
    tag_frequency: dict[str, int] = field(default_factory=dict)
    # Candidate duplicate tag groups: canonical → variants
    tag_duplicate_candidates: dict[str, list[str]] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "total_notes": self.total_notes,
            "notes_without_frontmatter": [str(p) for p in self.notes_without_frontmatter],
            "notes_with_legacy_id": [str(p) for p in self.notes_with_legacy_id],
            "notes_with_bare_placeholder": [
                str(p) for p in self.notes_with_bare_placeholder
            ],
            "notes_with_null_tags": [str(p) for p in self.notes_with_null_tags],
            "notes_with_no_tags": [str(p) for p in self.notes_with_no_tags],
            "notes_over_tagged": [str(p) for p in self.notes_over_tagged],
            "notes_with_templater_leak": [
                str(p) for p in self.notes_with_templater_leak
            ],
            "notes_with_corrupt_emoji": [
                str(p) for p in self.notes_with_corrupt_emoji
            ],
            "fvh_notes_missing_context": [
                str(p) for p in self.fvh_notes_missing_context
            ],
            "tag_frequency": self.tag_frequency,
            "tag_duplicate_candidates": self.tag_duplicate_candidates,
        }


def _is_fvh_note(note: Note) -> bool:
    """A note lives under FVH/ if its relative path starts with that segment."""
    return note.rel_path.parts and note.rel_path.parts[0] == "FVH"


def _normalize_for_dupe_detection(tag: str) -> str:
    """Strip emoji prefix, lowercase, drop trailing 's'. Used to cluster near-duplicates."""
    # Drop all leading non-alphanumeric bytes
    stripped = re.sub(r"^[^a-zA-Z0-9]+/?", "", tag)
    lower = stripped.lower().strip("/")
    if lower.endswith("s"):
        lower = lower[:-1]
    return lower


def analyze_frontmatter(index: VaultIndex) -> FrontmatterReport:
    """Run every frontmatter/tag check over the index in one pass."""
    report = FrontmatterReport(total_notes=len(index.notes))
    dupe_groups: dict[str, set[str]] = {}

    for note in index.notes:
        # Missing frontmatter
        if not note.has_frontmatter:
            report.notes_without_frontmatter.append(note.path)

        fm = note.frontmatter

        # Legacy id: field
        if "id" in fm:
            report.notes_with_legacy_id.append(note.path)

        # FVH notes: require context: fvh
        if _is_fvh_note(note) and fm.get("context") != "fvh":
            report.fvh_notes_missing_context.append(note.path)

        # Tags
        tags = note.tags
        if not tags:
            if note.has_frontmatter:
                report.notes_with_no_tags.append(note.path)
        else:
            if len(tags) > 5:
                report.notes_over_tagged.append(note.path)
            if "__null__" in tags:
                report.notes_with_null_tags.append(note.path)
            if any(t in _BARE_PLACEHOLDERS for t in tags):
                report.notes_with_bare_placeholder.append(note.path)
            if any(_UNICODE_REPLACEMENT in t for t in tags):
                report.notes_with_corrupt_emoji.append(note.path)

            for t in tags:
                if t == "__null__":
                    continue
                report.tag_frequency[t] = report.tag_frequency.get(t, 0) + 1
                key = _normalize_for_dupe_detection(t)
                if key:
                    dupe_groups.setdefault(key, set()).add(t)

        # Templater leakage (raw YAML + body)
        haystack = note.raw_frontmatter_text + "\n" + note.body
        if any(pat.search(haystack) for pat in _TEMPLATER_PATTERNS):
            report.notes_with_templater_leak.append(note.path)

    # Keep only normalized groups with > 1 distinct tag
    report.tag_duplicate_candidates = {
        k: sorted(v) for k, v in dupe_groups.items() if len(v) > 1
    }
    return report
