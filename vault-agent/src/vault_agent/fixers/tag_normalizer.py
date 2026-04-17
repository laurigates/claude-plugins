"""Tag normalization: remove placeholders, rewrite legacy tags.

Handles the two common tag-list YAML styles by line editing, preserving
the original format:

Inline:
    tags: [📝, 🛠️/neovim]      →  tags: [🛠️/neovim]

Block:
    tags:
      - 📝                         →  tags:
      - 🛠️/neovim                       - 🛠️/neovim

Single scalar:
    tags: 📝                      →  (line removed; note has no tags after)

We do NOT convert between styles. If the result would leave an empty
list, we leave the key with ``tags: []`` rather than deleting it —
callers that want the empty-tags case removed should run a second pass.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from vault_agent.fixers._frontmatter_io import FrontmatterFile, load, save

# Bare placeholder tags — no-ops we want to drop.
BARE_PLACEHOLDERS: frozenset[str] = frozenset({"📝", "🌱", "📝/🌱"})

# Tag rewrites applied verbatim.
TAG_REWRITES: dict[str, str] = {
    "🗺️": "📝/moc",
    "🗺": "📝/moc",
}


@dataclass
class TagFixResult:
    path: Path
    changed: bool
    removed_placeholders: int
    rewrites: int
    removed_nulls: int


_INLINE_TAGS_RE = re.compile(r"^(\s*tags\s*:\s*)\[(.*)\](\s*)$")
_BLOCK_TAGS_HEADER_RE = re.compile(r"^(\s*tags\s*:\s*)$")
_BLOCK_TAGS_ITEM_RE = re.compile(r"^(\s+-\s+)(.+?)(\s*)$")
_SCALAR_TAGS_RE = re.compile(r"^(\s*tags\s*:\s+)(\S.*?)(\s*)$")


def _apply_rewrites(tag: str) -> str:
    return TAG_REWRITES.get(tag, tag)


def _split_inline_tags(csv: str) -> list[str]:
    """Parse ``a, b, c`` into tag strings. Handles quoted values."""
    out: list[str] = []
    for raw in csv.split(","):
        t = raw.strip()
        if len(t) >= 2 and t[0] == t[-1] and t[0] in ("'", '"'):
            t = t[1:-1]
        if t:
            out.append(t)
    return out


def _format_inline_tags(tags: list[str]) -> str:
    return ", ".join(tags)


def _process_inline_line(line: str) -> tuple[str, int, int, int]:
    """Returns (new_line, placeholders_removed, rewrites, nulls_removed)."""
    m = _INLINE_TAGS_RE.match(line)
    if not m:
        return line, 0, 0, 0
    prefix, body, suffix = m.group(1), m.group(2), m.group(3)
    tags = _split_inline_tags(body)
    new_tags: list[str] = []
    p = r = n = 0
    for tag in tags:
        if tag.lower() == "null":
            n += 1
            continue
        if tag in BARE_PLACEHOLDERS:
            p += 1
            continue
        rewritten = _apply_rewrites(tag)
        if rewritten != tag:
            r += 1
        new_tags.append(rewritten)
    if p == 0 and r == 0 and n == 0:
        return line, 0, 0, 0
    return f"{prefix}[{_format_inline_tags(new_tags)}]{suffix}", p, r, n


def _process_block_items(
    lines: list[str], start: int
) -> tuple[list[str], int, int, int, int]:
    """Process the block-list items starting at ``start+1`` (after the header).

    Returns (new_lines, end_index_exclusive, placeholders, rewrites, nulls).
    ``end_index_exclusive`` is the first line past the block-item region.
    """
    out: list[str] = []
    p = r = n = 0
    i = start + 1
    while i < len(lines):
        item = _BLOCK_TAGS_ITEM_RE.match(lines[i])
        if not item:
            break
        prefix, value, suffix = item.group(1), item.group(2).strip(), item.group(3)
        # Strip quotes around the value.
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        if value.lower() == "null":
            n += 1
            i += 1
            continue
        if value in BARE_PLACEHOLDERS:
            p += 1
            i += 1
            continue
        rewritten = _apply_rewrites(value)
        if rewritten != value:
            r += 1
        out.append(f"{prefix}{rewritten}{suffix}")
        i += 1
    return out, i, p, r, n


def _process_scalar_line(line: str) -> tuple[str | None, int, int, int]:
    """Process ``tags: foo``. Returns (new_line_or_None, p, r, n).

    None means "drop the line entirely" (the single tag was a placeholder).
    """
    m = _SCALAR_TAGS_RE.match(line)
    if not m:
        return line, 0, 0, 0
    prefix, value, suffix = m.group(1), m.group(2).strip(), m.group(3)
    # Skip if the value looks like a list/flow-style start.
    if value.startswith("["):
        return line, 0, 0, 0
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        value = value[1:-1]
    if value.lower() == "null":
        return None, 0, 0, 1
    if value in BARE_PLACEHOLDERS:
        return None, 1, 0, 0
    rewritten = _apply_rewrites(value)
    if rewritten != value:
        return f"{prefix}{rewritten}{suffix}", 0, 1, 0
    return line, 0, 0, 0


def _normalize_fm_lines(lines: list[str]) -> tuple[list[str], int, int, int]:
    """Pass over frontmatter lines applying the transforms."""
    out: list[str] = []
    p = r = n = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        # Inline list
        if _INLINE_TAGS_RE.match(line):
            new_line, pp, rr, nn = _process_inline_line(line)
            p += pp
            r += rr
            n += nn
            out.append(new_line)
            i += 1
            continue
        # Block list header
        if _BLOCK_TAGS_HEADER_RE.match(line):
            new_items, end, pp, rr, nn = _process_block_items(lines, i)
            if new_items:
                out.append(line)
                out.extend(new_items)
            else:
                # Header with no remaining items after pruning — drop whole block
                pass
            p += pp
            r += rr
            n += nn
            i = end
            continue
        # Scalar tags: value
        if _SCALAR_TAGS_RE.match(line):
            new_line, pp, rr, nn = _process_scalar_line(line)
            p += pp
            r += rr
            n += nn
            if new_line is not None:
                out.append(new_line)
            i += 1
            continue
        out.append(line)
        i += 1
    return out, p, r, n


def normalize_tags(paths: list[Path]) -> list[TagFixResult]:
    """Normalize tag lists in each file. Returns per-file results."""
    results: list[TagFixResult] = []
    for path in paths:
        ff = load(path)
        if not ff.has_frontmatter:
            results.append(
                TagFixResult(
                    path=path,
                    changed=False,
                    removed_placeholders=0,
                    rewrites=0,
                    removed_nulls=0,
                )
            )
            continue
        new_lines, p, r, n = _normalize_fm_lines(ff.fm_lines)
        changed = p + r + n > 0 or new_lines != ff.fm_lines
        if changed:
            ff.fm_lines = new_lines
            save(ff)
        results.append(
            TagFixResult(
                path=path,
                changed=changed,
                removed_placeholders=p,
                rewrites=r,
                removed_nulls=n,
            )
        )
    return results
