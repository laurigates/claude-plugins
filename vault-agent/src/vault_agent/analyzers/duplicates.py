"""Duplicate-note detector.

  * Same basename in multiple paths (e.g. ``Zettelkasten/Docker.md`` and
    ``FVH/z/Docker.md``). Some are legitimate redirect stubs — the stubs
    analyzer classifies those separately. This one emits the raw list.
  * ``Untitled``, ``Untitled 1``, ``Untitled 2`` style placeholders.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from vault_agent.analyzers.vault_index import VaultIndex

_UNTITLED_RE = re.compile(r"^Untitled(\s+\d+)?$", re.IGNORECASE)


@dataclass
class DuplicateGroup:
    basename: str
    paths: list[Path]

    def to_dict(self) -> dict:
        return {"basename": self.basename, "paths": [str(p) for p in self.paths]}


@dataclass
class DuplicateReport:
    basename_collisions: list[DuplicateGroup] = field(default_factory=list)
    untitled_placeholders: list[Path] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "basename_collision_count": len(self.basename_collisions),
            "basename_collisions": [g.to_dict() for g in self.basename_collisions],
            "untitled_placeholder_count": len(self.untitled_placeholders),
            "untitled_placeholders": [str(p) for p in self.untitled_placeholders],
        }


def analyze_duplicates(index: VaultIndex) -> DuplicateReport:
    report = DuplicateReport()

    for basename, notes in index.by_basename.items():
        if len(notes) > 1:
            report.basename_collisions.append(
                DuplicateGroup(
                    basename=basename,
                    paths=sorted(n.path for n in notes),
                )
            )
        if _UNTITLED_RE.match(basename):
            for note in notes:
                report.untitled_placeholders.append(note.path)

    return report
