"""Rewrite FVH/z stubs to the canonical redirect-body shape.

Deterministic functions in this module:

  * ``rewrite_broken_redirects`` — turns ``broken_redirect`` files
    (already tagged ``redirect`` but with a stale body) into the canonical
    redirect stub.

  * ``section_headings`` — parse the ``##`` headings from a markdown body.

  * ``unique_sections`` — given two note contents, return the headings
    whose bodies in the source aren't substantively present in the
    destination.

  * ``verify_canonical_phrase_present`` — safety check used by the
    vault-stubs subagent before overwriting a stale_duplicate with the
    canonical redirect: returns False if no canonical phrase from the
    source exists in the destination, signalling that the merge step was
    skipped or incomplete.

Stale-duplicate merging itself is handled by the LLM-backed vault-stubs
subagent (see ``prompts/vault_stubs.md``); these helpers give the agent
a deterministic checklist to call via Bash.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

from vault_agent.analyzers.stubs import StubClass, analyze_stubs
from vault_agent.analyzers.vault_index import VaultIndex


CANONICAL_REDIRECT_TEMPLATE = """---
tags: [redirect]
context: fvh
---
See [[Zettelkasten/{basename}|{basename}]] in the main knowledge base.
"""


_FRONTMATTER_RE = re.compile(
    r"\A\s*---\n(.*?)\n---\n", re.DOTALL
)

_H2_RE = re.compile(r"^##\s+(.*?)\s*$", re.MULTILINE)


def _strip_frontmatter(body: str) -> str:
    """Drop YAML frontmatter from a markdown string."""
    m = _FRONTMATTER_RE.match(body)
    return body[m.end() :] if m else body


def section_headings(body: str) -> list[str]:
    """Return the list of ``##``-level headings in a markdown body.

    Frontmatter is stripped first so we don't match YAML content.
    """
    stripped = _strip_frontmatter(body)
    return [m.group(1).strip() for m in _H2_RE.finditer(stripped)]


def _section_bodies(body: str) -> dict[str, str]:
    """Parse ``##`` sections into a mapping of heading → body text.

    Frontmatter is stripped. Content before the first ``##`` is returned
    under the key ``""`` (empty). Trailing whitespace is trimmed.
    """
    stripped = _strip_frontmatter(body)
    sections: dict[str, str] = {}
    current_heading = ""
    current_lines: list[str] = []
    for line in stripped.splitlines():
        m = _H2_RE.match(line)
        if m:
            sections[current_heading] = "\n".join(current_lines).strip()
            current_heading = m.group(1).strip()
            current_lines = []
        else:
            current_lines.append(line)
    sections[current_heading] = "\n".join(current_lines).strip()
    return sections


_MARKDOWN_NOISE_RE = re.compile(r"[#*_\[\]()`>|-]+")


def _normalize(text: str) -> str:
    """Whitespace-normalize for coarse substantive-equality comparison."""
    return re.sub(r"\s+", " ", text).strip().lower()


def _meaningful_tokens(text: str) -> list[str]:
    """Like ``_normalize`` but strips markdown syntactic noise first.

    Used by the phrase-presence check so that a near-empty source like
    ``# Foo`` — which normalizes to two tokens but has zero semantic
    content — is treated as having nothing to verify.
    """
    stripped = _MARKDOWN_NOISE_RE.sub(" ", text)
    return [tok for tok in _normalize(stripped).split() if tok]


def unique_sections(source_body: str, destination_body: str) -> list[str]:
    """Return headings in ``source_body`` whose content isn't in ``destination_body``.

    "Isn't in" means the normalized section text doesn't appear anywhere
    in the destination, not even as a sub-paragraph. Intentionally coarse:
    the goal is to surface headings the LLM should consider merging, not
    to prove exact duplication.
    """
    dest_normal = _normalize(destination_body)
    out: list[str] = []
    for heading, body in _section_bodies(source_body).items():
        if not heading:
            continue
        body_normal = _normalize(body)
        if not body_normal:
            continue
        if body_normal not in dest_normal:
            out.append(heading)
    return out


def verify_canonical_phrase_present(
    source_body: str, destination_body: str, *, min_phrase_words: int = 5
) -> bool:
    """Safety check: at least one substantive phrase from ``source`` is in ``destination``.

    The vault-stubs subagent calls this before overwriting a
    ``stale_duplicate`` with the canonical redirect. If it returns
    ``False``, the merge step either was skipped or failed to land —
    abort the overwrite.

    "Phrase" = a run of ``min_phrase_words`` or more consecutive words
    after normalization. We require at least one such phrase to appear
    verbatim in the destination.
    """
    src_words = _meaningful_tokens(source_body)
    if len(src_words) < min_phrase_words:
        # Near-empty source (e.g. `# Foo` with no body) — nothing
        # substantive to verify; pass vacuously rather than block.
        return True

    dest_normal = _normalize(destination_body)
    for i in range(len(src_words) - min_phrase_words + 1):
        phrase = " ".join(src_words[i : i + min_phrase_words])
        if phrase in dest_normal:
            return True
    return False


def body_digest(body: str) -> str:
    """Stable sha256 digest of the body content for reproducible diffing."""
    return hashlib.sha256(_normalize(body).encode("utf-8")).hexdigest()[:16]


@dataclass
class StubRewriteResult:
    path: Path
    changed: bool
    previous_size: int


def rewrite_broken_redirects(index: VaultIndex) -> list[StubRewriteResult]:
    """Rewrite ``broken_redirect`` files to canonical redirect shape."""
    report = analyze_stubs(index)
    results: list[StubRewriteResult] = []
    for cls in report.classifications:
        if cls.cls != StubClass.BROKEN_REDIRECT:
            continue
        if cls.canonical_path is None:
            # Shouldn't happen for BROKEN_REDIRECT with a matching note, but
            # guard just in case.
            continue
        basename = cls.canonical_path.stem
        previous_size = cls.size_bytes
        new_body = CANONICAL_REDIRECT_TEMPLATE.format(basename=basename)
        cls.path.write_text(new_body, encoding="utf-8")
        results.append(
            StubRewriteResult(
                path=cls.path, changed=True, previous_size=previous_size
            )
        )
    return results
