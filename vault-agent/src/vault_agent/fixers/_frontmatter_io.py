"""Utilities for reading and writing YAML frontmatter safely.

We use line-based editing for frontmatter rather than round-tripping
through pyyaml. This preserves the original whitespace and key order,
which keeps diffs minimal and easy to review.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass
class FrontmatterFile:
    """A markdown file split into its frontmatter lines and body lines."""

    path: Path
    has_frontmatter: bool
    fm_lines: list[str]  # lines BETWEEN the --- markers (excl. the markers)
    body: str  # everything after the closing --- (raw)
    eol: str  # line ending used in the source file

    def join(self) -> str:
        if not self.has_frontmatter:
            return self.body
        return (
            "---" + self.eol
            + "".join(self.fm_lines)
            + "---" + self.eol
            + self.body
        )


def _detect_eol(text: str) -> str:
    if "\r\n" in text:
        return "\r\n"
    return "\n"


def load(path: Path) -> FrontmatterFile:
    """Split a file into its frontmatter lines + body. Lossless."""
    raw = path.read_text(encoding="utf-8")
    eol = _detect_eol(raw)
    if not raw.startswith("---"):
        return FrontmatterFile(
            path=path, has_frontmatter=False, fm_lines=[], body=raw, eol=eol
        )
    lines = raw.splitlines(keepends=True)
    if len(lines) < 2:
        return FrontmatterFile(
            path=path, has_frontmatter=False, fm_lines=[], body=raw, eol=eol
        )
    for i, line in enumerate(lines[1:], start=1):
        if line.rstrip() == "---":
            fm_lines = lines[1:i]
            body = "".join(lines[i + 1 :])
            return FrontmatterFile(
                path=path,
                has_frontmatter=True,
                fm_lines=list(fm_lines),
                body=body,
                eol=eol,
            )
    # Unclosed frontmatter — treat as no frontmatter.
    return FrontmatterFile(
        path=path, has_frontmatter=False, fm_lines=[], body=raw, eol=eol
    )


def save(ff: FrontmatterFile) -> None:
    """Write the file back to disk atomically-ish (write + rename)."""
    tmp = ff.path.with_suffix(ff.path.suffix + ".tmp")
    tmp.write_text(ff.join(), encoding="utf-8")
    tmp.replace(ff.path)
