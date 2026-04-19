"""Deterministic helpers the vault-mocs subagent calls (issues #1071, #1072).

Nothing here invokes the LLM; these are the safety rails and parsing
primitives the subagent's prompt tells it to use before writing to a MOC.

  * ``parse_moc_sections`` — extract the ``##``-level section structure
    (and the wikilinks inside each section) from a MOC body.

  * ``is_dataview_moc`` — detect MOCs whose body is a dataview code
    fence. Skip these: static links would break the regenerating query.

  * ``insert_link_alphabetically`` — add a wikilink to the right place
    inside a section, preserving the existing sort order (alphabetical,
    inferred from the section's first 3 entries).

  * ``render_new_moc`` — compose a canonical new-MOC body from a
    proposal (title, intro, sections, per-section links).

  * ``NEW_MOC_FILENAME_TEMPLATE`` — the vault's naming convention for
    new MOCs: ``Zettelkasten/{Subject} MOC.md``.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


NEW_MOC_FILENAME_TEMPLATE = "Zettelkasten/{subject} MOC.md"

_FRONTMATTER_RE = re.compile(r"\A\s*---\n(.*?)\n---\n", re.DOTALL)
_H2_RE = re.compile(r"^##\s+(.*?)\s*$", re.MULTILINE)
_WIKILINK_RE = re.compile(r"\[\[([^\]|#]+)(?:\|([^\]]+))?\]\]")
_DATAVIEW_FENCE_RE = re.compile(r"```\s*dataview[\s\S]*?```", re.IGNORECASE)


def _strip_frontmatter(body: str) -> tuple[str, str]:
    """Split ``body`` into (frontmatter_block, content).

    The frontmatter_block includes the ``---`` fences so we can reattach
    it verbatim when writing back. If no frontmatter, returns ("", body).
    """
    m = _FRONTMATTER_RE.match(body)
    if m is None:
        return ("", body)
    return (body[: m.end()], body[m.end() :])


@dataclass
class MocSection:
    heading: str  # exact text without leading "## "
    body: str  # lines between this heading and the next
    wikilink_targets: list[str]  # in document order, pre-aliased target


@dataclass
class MocStructure:
    frontmatter: str
    preamble: str  # content before the first ##
    sections: list[MocSection]
    trailing: str  # content after the last section (rare)


def parse_moc_sections(body: str) -> MocStructure:
    """Parse a MOC body into its structural parts."""
    frontmatter, content = _strip_frontmatter(body)
    lines = content.splitlines()

    preamble_lines: list[str] = []
    current_heading: str | None = None
    current_body: list[str] = []
    sections: list[MocSection] = []

    def _flush() -> None:
        if current_heading is None:
            return
        body_text = "\n".join(current_body).rstrip()
        targets = [m.group(1).strip() for m in _WIKILINK_RE.finditer(body_text)]
        sections.append(
            MocSection(
                heading=current_heading, body=body_text, wikilink_targets=targets
            )
        )

    for line in lines:
        m = _H2_RE.match(line)
        if m:
            _flush()
            current_heading = m.group(1).strip()
            current_body = []
        else:
            if current_heading is None:
                preamble_lines.append(line)
            else:
                current_body.append(line)
    _flush()

    return MocStructure(
        frontmatter=frontmatter,
        preamble="\n".join(preamble_lines).rstrip(),
        sections=sections,
        trailing="",
    )


def is_dataview_moc(body: str) -> bool:
    """True when the MOC body contains a dataview-generated code fence.

    Adding static wikilinks to a dataview-generated MOC breaks its
    regeneration pattern — skip these.
    """
    _, content = _strip_frontmatter(body)
    return bool(_DATAVIEW_FENCE_RE.search(content))


def _is_alphabetical(targets: Iterable[str]) -> bool:
    """Best-effort: is the iterable in case-insensitive alphabetical order?"""
    items = [t.lower() for t in targets]
    return items == sorted(items)


def insert_link_alphabetically(
    body: str, heading: str, new_target: str, *, alias: str | None = None
) -> str:
    """Insert a wikilink to ``new_target`` in the named ``##`` section.

    Preserves existing order: if the section's current links look
    alphabetical we insert alphabetically; otherwise we append to the
    end. The caller is responsible for deciding which section the link
    belongs in.

    Raises ``ValueError`` if the section doesn't exist or if the body is
    dataview-generated.
    """
    if is_dataview_moc(body):
        raise ValueError("cannot insert into a dataview-generated MOC")

    structure = parse_moc_sections(body)
    target_section = next(
        (s for s in structure.sections if s.heading == heading), None
    )
    if target_section is None:
        raise ValueError(f"section {heading!r} not found in MOC")

    wikilink = (
        f"[[{new_target}|{alias}]]" if alias else f"[[{new_target}]]"
    )

    # Parse the section's body into lines so we can place the bullet.
    body_lines = target_section.body.split("\n") if target_section.body else []
    bullet = f"- {wikilink}"

    # Already present?
    if any(new_target in ln for ln in body_lines):
        return body  # idempotent

    # Decide placement.
    if _is_alphabetical(target_section.wikilink_targets) and target_section.wikilink_targets:
        # Insert before the first bullet whose target sorts after ours.
        inserted = False
        new_lines: list[str] = []
        for ln in body_lines:
            m = _WIKILINK_RE.search(ln)
            if not inserted and m and m.group(1).lower() > new_target.lower():
                new_lines.append(bullet)
                inserted = True
            new_lines.append(ln)
        if not inserted:
            new_lines.append(bullet)
        body_lines = new_lines
    else:
        body_lines.append(bullet)

    new_section_body = "\n".join(body_lines).rstrip()
    return _rebuild_moc(structure, heading, new_section_body)


def _rebuild_moc(
    structure: MocStructure, replaced_heading: str, new_body: str
) -> str:
    """Reassemble a MOC body after editing one section."""
    parts: list[str] = []
    if structure.frontmatter:
        parts.append(structure.frontmatter.rstrip() + "\n")
    if structure.preamble.strip():
        parts.append(structure.preamble.rstrip() + "\n\n")
    for section in structure.sections:
        parts.append(f"## {section.heading}\n")
        body = new_body if section.heading == replaced_heading else section.body
        if body:
            parts.append(body.rstrip() + "\n")
        parts.append("\n")
    return "".join(parts).rstrip() + "\n"


@dataclass
class MocProposal:
    """LLM-produced proposal; ``render_new_moc`` turns it into a ``.md`` body."""

    subject: str
    intro: str
    sections: list[tuple[str, list[str]]]  # [(heading, [target, ...]), ...]

    def filename(self) -> str:
        return NEW_MOC_FILENAME_TEMPLATE.format(subject=self.subject)


def render_new_moc(proposal: MocProposal) -> str:
    """Render a ``MocProposal`` into the canonical MOC body.

    Uses the vault's convention:
      * ``tags: [📝/moc]`` frontmatter
      * One-paragraph intro above the first ##
      * ``## {heading}`` section with each linked note as a bullet, alphabetized
    """
    lines = [
        "---",
        "tags:",
        "  - 📝/moc",
        "---",
        "",
        f"# {proposal.subject}",
        "",
        proposal.intro.strip(),
        "",
    ]
    for heading, targets in proposal.sections:
        lines.append(f"## {heading}")
        for target in sorted(targets, key=str.lower):
            lines.append(f"- [[{target}]]")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def basename_from_path(p: Path | str) -> str:
    """Cross-OS extraction of a note basename (no .md, no directories)."""
    return Path(p).stem
