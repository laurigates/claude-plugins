"""Filesystem scan that builds a reusable index of the vault.

The index is intentionally cheap: one pass over every ``.md`` file, YAML
frontmatter parsed, wikilinks extracted via regex, nothing more. All
downstream analyzers consume this index rather than re-scanning.

Exclusions follow the convention documented in
``CLAUDE.md`` / ``.claude/rules/vault-conventions.md``: ignore Obsidian's
own state, Claude's metadata, git internals, media, and build artifacts.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

import frontmatter

# Paths that are never vault content. Match on any path segment.
EXCLUDED_DIRS: frozenset[str] = frozenset(
    {
        ".obsidian",
        ".claude",
        ".git",
        ".trash",
        "node_modules",
        "_site",
        "__pycache__",
    }
)

# Top-level directories that contain content we exclude from markdown scans
# because they are non-note assets (media) or build output.
EXCLUDED_TOP: frozenset[str] = frozenset({"Files"})

# Wikilink regex. Captures three groups:
#   1) target  — everything before ``|`` or ``#`` or ``]]``
#   2) section — optional ``#section`` suffix
#   3) alias   — optional ``|alias`` display text
# Embeds ``![[...]]`` are matched too; we note them separately.
_WIKILINK_RE = re.compile(
    r"(?P<embed>!?)\[\[(?P<target>[^\]|#]+)(?:#(?P<section>[^\]|]+))?(?:\|(?P<alias>[^\]]+))?\]\]"
)


@dataclass(frozen=True)
class Wikilink:
    """A parsed ``[[Target]]``, ``[[Target|Alias]]`` or ``![[Target]]``."""

    target: str
    section: str | None
    alias: str | None
    is_embed: bool


@dataclass
class Note:
    """One markdown file in the vault."""

    path: Path  # absolute
    rel_path: Path  # relative to vault root
    basename: str  # without .md extension
    size_bytes: int
    has_frontmatter: bool
    frontmatter: dict  # empty dict if none or unparseable
    raw_frontmatter_text: str  # exact YAML block, "" if none
    body: str
    wikilinks: list[Wikilink] = field(default_factory=list)

    @property
    def tags(self) -> list[str]:
        """Tags from frontmatter (always a list of strings)."""
        raw = self.frontmatter.get("tags")
        if raw is None:
            return []
        if isinstance(raw, str):
            return [raw]
        if isinstance(raw, list):
            out: list[str] = []
            for t in raw:
                if t is None:
                    out.append("__null__")
                else:
                    out.append(str(t))
            return out
        return [str(raw)]

    @property
    def outgoing_targets(self) -> set[str]:
        """Distinct wikilink target basenames (unqualified)."""
        return {link.target.rsplit("/", 1)[-1].strip() for link in self.wikilinks}


@dataclass
class VaultIndex:
    """All information needed by the analyzers, computed in one pass."""

    vault_root: Path
    notes: list[Note]
    # basename (no .md) → list of notes with that basename
    by_basename: dict[str, list[Note]]
    # relative path string → note
    by_rel_path: dict[str, Note]

    def __post_init__(self) -> None:
        if not isinstance(self.vault_root, Path):
            self.vault_root = Path(self.vault_root)

    # -- convenience lookups ----------------------------------------------

    def resolve(self, target: str) -> list[Note]:
        """Resolve a wikilink target to candidate notes.

        Obsidian resolves by basename, but callers may pass a path-qualified
        target like ``Kanban/Main``. We try path-qualified first, then
        basename.
        """
        target = target.strip()
        if not target:
            return []
        # Path-qualified match
        if "/" in target:
            key = target if target.endswith(".md") else f"{target}.md"
            note = self.by_rel_path.get(key)
            if note is not None:
                return [note]
        # Basename match
        return list(self.by_basename.get(target, []))

    def is_broken(self, target: str) -> bool:
        return len(self.resolve(target)) == 0

    def is_ambiguous(self, target: str) -> bool:
        return len(self.resolve(target)) > 1


# ---------------------------------------------------------------------------
# Scanner
# ---------------------------------------------------------------------------


def _iter_markdown(vault_root: Path) -> Iterable[Path]:
    """Walk the vault yielding ``.md`` files under the allowed paths."""
    for path in vault_root.rglob("*.md"):
        parts = set(path.relative_to(vault_root).parts)
        if parts & EXCLUDED_DIRS:
            continue
        top = path.relative_to(vault_root).parts[0]
        if top in EXCLUDED_TOP:
            continue
        yield path


def _parse_wikilinks(body: str) -> list[Wikilink]:
    links: list[Wikilink] = []
    for m in _WIKILINK_RE.finditer(body):
        target = m.group("target").strip()
        if not target:
            continue
        links.append(
            Wikilink(
                target=target,
                section=m.group("section"),
                alias=m.group("alias"),
                is_embed=bool(m.group("embed")),
            )
        )
    return links


def _split_frontmatter(text: str) -> tuple[str, str]:
    """Return (raw_yaml_text, body). Empty raw_yaml_text if no frontmatter."""
    if not text.startswith("---"):
        return "", text
    # Find the closing --- on its own line after position 3
    lines = text.splitlines(keepends=True)
    if len(lines) < 2:
        return "", text
    raw_lines: list[str] = []
    for i, line in enumerate(lines[1:], start=1):
        if line.rstrip() == "---":
            raw_lines = lines[1:i]
            body = "".join(lines[i + 1 :])
            return "".join(raw_lines), body
    # Unclosed frontmatter — treat whole file as body
    return "", text


def _load_note(vault_root: Path, path: Path) -> Note:
    rel = path.relative_to(vault_root)
    try:
        raw = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raw = path.read_text(encoding="utf-8", errors="replace")

    raw_yaml, body_only = _split_frontmatter(raw)
    has_fm = bool(raw_yaml)
    fm: dict = {}
    if has_fm:
        try:
            post = frontmatter.loads(raw)
            fm = dict(post.metadata)
            body_only = post.content
        except Exception:
            # Malformed YAML — keep has_frontmatter True but leave fm empty.
            fm = {}

    return Note(
        path=path,
        rel_path=rel,
        basename=path.stem,
        size_bytes=path.stat().st_size,
        has_frontmatter=has_fm,
        frontmatter=fm,
        raw_frontmatter_text=raw_yaml,
        body=body_only,
        wikilinks=_parse_wikilinks(body_only),
    )


def scan(vault_root: Path | str) -> VaultIndex:
    """Walk the vault once and build a VaultIndex."""
    root = Path(vault_root).expanduser().resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"Vault root not found: {root}")

    notes: list[Note] = []
    by_basename: dict[str, list[Note]] = {}
    by_rel_path: dict[str, Note] = {}

    for path in _iter_markdown(root):
        note = _load_note(root, path)
        notes.append(note)
        by_basename.setdefault(note.basename, []).append(note)
        by_rel_path[str(note.rel_path)] = note

    return VaultIndex(
        vault_root=root,
        notes=notes,
        by_basename=by_basename,
        by_rel_path=by_rel_path,
    )
