"""Broken-wikilink rewriter driven by an explicit rule table.

Rewrites `[[Old]]` → `[[New]]` (preserving alias and section syntax)
across every note. Only applies rules where the OLD target is broken
AND the NEW target resolves uniquely in the current vault — this keeps
the rule table immune to stale rules.

Also exports ``unqualify_kanban_links`` which rewrites `[[Kanban/X]]`
to `[[X]]` when the basename is unique.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from vault_agent.analyzers.vault_index import VaultIndex

# Rule table: broken target → canonical target.
# Sourced from the LakuVault audit; extend as new patterns emerge.
BROKEN_LINK_REWRITES: dict[str, str] = {
    # Top broken target in LakuVault — 44 references
    "AnsibleFVH": "Ansible",
    # Renamed MOC
    "Development MOC": "Development Workflows and Tools MOC",
    "Development Workflows": "Development Workflows and Tools MOC",
}


@dataclass
class LinkPatchResult:
    path: Path
    changed: bool
    per_rule_counts: dict[str, int] = field(default_factory=dict)

    @property
    def total_rewrites(self) -> int:
        return sum(self.per_rule_counts.values())


def _build_wikilink_re(target: str) -> re.Pattern[str]:
    """Regex that matches ``[[target]]``, ``[[target|alias]]``, ``[[target#section]]``.

    The target must match exactly (no partial matches). We preserve the
    optional alias and section suffix by capturing them.
    """
    escaped = re.escape(target)
    # Group 1: section (#...), Group 2: alias (|...)
    return re.compile(
        rf"\[\[{escaped}(#[^\]|]+)?(\|[^\]]+)?\]\]"
    )


def _rewrite_one(body: str, old: str, new: str) -> tuple[str, int]:
    """Apply a single rule to a body; returns (new_body, count)."""
    pattern = _build_wikilink_re(old)
    count = 0

    def repl(match: re.Match[str]) -> str:
        nonlocal count
        count += 1
        section = match.group(1) or ""
        alias = match.group(2) or ""
        return f"[[{new}{section}{alias}]]"

    new_body = pattern.sub(repl, body)
    return new_body, count


def _applicable_rules(
    index: VaultIndex, table: dict[str, str]
) -> dict[str, str]:
    """Keep only rules whose NEW target resolves uniquely in the vault."""
    return {
        old: new
        for old, new in table.items()
        if len(index.resolve(new)) == 1
    }


def apply_rewrites(
    index: VaultIndex, rules: dict[str, str] | None = None
) -> list[LinkPatchResult]:
    """Apply the rule table to every note. Returns per-file results."""
    effective = _applicable_rules(index, rules or BROKEN_LINK_REWRITES)
    results: list[LinkPatchResult] = []
    for note in index.notes:
        new_body = note.body
        counts: dict[str, int] = {}
        for old, new in effective.items():
            new_body, n = _rewrite_one(new_body, old, new)
            if n:
                counts[old] = n
        if new_body == note.body:
            results.append(LinkPatchResult(path=note.path, changed=False))
            continue
        # Write back (preserving frontmatter verbatim).
        raw = note.path.read_text(encoding="utf-8")
        new_raw = raw.replace(note.body, new_body, 1)
        note.path.write_text(new_raw, encoding="utf-8")
        results.append(
            LinkPatchResult(path=note.path, changed=True, per_rule_counts=counts)
        )
    return results


def unqualify_kanban_links(index: VaultIndex) -> list[LinkPatchResult]:
    """Rewrite ``[[Kanban/X]]`` → ``[[X]]`` where ``X`` is a unique basename."""
    results: list[LinkPatchResult] = []
    pattern = re.compile(r"\[\[Kanban/([^\]|#]+)(#[^\]|]+)?(\|[^\]]+)?\]\]")
    for note in index.notes:
        counts: dict[str, int] = {}

        def repl(match: re.Match[str]) -> str:
            basename = match.group(1).strip()
            if len(index.resolve(basename)) != 1:
                return match.group(0)
            counts[f"Kanban/{basename}"] = counts.get(f"Kanban/{basename}", 0) + 1
            section = match.group(2) or ""
            alias = match.group(3) or ""
            return f"[[{basename}{section}{alias}]]"

        new_body = pattern.sub(repl, note.body)
        if new_body == note.body:
            results.append(LinkPatchResult(path=note.path, changed=False))
            continue
        raw = note.path.read_text(encoding="utf-8")
        new_raw = raw.replace(note.body, new_body, 1)
        note.path.write_text(new_raw, encoding="utf-8")
        results.append(
            LinkPatchResult(path=note.path, changed=True, per_rule_counts=counts)
        )
    return results


def summarize_rewrites(results: list[LinkPatchResult]) -> dict[str, int]:
    """Aggregate per-rule counts across all files."""
    totals: dict[str, int] = {}
    for r in results:
        for rule, n in r.per_rule_counts.items():
            totals[rule] = totals.get(rule, 0) + n
    return totals
