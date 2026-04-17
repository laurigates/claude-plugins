"""FVH/z redirect-stub classifier.

Convention: ``FVH/z/Foo.md`` is a redirect stub pointing to
``Zettelkasten/Foo.md``. Proper stubs are tiny (<200 bytes), tagged
``redirect``, and contain only ``See [[Zettelkasten/Foo|Foo]] in the
main knowledge base.``

Stale stubs: files under ``FVH/z/`` that were never converted — they
contain full article content and duplicate what's in Zettelkasten.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from vault_agent.analyzers.vault_index import Note, VaultIndex

_FVH_STUB_DIR: tuple[str, ...] = ("FVH", "z")
_CLEAN_STUB_MAX_BYTES = 200


class StubClass(str, Enum):
    """Classification of a FVH/z file."""

    CLEAN_REDIRECT = "clean_redirect"
    # Has redirect tag but body is suspiciously large, or missing zettelkasten target
    BROKEN_REDIRECT = "broken_redirect"
    # Stale full article; no redirect tag; basename exists in Zettelkasten
    STALE_DUPLICATE = "stale_duplicate"
    # Original FVH/z content with no canonical version elsewhere
    FVH_ORIGINAL = "fvh_original"


@dataclass
class StubClassification:
    path: Path
    cls: StubClass
    size_bytes: int
    canonical_path: Path | None  # matching Zettelkasten note, if any

    def to_dict(self) -> dict:
        return {
            "path": str(self.path),
            "class": self.cls.value,
            "size_bytes": self.size_bytes,
            "canonical_path": str(self.canonical_path) if self.canonical_path else None,
        }


@dataclass
class StubReport:
    total_stubs: int = 0
    classifications: list[StubClassification] = field(default_factory=list)

    def count_by_class(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for c in self.classifications:
            out[c.cls.value] = out.get(c.cls.value, 0) + 1
        return out

    def to_dict(self) -> dict:
        return {
            "total_stubs": self.total_stubs,
            "classifications": [c.to_dict() for c in self.classifications],
            "count_by_class": self.count_by_class(),
        }


def _is_fvh_z(note: Note) -> bool:
    return note.rel_path.parts[: len(_FVH_STUB_DIR)] == _FVH_STUB_DIR


def _has_redirect_tag(note: Note) -> bool:
    return "redirect" in note.tags


def _canonical_in_zettelkasten(index: VaultIndex, basename: str) -> Path | None:
    for candidate in index.by_basename.get(basename, []):
        if candidate.rel_path.parts and candidate.rel_path.parts[0] == "Zettelkasten":
            return candidate.path
    return None


def analyze_stubs(index: VaultIndex) -> StubReport:
    report = StubReport()

    for note in index.notes:
        if not _is_fvh_z(note):
            continue
        report.total_stubs += 1
        canonical = _canonical_in_zettelkasten(index, note.basename)

        if _has_redirect_tag(note):
            if note.size_bytes <= _CLEAN_STUB_MAX_BYTES and canonical is not None:
                cls = StubClass.CLEAN_REDIRECT
            else:
                cls = StubClass.BROKEN_REDIRECT
        else:
            if canonical is not None:
                cls = StubClass.STALE_DUPLICATE
            else:
                cls = StubClass.FVH_ORIGINAL

        report.classifications.append(
            StubClassification(
                path=note.path,
                cls=cls,
                size_bytes=note.size_bytes,
                canonical_path=canonical,
            )
        )
    return report
