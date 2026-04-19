"""Knowledge-graph analyzer: orphans, hubs, incoming-link counts.

"Orphan" = note with zero incoming wikilinks AND zero outgoing wikilinks.
Daily notes (files under ``Notes/`` or ``FVH/notes/``) and inbox files
are listed separately because they are expected to have few links.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from vault_agent.analyzers.vault_index import Note, VaultIndex

# Top-level directories whose notes are expected to be weakly connected.
# They're counted, but not flagged as "meaningful" orphans.
_EXPECTED_ORPHAN_DIRS: frozenset[str] = frozenset(
    {"Inbox", "Notes", "truecharts-migration", "radio-hacking"}
)

# Daily-note directories (expected to have few backlinks).
_DAILY_DIRS: tuple[tuple[str, ...], ...] = (
    ("Notes",),
    ("FVH", "notes"),
)


def _is_daily_note(note: Note) -> bool:
    for prefix in _DAILY_DIRS:
        if note.rel_path.parts[: len(prefix)] == prefix:
            return True
    return False


def _is_expected_orphan(note: Note) -> bool:
    top = note.rel_path.parts[0] if note.rel_path.parts else ""
    return top in _EXPECTED_ORPHAN_DIRS


@dataclass
class GraphReport:
    # Count of incoming wikilinks per note, indexed by absolute path.
    incoming_counts: dict[Path, int] = field(default_factory=dict)
    # Absolute paths of notes with 0 incoming and 0 outgoing links,
    # excluding expected-orphan directories.
    meaningful_orphans: list[Path] = field(default_factory=list)
    expected_orphans: list[Path] = field(default_factory=list)
    # (path, incoming_count) sorted descending — the vault's knowledge hubs.
    top_hubs: list[tuple[Path, int]] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "incoming_counts": {str(p): c for p, c in self.incoming_counts.items()},
            "meaningful_orphans": [str(p) for p in self.meaningful_orphans],
            "expected_orphans": [str(p) for p in self.expected_orphans],
            "top_hubs": [(str(p), c) for p, c in self.top_hubs],
            "meaningful_orphan_count": len(self.meaningful_orphans),
        }


def analyze_graph(index: VaultIndex, *, hub_limit: int = 20) -> GraphReport:
    # Incoming counts via resolved targets.
    incoming = Counter()
    for note in index.notes:
        for link in note.wikilinks:
            for target_note in index.resolve(link.target):
                incoming[target_note.path] += 1

    report = GraphReport()
    report.incoming_counts = dict(incoming)

    for note in index.notes:
        has_incoming = incoming.get(note.path, 0) > 0
        has_outgoing = len(note.wikilinks) > 0
        if not has_incoming and not has_outgoing:
            if _is_expected_orphan(note) or _is_daily_note(note):
                report.expected_orphans.append(note.path)
            else:
                report.meaningful_orphans.append(note.path)

    # Hubs: top-N by incoming count.
    report.top_hubs = [
        (path, count)
        for path, count in sorted(incoming.items(), key=lambda kv: -kv[1])[:hub_limit]
    ]
    return report
