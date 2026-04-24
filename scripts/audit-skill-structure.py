#!/usr/bin/env python3
"""
Audit SKILL.md files for overlap, split-pressure, and consolidation candidates.

Complements existing audits — `plugin-compliance-check.sh` owns frontmatter,
size, and body corruption; `audit-skill-descriptions.py` owns trigger-phrase
presence; `/health:agentic-audit` owns CLI-flag compactness. This audit fills
the remaining gap: **skill-to-skill** relationships.

Outputs four artefacts under ``tmp/skill-audit/``:

  report.json                   canonical machine-readable output
  summary.md                    top-N by severity, intended for triage
  overlap-clusters.md           side-by-side description comparison per cluster
  split-candidates.md           quantitative evidence per oversized skill
  consolidation-candidates.md   conservative merge suggestions

Usage:
    python scripts/audit-skill-structure.py
    python scripts/audit-skill-structure.py --plugin configure-plugin
    python scripts/audit-skill-structure.py --strict
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "tmp" / "skill-audit"

# --- Heuristic thresholds (documented in REFERENCE.md) ----------------------

WARN_LINES = 400
ERROR_LINES = 500
TABLE_BLOCK_WARN = 80
FENCED_CODE_WARN = 100
EXAMPLE_BLOCK_COUNT = 5
EXAMPLE_BLOCK_LINES = 120
OVERLAP_SIMILARITY = 0.60
CONSOLIDATION_SIMILARITY = 0.70
CONSOLIDATION_MAX_LINES = 100

STOPWORDS = frozenset(
    """
    a an and or the of to for with in on at by from as is are be use used using
    when user users asks want wants ask asking need needs requires requirement
    this that these those it its skill use-when such skills command commands
    mentions mention provides provide provided can will would should may might
    also etc via into over up all any each every some other another same more
    less less-than greater-than between before after during while if then else
    new existing your their my our they them he she his her its we i you
    support supports supporting across against including include included
    make makes made do does doing done have has had get gets got set sets
    configure configured configuring run running runs based uses using
    check checks checking
    """.split()
)

# --- Data classes -----------------------------------------------------------


@dataclass
class Skill:
    plugin: str
    skill: str
    path: Path
    rel_path: str
    lines: int
    fenced_lines: int
    table_lines: int
    example_blocks: int
    example_lines: int
    largest_table: int
    has_reference: bool
    has_scripts: bool
    has_examples_dir: bool
    description: str
    trigger_tokens: frozenset[str]


@dataclass
class SplitFinding:
    skill: Skill
    reason: str
    severity: str  # "warn" | "error"


@dataclass
class Cluster:
    key: str
    basis: str  # "prefix" | "suffix"
    skills: list[Skill] = field(default_factory=list)
    pairs: list[dict] = field(default_factory=list)


# --- Frontmatter extraction (stdlib-only) -----------------------------------

_FM_FIELD_RE = re.compile(
    r"^(?P<key>[\w-]+):\s*(?P<value>.*?)(?=^[\w-]+:\s|^---\s*$|\Z)",
    re.MULTILINE | re.DOTALL,
)


def _strip_block_scalar(value: str) -> str:
    value = value.rstrip()
    if not value:
        return ""
    if value.lstrip().startswith(("|", ">")):
        lines = value.splitlines()[1:]
        return " ".join(line.strip() for line in lines if line.strip())
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return " ".join(line.strip() for line in value.splitlines() if line.strip())


def extract_description(text: str) -> str:
    if not text.startswith("---"):
        return ""
    parts = text.split("\n---", 1)
    if len(parts) < 2:
        return ""
    fm_text = parts[0].lstrip("-").lstrip("\n")
    for m in _FM_FIELD_RE.finditer(fm_text):
        if m.group("key") == "description":
            return _strip_block_scalar(m.group("value"))
    return ""


# --- Body analysis ----------------------------------------------------------

_FENCE_RE = re.compile(r"^```")
_TABLE_ROW_RE = re.compile(r"^\s*\|")
_EXAMPLE_HEADING_RE = re.compile(r"^#{2,4}\s+.*example", re.IGNORECASE)


def analyze_body(text: str) -> dict:
    """Scan the markdown body for fenced code, table blocks, and example sections."""
    body = text
    if text.startswith("---"):
        parts = text.split("\n---", 2)
        if len(parts) >= 3:
            body = parts[2]

    lines = body.splitlines()
    fenced_lines = 0
    table_lines = 0
    largest_table = 0
    current_table = 0
    in_fence = False
    example_blocks = 0
    example_lines = 0
    in_example = False
    example_heading_level = 0

    for line in lines:
        if _FENCE_RE.match(line):
            in_fence = not in_fence
            fenced_lines += 1  # count the fence line
            continue
        if in_fence:
            fenced_lines += 1
            if in_example:
                example_lines += 1
            continue

        if _TABLE_ROW_RE.match(line):
            table_lines += 1
            current_table += 1
            largest_table = max(largest_table, current_table)
        else:
            current_table = 0

        stripped = line.strip()
        if stripped.startswith("#"):
            heading_hashes = len(stripped) - len(stripped.lstrip("#"))
            if _EXAMPLE_HEADING_RE.match(stripped):
                if in_example:
                    # nested example heading — keep counting under the outer
                    pass
                else:
                    in_example = True
                    example_heading_level = heading_hashes
                    example_blocks += 1
            elif in_example and heading_hashes <= example_heading_level:
                in_example = False
                example_heading_level = 0

        if in_example:
            example_lines += 1

    return {
        "fenced_lines": fenced_lines,
        "table_lines": table_lines,
        "largest_table": largest_table,
        "example_blocks": example_blocks,
        "example_lines": example_lines,
        "total_lines": len(lines),
    }


# --- Skill discovery --------------------------------------------------------


def find_skills(root: Path, plugin_filter: str | None) -> list[Path]:
    skills: list[Path] = []
    for plugin_dir in sorted(root.glob("*-plugin")):
        if not plugin_dir.is_dir():
            continue
        if plugin_filter and plugin_dir.name != plugin_filter:
            continue
        skills_dir = plugin_dir / "skills"
        if not skills_dir.is_dir():
            continue
        for skill_md in sorted(skills_dir.rglob("SKILL.md")):
            skills.append(skill_md)
        for skill_md in sorted(skills_dir.rglob("skill.md")):
            if skill_md.parent not in {s.parent for s in skills}:
                skills.append(skill_md)
    return skills


def load_skill(path: Path, root: Path) -> Skill:
    text = path.read_text(encoding="utf-8", errors="replace")
    body = analyze_body(text)
    description = extract_description(text)
    trigger_tokens = tokenize(description)
    parent = path.parent
    rel_path = str(path.relative_to(root))
    plugin = path.relative_to(root).parts[0]
    scripts_dir = parent / "scripts"
    examples_dir = parent / "examples"
    return Skill(
        plugin=plugin,
        skill=parent.name,
        path=path,
        rel_path=rel_path,
        lines=len(text.splitlines()),
        fenced_lines=body["fenced_lines"],
        table_lines=body["table_lines"],
        example_blocks=body["example_blocks"],
        example_lines=body["example_lines"],
        largest_table=body["largest_table"],
        has_reference=(parent / "REFERENCE.md").is_file(),
        has_scripts=scripts_dir.is_dir() and any(scripts_dir.iterdir()),
        has_examples_dir=examples_dir.is_dir() and any(examples_dir.iterdir()),
        description=description,
        trigger_tokens=trigger_tokens,
    )


# --- Tokenization & similarity ---------------------------------------------

_TOKEN_RE = re.compile(r"[a-z][a-z0-9-]+")


def tokenize(text: str) -> frozenset[str]:
    if not text:
        return frozenset()
    tokens = _TOKEN_RE.findall(text.lower())
    return frozenset(t for t in tokens if t not in STOPWORDS and len(t) > 2)


def jaccard(a: frozenset[str], b: frozenset[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


# --- Cluster detection ------------------------------------------------------


def prefix_of(slug: str) -> str:
    parts = slug.split("-")
    return parts[0] if parts else slug


def suffix_of(slug: str) -> str:
    parts = slug.split("-")
    return parts[-1] if parts else slug


def stem(word: str) -> str:
    """Fold ``-s``/``-es``/``-ing`` so tests/testing/test collapse to 'test'."""
    if len(word) > 5 and word.endswith("ing"):
        return word[:-3]
    if len(word) > 4 and word.endswith("es"):
        return word[:-2]
    if len(word) > 3 and word.endswith("s") and not word.endswith("ss"):
        return word[:-1]
    return word


def plugin_stem(plugin: str) -> str:
    """Plugin name stem: 'configure-plugin' → 'configure'."""
    return plugin.removesuffix("-plugin")


def distinctive_prefix(skill: Skill) -> str:
    """First name component that isn't the plugin's own stem."""
    parts = skill.skill.split("-")
    stem = plugin_stem(skill.plugin)
    for p in parts:
        if p != stem:
            return p
    return parts[0] if parts else skill.skill


def score_pairs(members: list[Skill]) -> list[dict]:
    """Pairwise scoring within a cluster. Returns only pairs >= threshold."""
    pairs: list[dict] = []
    for i, a in enumerate(members):
        for b in members[i + 1 :]:
            sim = jaccard(a.trigger_tokens, b.trigger_tokens)
            first_a = (a.description.split(".")[0] or "").strip().lower()
            first_b = (b.description.split(".")[0] or "").strip().lower()
            identical_first = bool(first_a) and first_a == first_b
            if sim >= OVERLAP_SIMILARITY or identical_first:
                pairs.append(
                    {
                        "a": a.rel_path,
                        "b": b.rel_path,
                        "similarity": round(sim, 3),
                        "identical_first_sentence": identical_first,
                    }
                )
    return pairs


def build_clusters(skills: list[Skill]) -> list[Cluster]:
    """Emit clusters when ≥3 skills share a meaningful name component.

    Three cluster bases — deliberately redundant so a single skill may appear
    in multiple clusters (triage signal, not disjoint partition):

    - ``plugin-prefix`` — within one plugin, skills sharing their distinctive
      first name component (first component that is not the plugin stem).
    - ``suffix`` — globally, skills sharing their last name component,
      provided ≥2 plugins are represented.
    - ``shared-token`` — globally, skills sharing any other name component
      that occurs in ≥4 skills across ≥2 plugins.
    """
    clusters: list[Cluster] = []

    # Per-plugin distinctive-prefix clusters
    by_pp: dict[tuple[str, str], list[Skill]] = {}
    for s in skills:
        by_pp.setdefault((s.plugin, distinctive_prefix(s)), []).append(s)
    for (plugin, key), members in sorted(by_pp.items()):
        if len(members) < 3:
            continue
        clusters.append(
            Cluster(
                key=f"{plugin}:{key}-*",
                basis="plugin-prefix",
                skills=members,
                pairs=score_pairs(members),
            )
        )

    seen_member_sets: set[frozenset[str]] = {
        frozenset(s.rel_path for s in c.skills) for c in clusters
    }

    # Global suffix clusters (spanning ≥2 plugins, with s/ing stemming)
    by_suffix: dict[str, list[Skill]] = {}
    for s in skills:
        by_suffix.setdefault(stem(suffix_of(s.skill)), []).append(s)
    for key, members in sorted(by_suffix.items()):
        if len(members) < 3:
            continue
        if len({s.plugin for s in members}) < 2:
            continue
        member_set = frozenset(s.rel_path for s in members)
        if member_set in seen_member_sets:
            continue
        seen_member_sets.add(member_set)
        clusters.append(
            Cluster(
                key=f"*-{key}*",
                basis="suffix",
                skills=members,
                pairs=score_pairs(members),
            )
        )

    # Global shared-token clusters (other name components, stemmed)
    token_index: dict[str, list[Skill]] = {}
    for s in skills:
        for part in {stem(p) for p in s.skill.split("-")}:
            token_index.setdefault(part, []).append(s)
    for token, members in sorted(token_index.items()):
        if len(members) < 4:
            continue
        if len({s.plugin for s in members}) < 2:
            continue
        # Skip tokens already covered by a prefix/suffix cluster
        member_set = frozenset(s.rel_path for s in members)
        if member_set in seen_member_sets:
            continue
        # Skip tokens equal to any plugin stem (e.g. 'configure', 'blueprint')
        if any(token == plugin_stem(s.plugin) for s in members):
            continue
        seen_member_sets.add(member_set)
        clusters.append(
            Cluster(
                key=f"*{token}*",
                basis="shared-token",
                skills=members,
                pairs=score_pairs(members),
            )
        )

    return clusters


def ambiguous_within_cluster(cluster: Cluster) -> list[dict]:
    """Skills whose tokens are fully covered by a sibling's — no distinguisher."""
    findings = []
    for skill in cluster.skills:
        for sibling in cluster.skills:
            if sibling is skill:
                continue
            if skill.trigger_tokens and skill.trigger_tokens <= sibling.trigger_tokens:
                findings.append(
                    {
                        "skill": skill.rel_path,
                        "dominated_by": sibling.rel_path,
                    }
                )
                break
    return findings


# --- Split-candidate detection ---------------------------------------------


def split_candidates(skill: Skill) -> list[SplitFinding]:
    findings: list[SplitFinding] = []
    if skill.lines > ERROR_LINES and not skill.has_reference:
        findings.append(
            SplitFinding(
                skill,
                f"{skill.lines} lines and no sibling REFERENCE.md",
                "error",
            )
        )
    elif skill.lines > WARN_LINES and not skill.has_reference:
        findings.append(
            SplitFinding(
                skill,
                f"{skill.lines} lines and no sibling REFERENCE.md",
                "warn",
            )
        )
    if skill.largest_table > TABLE_BLOCK_WARN and not skill.has_reference:
        findings.append(
            SplitFinding(
                skill,
                f"contiguous table block of {skill.largest_table} lines "
                "→ extract to REFERENCE.md",
                "warn",
            )
        )
    if skill.fenced_lines > FENCED_CODE_WARN and not skill.has_scripts:
        findings.append(
            SplitFinding(
                skill,
                f"{skill.fenced_lines} fenced-code lines "
                "→ consider scripts/ directory",
                "warn",
            )
        )
    if (
        skill.example_blocks >= EXAMPLE_BLOCK_COUNT
        and skill.example_lines > EXAMPLE_BLOCK_LINES
        and not skill.has_examples_dir
    ):
        findings.append(
            SplitFinding(
                skill,
                f"{skill.example_blocks} example blocks totalling "
                f"{skill.example_lines} lines → consider examples/ directory",
                "warn",
            )
        )
    return findings


# --- Consolidation-candidate detection -------------------------------------


def consolidation_candidates(skills: list[Skill]) -> list[dict]:
    out = []
    by_plugin_prefix: dict[tuple[str, str], list[Skill]] = {}
    for s in skills:
        by_plugin_prefix.setdefault((s.plugin, prefix_of(s.skill)), []).append(s)
    for (plugin, prefix), group in by_plugin_prefix.items():
        small = [s for s in group if s.lines < CONSOLIDATION_MAX_LINES]
        if len(small) < 2:
            continue
        for i, a in enumerate(small):
            for b in small[i + 1 :]:
                sim = jaccard(a.trigger_tokens, b.trigger_tokens)
                if sim >= CONSOLIDATION_SIMILARITY:
                    out.append(
                        {
                            "plugin": plugin,
                            "prefix": prefix,
                            "skills": [a.rel_path, b.rel_path],
                            "similarity": round(sim, 3),
                            "combined_lines": a.lines + b.lines,
                            "rationale": (
                                f"Both under {CONSOLIDATION_MAX_LINES} lines, "
                                f"same prefix '{prefix}', Jaccard {sim:.2f}"
                            ),
                        }
                    )
    return out


# --- Report rendering -------------------------------------------------------


def render_summary(
    skills: list[Skill],
    splits: list[SplitFinding],
    clusters: list[Cluster],
    consolidations: list[dict],
) -> str:
    errors = [f for f in splits if f.severity == "error"]
    warns = [f for f in splits if f.severity == "warn"]
    lines = [
        "# Skill Audit Summary",
        "",
        f"Scanned **{len(skills)}** skills across "
        f"**{len({s.plugin for s in skills})}** plugins.",
        "",
        "## Counts",
        "",
        "| Category | Count |",
        "|----------|-------|",
        f"| Split candidates (error) | {len(errors)} |",
        f"| Split candidates (warn) | {len(warns)} |",
        f"| Overlap clusters | {len(clusters)} |",
        f"| Overlap pairs | {sum(len(c.pairs) for c in clusters)} |",
        f"| Consolidation candidates | {len(consolidations)} |",
        "",
        "## Top split candidates (error tier)",
        "",
    ]
    if errors:
        lines.append("| Skill | Lines | Reason |")
        lines.append("|-------|------:|--------|")
        for f in sorted(errors, key=lambda f: -f.skill.lines)[:20]:
            lines.append(
                f"| `{f.skill.rel_path}` | {f.skill.lines} | {f.reason} |"
            )
    else:
        lines.append("_None._")
    lines += ["", "## Largest overlap clusters", ""]
    if clusters:
        lines.append("| Cluster | Basis | Members | Pairs flagged |")
        lines.append("|---------|-------|--------:|--------------:|")
        for c in sorted(clusters, key=lambda c: (-len(c.pairs), -len(c.skills)))[:10]:
            lines.append(
                f"| `{c.key}` | {c.basis} | {len(c.skills)} | {len(c.pairs)} |"
            )
    else:
        lines.append("_None._")
    lines += [
        "",
        "## Output files",
        "",
        "- `report.json` — canonical machine-readable output",
        "- `overlap-clusters.md` — per-cluster detail",
        "- `split-candidates.md` — per-skill detail",
        "- `consolidation-candidates.md` — merge suggestions",
        "",
    ]
    return "\n".join(lines)


def render_overlap_clusters(clusters: list[Cluster]) -> str:
    out = ["# Overlap Clusters", ""]
    if not clusters:
        out.append("_No clusters flagged._")
        return "\n".join(out)
    out.append(
        "Clusters are groups of skills sharing a name prefix or suffix where "
        "at least one pair has Jaccard token similarity ≥ "
        f"{OVERLAP_SIMILARITY:.2f} or an identical first-sentence description."
    )
    out.append("")
    for cluster in sorted(clusters, key=lambda c: (-len(c.pairs), c.key)):
        out.append(f"## `{cluster.key}` ({cluster.basis})")
        out.append("")
        out.append("| Skill | Description (first ~120 chars) |")
        out.append("|-------|--------------------------------|")
        for s in sorted(cluster.skills, key=lambda s: s.skill):
            preview = " ".join(s.description.split())
            if len(preview) > 120:
                preview = preview[:117] + "..."
            preview = preview.replace("|", "\\|")
            out.append(f"| `{s.rel_path}` | {preview} |")
        out.append("")
        out.append("**Flagged pairs:**")
        out.append("")
        out.append("| A | B | Similarity | Identical first sentence |")
        out.append("|---|---|-----------:|:------------------------:|")
        for pair in sorted(cluster.pairs, key=lambda p: -p["similarity"]):
            out.append(
                f"| `{pair['a']}` | `{pair['b']}` | {pair['similarity']} "
                f"| {'yes' if pair['identical_first_sentence'] else 'no'} |"
            )
        ambiguous = ambiguous_within_cluster(cluster)
        if ambiguous:
            out.append("")
            out.append("**Ambiguity markers** (description tokens dominated by a sibling):")
            out.append("")
            for a in ambiguous:
                out.append(f"- `{a['skill']}` dominated by `{a['dominated_by']}`")
        out.append("")
    return "\n".join(out)


def render_split_candidates(splits: list[SplitFinding]) -> str:
    out = ["# Split Candidates", ""]
    if not splits:
        out.append("_None._")
        return "\n".join(out)
    out.append(
        f"Thresholds: `warn` at {WARN_LINES} lines, `error` at {ERROR_LINES} "
        f"lines (when no REFERENCE.md exists). Tables > {TABLE_BLOCK_WARN} "
        f"contiguous rows, fenced-code > {FENCED_CODE_WARN} lines, and example "
        "clusters are surfaced as supporting evidence."
    )
    out.append("")
    out.append("| Severity | Skill | Lines | Tables | Fenced | Examples | Reason |")
    out.append("|----------|-------|------:|-------:|-------:|---------:|--------|")
    for f in sorted(splits, key=lambda f: (f.severity != "error", -f.skill.lines)):
        s = f.skill
        out.append(
            f"| {f.severity} | `{s.rel_path}` | {s.lines} | "
            f"{s.largest_table} | {s.fenced_lines} | {s.example_blocks} "
            f"| {f.reason} |"
        )
    return "\n".join(out)


def render_consolidations(consolidations: list[dict]) -> str:
    out = ["# Consolidation Candidates", ""]
    if not consolidations:
        out.append("_None._")
        return "\n".join(out)
    out.append(
        "Pairs where both skills are small, share a name prefix inside the "
        "same plugin, and have high description similarity. Merging is "
        "editorial — these are surfaced for human review only."
    )
    out.append("")
    out.append("| Plugin | Prefix | Skills | Similarity | Combined lines |")
    out.append("|--------|--------|--------|-----------:|---------------:|")
    for c in sorted(consolidations, key=lambda c: -c["similarity"]):
        skills_cell = "<br>".join(f"`{s}`" for s in c["skills"])
        out.append(
            f"| {c['plugin']} | {c['prefix']} | {skills_cell} "
            f"| {c['similarity']} | {c['combined_lines']} |"
        )
    return "\n".join(out)


# --- JSON emission ----------------------------------------------------------


def build_json(
    skills: list[Skill],
    splits: list[SplitFinding],
    clusters: list[Cluster],
    consolidations: list[dict],
) -> dict:
    return {
        "skills": [
            {
                "plugin": s.plugin,
                "skill": s.skill,
                "path": s.rel_path,
                "lines": s.lines,
                "fenced_lines": s.fenced_lines,
                "table_lines": s.table_lines,
                "largest_table": s.largest_table,
                "example_blocks": s.example_blocks,
                "example_lines": s.example_lines,
                "has_reference": s.has_reference,
                "has_scripts": s.has_scripts,
                "has_examples_dir": s.has_examples_dir,
                "description": s.description,
            }
            for s in skills
        ],
        "overlap_clusters": [
            {
                "cluster": c.key,
                "basis": c.basis,
                "members": [s.rel_path for s in c.skills],
                "pairs": c.pairs,
                "ambiguous": ambiguous_within_cluster(c),
            }
            for c in clusters
        ],
        "split_candidates": [
            {
                "skill": f.skill.rel_path,
                "lines": f.skill.lines,
                "reason": f.reason,
                "severity": f.severity,
            }
            for f in splits
        ],
        "consolidation_candidates": consolidations,
        "thresholds": {
            "warn_lines": WARN_LINES,
            "error_lines": ERROR_LINES,
            "table_block_warn": TABLE_BLOCK_WARN,
            "fenced_code_warn": FENCED_CODE_WARN,
            "example_block_count": EXAMPLE_BLOCK_COUNT,
            "example_block_lines": EXAMPLE_BLOCK_LINES,
            "overlap_similarity": OVERLAP_SIMILARITY,
            "consolidation_similarity": CONSOLIDATION_SIMILARITY,
            "consolidation_max_lines": CONSOLIDATION_MAX_LINES,
        },
    }


# --- Main -------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plugin",
        help="Restrict analysis to a single plugin (e.g. configure-plugin)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero on any finding (warn or error). Default exit is 0.",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=REPO_ROOT,
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args()

    root = args.root.resolve()
    skill_paths = find_skills(root, args.plugin)
    skills = [load_skill(p, root) for p in skill_paths]

    splits = [f for s in skills for f in split_candidates(s)]
    clusters = build_clusters(skills)
    consolidations = consolidation_candidates(skills)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / "report.json").write_text(
        json.dumps(
            build_json(skills, splits, clusters, consolidations),
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    (OUTPUT_DIR / "summary.md").write_text(
        render_summary(skills, splits, clusters, consolidations) + "\n",
        encoding="utf-8",
    )
    (OUTPUT_DIR / "overlap-clusters.md").write_text(
        render_overlap_clusters(clusters) + "\n",
        encoding="utf-8",
    )
    (OUTPUT_DIR / "split-candidates.md").write_text(
        render_split_candidates(splits) + "\n",
        encoding="utf-8",
    )
    (OUTPUT_DIR / "consolidation-candidates.md").write_text(
        render_consolidations(consolidations) + "\n",
        encoding="utf-8",
    )

    errors = [f for f in splits if f.severity == "error"]
    warns = [f for f in splits if f.severity == "warn"]

    print(
        f"Scanned {len(skills)} skills. "
        f"Split: {len(errors)} error / {len(warns)} warn. "
        f"Clusters: {len(clusters)}. "
        f"Consolidations: {len(consolidations)}.",
        file=sys.stderr,
    )
    print(f"Reports written to {OUTPUT_DIR.relative_to(REPO_ROOT)}/", file=sys.stderr)

    if args.strict and (errors or warns):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
