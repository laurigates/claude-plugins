"""Broken-wikilink rewriter driven by an explicit rule table.

Rewrites `[[Old]]` → `[[New]]` (preserving alias and section syntax)
across every note. Only applies rules where the OLD target is broken
AND the NEW target resolves uniquely in the current vault — this keeps
the rule table immune to stale rules.

Also exports ``unqualify_kanban_links`` which rewrites `[[Kanban/X]]`
to `[[X]]` when the basename is unique.

## LLM-backed helpers (#1073)

For low-leverage broken targets the rule table doesn't cover (e.g.
``[[CICD]]``, ``[[ESP32 MOC]]``), the vault-links subagent calls:

  * :data:`INLINE_TAG_SYNTAX_TARGETS` — basenames that are generic nouns
    users occasionally wrote as ``[[code]]`` or ``[[project]]`` without
    ever creating the target note. Never auto-rewrite; delete or flag.

  * :func:`fuzzy_basename_candidates` — ``difflib``-backed lookup of
    near-matches in the vault's basename index, returning
    ``(basename, ratio)`` tuples above a configurable cutoff.

  * :class:`ConfidenceTier` + :func:`classify_match` — translate a
    similarity score into an action tier (auto / confirm / no-canonical)
    that the subagent uses to decide whether to rewrite, prompt, or
    flag.
"""

from __future__ import annotations

import difflib
import re
from dataclasses import dataclass, field
from enum import Enum
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


# ---------------------------------------------------------------------------
# #1073 — LLM-backed edge-case helpers
# ---------------------------------------------------------------------------


#: Basenames that look like broken wikilinks but were actually inline-tag
#: syntax: e.g. ``[[code]]`` inside a sentence meant as emphasis on the word
#: "code", not a reference to a note. Never auto-rewrite these — the agent
#: prompt tells the LLM to delete the link or flag for user.
INLINE_TAG_SYNTAX_TARGETS: frozenset[str] = frozenset(
    {
        "code",
        "project",
        "software",
        "tool",
        "tools",
        "framework",
        "library",
        "package",
        "service",
        "app",
        "system",
        "platform",
        "language",
    }
)


#: Similarity threshold above which a rewrite is "obvious" enough to auto-apply.
CONFIDENCE_AUTO_THRESHOLD = 0.9
#: Threshold above which we ask the user to confirm.
CONFIDENCE_CONFIRM_THRESHOLD = 0.7


class ConfidenceTier(str, Enum):
    """Action tier for an LLM-proposed rewrite."""

    AUTO = "auto"  # high-confidence — apply without prompting
    CONFIRM = "confirm"  # medium — surface to user
    NO_CANONICAL = "no_canonical"  # no plausible match — offer create/delete
    SKIP = "skip"  # inline-tag syntax or protected — never rewrite


@dataclass(frozen=True)
class BasenameMatch:
    basename: str
    ratio: float


def is_inline_tag_syntax(target: str) -> bool:
    """True when ``target`` is a generic noun better treated as emphasis than a link."""
    return target.strip().lower() in INLINE_TAG_SYNTAX_TARGETS


def fuzzy_basename_candidates(
    target: str, index: VaultIndex, *, cutoff: float = 0.6, limit: int = 5
) -> list[BasenameMatch]:
    """Return the top fuzzy matches for ``target`` in the vault's basenames.

    Uses ``difflib.get_close_matches`` over the full basename index.
    The LLM layer in the subagent can add semantic matching on top of
    this (e.g. via its own judgement or an embeddings call); this
    function is the deterministic floor.
    """
    basenames = list(index.by_basename.keys())
    # get_close_matches is case-sensitive; lower the comparison but keep
    # the original spelling for the return value.
    lower_to_original: dict[str, str] = {}
    for bn in basenames:
        lower_to_original.setdefault(bn.lower(), bn)

    matches = difflib.get_close_matches(
        target.lower(), list(lower_to_original.keys()), n=limit, cutoff=cutoff
    )
    out: list[BasenameMatch] = []
    for m in matches:
        ratio = difflib.SequenceMatcher(None, target.lower(), m).ratio()
        out.append(BasenameMatch(basename=lower_to_original[m], ratio=ratio))
    return out


def classify_match(
    target: str, candidates: list[BasenameMatch]
) -> ConfidenceTier:
    """Map the top candidate's similarity to a :class:`ConfidenceTier`.

    Rules, in order:

      1. ``target`` is inline-tag syntax → :attr:`ConfidenceTier.SKIP`
      2. No candidates → :attr:`ConfidenceTier.NO_CANONICAL`
      3. Top ratio ≥ 0.9 → :attr:`ConfidenceTier.AUTO`
      4. Top ratio ≥ 0.7 → :attr:`ConfidenceTier.CONFIRM`
      5. Otherwise → :attr:`ConfidenceTier.NO_CANONICAL`
    """
    if is_inline_tag_syntax(target):
        return ConfidenceTier.SKIP
    if not candidates:
        return ConfidenceTier.NO_CANONICAL
    top = candidates[0]
    if top.ratio >= CONFIDENCE_AUTO_THRESHOLD:
        return ConfidenceTier.AUTO
    if top.ratio >= CONFIDENCE_CONFIRM_THRESHOLD:
        return ConfidenceTier.CONFIRM
    return ConfidenceTier.NO_CANONICAL


@dataclass
class RewriteProposal:
    """One LLM-proposed broken-link rewrite, with evidence."""

    target: str  # the broken wikilink text
    reference_count: int  # how many wikilinks to this target exist
    candidates: list[BasenameMatch]  # sorted, top-N
    tier: ConfidenceTier

    @property
    def top_canonical(self) -> str | None:
        return self.candidates[0].basename if self.candidates else None

    def to_dict(self) -> dict:
        return {
            "target": self.target,
            "reference_count": self.reference_count,
            "tier": self.tier.value,
            "candidates": [
                {"basename": c.basename, "ratio": round(c.ratio, 3)}
                for c in self.candidates
            ],
            "top_canonical": self.top_canonical,
        }


def propose_rewrites(
    audit_broken: list[tuple[str, int]],
    index: VaultIndex,
    *,
    min_references: int = 3,
) -> list[RewriteProposal]:
    """Compute per-target :class:`RewriteProposal`s for LLM-tier triage.

    ``audit_broken`` is the ``(target, reference_count)`` list from
    ``VaultAudit.links.top_broken(...)``. We filter to targets with at
    least ``min_references`` references (per #1073's threshold) and
    compute candidates + tier for each.
    """
    proposals: list[RewriteProposal] = []
    for target, count in audit_broken:
        if count < min_references:
            continue
        if target in BROKEN_LINK_REWRITES:
            continue  # rule table covers this; skip LLM pass
        candidates = fuzzy_basename_candidates(target, index)
        tier = classify_match(target, candidates)
        proposals.append(
            RewriteProposal(
                target=target,
                reference_count=count,
                candidates=candidates,
                tier=tier,
            )
        )
    return proposals
