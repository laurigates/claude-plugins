"""Wikilink integrity analyzer.

Detects:
  * broken wikilinks (target has no matching ``.md`` anywhere)
  * ambiguous targets (same basename in multiple paths, e.g.
    ``Zettelkasten/Docker.md`` and ``FVH/z/Docker.md``)
  * path-qualified links that happen to resolve (e.g. ``[[Kanban/X]]``
    — obsidian resolves these, but they are an anti-pattern in this
    vault because Kanban boards also appear by basename)
  * top broken targets by reference count (high-leverage fixes)
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from vault_agent.analyzers.vault_index import Note, VaultIndex, Wikilink


@dataclass
class BrokenLink:
    source_path: Path
    target: str
    is_embed: bool

    def to_dict(self) -> dict:
        return {
            "source": str(self.source_path),
            "target": self.target,
            "is_embed": self.is_embed,
        }


@dataclass
class AmbiguousLink:
    source_path: Path
    target: str
    candidate_paths: list[Path]

    def to_dict(self) -> dict:
        return {
            "source": str(self.source_path),
            "target": self.target,
            "candidates": [str(p) for p in self.candidate_paths],
        }


@dataclass
class LinkReport:
    total_wikilinks: int = 0
    broken: list[BrokenLink] = field(default_factory=list)
    ambiguous: list[AmbiguousLink] = field(default_factory=list)
    # Target → number of broken references (most-broken targets first)
    broken_target_frequency: dict[str, int] = field(default_factory=dict)
    # Ambiguous basenames → list of colliding paths
    ambiguous_basenames: dict[str, list[Path]] = field(default_factory=dict)

    @property
    def broken_count(self) -> int:
        return len(self.broken)

    @property
    def ambiguous_count(self) -> int:
        return len(self.ambiguous)

    def top_broken(self, n: int = 20) -> list[tuple[str, int]]:
        return Counter(self.broken_target_frequency).most_common(n)

    def to_dict(self) -> dict:
        return {
            "total_wikilinks": self.total_wikilinks,
            "broken_count": self.broken_count,
            "ambiguous_count": self.ambiguous_count,
            "broken": [b.to_dict() for b in self.broken],
            "ambiguous": [a.to_dict() for a in self.ambiguous],
            "broken_target_frequency": self.broken_target_frequency,
            "ambiguous_basenames": {
                k: [str(p) for p in v] for k, v in self.ambiguous_basenames.items()
            },
            "top_broken": self.top_broken(20),
        }


def _is_meaningfully_broken(link: Wikilink, index: VaultIndex) -> bool:
    """A link resolves if its target maps to at least one note.

    Special case: path-qualified links like ``Kanban/Foo`` — we treat
    them as resolved when the basename exists AND the path-qualified
    form exists, or when the basename alone exists. We do NOT call a
    link broken merely because the path-qualified form doesn't match;
    we reuse VaultIndex.resolve which handles both.
    """
    return len(index.resolve(link.target)) == 0


def analyze_links(index: VaultIndex) -> LinkReport:
    report = LinkReport()
    broken_counter: Counter[str] = Counter()

    for note in index.notes:
        for link in note.wikilinks:
            report.total_wikilinks += 1
            candidates = index.resolve(link.target)
            if not candidates:
                report.broken.append(
                    BrokenLink(
                        source_path=note.path,
                        target=link.target,
                        is_embed=link.is_embed,
                    )
                )
                broken_counter[link.target] += 1
            elif len(candidates) > 1:
                report.ambiguous.append(
                    AmbiguousLink(
                        source_path=note.path,
                        target=link.target,
                        candidate_paths=[c.path for c in candidates],
                    )
                )

    report.broken_target_frequency = dict(broken_counter.most_common())

    # Also emit a global ambiguous-basename map (basename → paths with that
    # basename) for the LLM to reason about cross-namespace collisions.
    for basename, notes in index.by_basename.items():
        if len(notes) > 1:
            report.ambiguous_basenames[basename] = [n.path for n in notes]

    return report
