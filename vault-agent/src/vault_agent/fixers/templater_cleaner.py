"""Remove unrendered Templater markers.

Drops ``<% tp.file.cursor(...) %>``, strips orphan ``<% tp.* %>``, and
replaces ``{{title}}`` with the filename stem.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from vault_agent.fixers._frontmatter_io import load, save

_CURSOR_MARKER_RE = re.compile(r"<%\s*tp\.file\.cursor\([^)]*\)\s*%>")
_ANY_TP_MARKER_RE = re.compile(r"<%\s*tp\.[^%]*%>")
_TITLE_RE = re.compile(r"\{\{title\}\}")
_DATE_RE = re.compile(r"\{\{date\}\}")


@dataclass
class TemplaterFixResult:
    path: Path
    changed: bool
    cursor_markers_removed: int
    title_substitutions: int
    generic_tp_markers_removed: int


def _collapse_blank_lines(text: str) -> str:
    """Squish 3+ consecutive newlines down to 2 (one blank line)."""
    return re.sub(r"\n{3,}", "\n\n", text)


def clean_templater_leakage(paths: list[Path]) -> list[TemplaterFixResult]:
    """Strip Templater markers from each file. Returns per-file results."""
    results: list[TemplaterFixResult] = []
    for path in paths:
        ff = load(path)
        body = ff.body
        filename_stem = path.stem

        cursor_n = len(_CURSOR_MARKER_RE.findall(body))
        title_n = len(_TITLE_RE.findall(body))
        date_n = len(_DATE_RE.findall(body))

        new_body = body
        if cursor_n:
            new_body = _CURSOR_MARKER_RE.sub("", new_body)
        if title_n:
            new_body = _TITLE_RE.sub(filename_stem, new_body)
        # Generic {{date}} — replace with filename if it looks like a date.
        if date_n and re.match(r"^\d{4}-\d{2}-\d{2}$", filename_stem):
            new_body = _DATE_RE.sub(filename_stem, new_body)

        # Any other stray <% tp.* %> (non-cursor) — count + strip.
        remaining_markers = _ANY_TP_MARKER_RE.findall(new_body)
        generic_n = len(remaining_markers)
        if generic_n:
            new_body = _ANY_TP_MARKER_RE.sub("", new_body)

        changed_body = new_body != body
        if changed_body:
            ff.body = _collapse_blank_lines(new_body)
            save(ff)

        results.append(
            TemplaterFixResult(
                path=path,
                changed=changed_body,
                cursor_markers_removed=cursor_n,
                title_substitutions=title_n,
                generic_tp_markers_removed=generic_n,
            )
        )
    return results
