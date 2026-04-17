"""Rewrite FVH/z stubs to the canonical redirect-body shape.

Only applies to files classified as ``broken_redirect`` (already has
``redirect`` tag, but body is wrong). Stale-duplicate consolidation
requires per-file content judgment and is handled by the LLM-backed
vault-stubs subagent, not here.
"""

from __future__ import annotations

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
