"""Strip the legacy ``id:`` frontmatter line.

A scalar line matching ``^id:\\s+...$`` inside the frontmatter block.
We don't touch any other ``id:`` occurrence (inside lists, nested
objects, etc.) because those would be structurally meaningful.
"""

from __future__ import annotations

import re
from pathlib import Path

from vault_agent.fixers._frontmatter_io import load, save

_ID_LINE_RE = re.compile(r"^id:\s+.*$")


def _strip_id_from_lines(fm_lines: list[str]) -> tuple[list[str], bool]:
    """Return (new_lines, was_stripped)."""
    out: list[str] = []
    stripped = False
    for line in fm_lines:
        # Top-level only: must start at column 0 (no leading whitespace).
        if not stripped and _ID_LINE_RE.match(line):
            stripped = True
            continue
        out.append(line)
    return out, stripped


def strip_legacy_id(paths: list[Path]) -> list[Path]:
    """Remove ``id:`` from every given file. Returns the list actually changed."""
    changed: list[Path] = []
    for path in paths:
        ff = load(path)
        if not ff.has_frontmatter:
            continue
        new_lines, was_stripped = _strip_id_from_lines(ff.fm_lines)
        if not was_stripped:
            continue
        ff.fm_lines = new_lines
        save(ff)
        changed.append(path)
    return changed
