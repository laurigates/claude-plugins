#!/usr/bin/env python3
"""summarize.py — roll up canary judgments into per-dimension profiles.

Deliberately does NOT compute a per-skill total, average, or rank. The rubric
(rubric.md, "Read this before scoring anything") forbids aggregation because no
source study varied skill quality as an independent variable, so a total would
imply a ranking the evidence cannot support. This script enforces that
structurally: there is no code path that sums a skill's dimensions.

Per-DIMENSION distributions across the corpus are computed and are legitimate —
they describe where the corpus sits on one research-derived axis, which is the
actual question. Per-SKILL totals are not.

Emits the repo's structured-script-output contract
(.claude/rules/structured-script-output.md).

    python3 summarize.py [--judgments DIR]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import statistics
import sys
from collections import defaultdict

DIMS = ["D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8"]

DIM_NAMES = {
    "D1": "procedural-anchoring",
    "D2": "outcome-annotation",
    "D3": "execution-specificity",
    "D4": "adaptation-latitude",
    "D5": "budget-discipline",
    "D6": "retrieval-distinctness",
    "D7": "scope-focus",
    "D8": "constraint-checkability",
}


def load(judgments_dir):
    """Return {slug: {judge_id: record}}."""
    by_skill = defaultdict(dict)
    for path in sorted(glob.glob(os.path.join(judgments_dir, "*.json"))):
        base = os.path.basename(path)[: -len(".json")]
        if "_" not in base:
            continue
        slug, judge = base.rsplit("_", 1)
        try:
            by_skill[slug][judge] = json.load(open(path, encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            print(f"# unreadable {base}: {exc}", file=sys.stderr)
    return by_skill


def score_of(record, dim):
    if not record:
        return None
    body = record.get("dimensions", {}).get(dim)
    if not isinstance(body, dict):
        return None
    return body.get("score")


def numeric(v):
    return v if isinstance(v, int) else None


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--judgments", default=os.path.join(here, "judgments"))
    args = ap.parse_args()

    by_skill = load(args.judgments)
    if not by_skill:
        print("=== CANARY RUBRIC SUMMARY ===")
        print("SKILLS=0")
        print("STATUS=ERROR")
        print("=== END CANARY RUBRIC SUMMARY ===")
        return 1

    # --- Per-skill profile (no totals) -------------------------------------
    print("=== CANARY RUBRIC SUMMARY ===")
    print(f"SKILLS={len(by_skill)}")
    print(f"DIMENSIONS={len(DIMS)}")
    print("AGGREGATION=disabled-by-design (no per-skill totals; see rubric.md)")
    print()

    print("=== PER_SKILL_PROFILES ===")
    print("# final = adjudicated score where present, else j1/j2 when they agree,")
    print("#         else the pair shown as j1/j2 with no resolution")
    for slug in sorted(by_skill):
        judges = by_skill[slug]
        pattern = ""
        for rec in judges.values():
            if rec.get("pattern"):
                pattern = rec["pattern"]
                break
        cells = []
        for d in DIMS:
            j1 = score_of(judges.get("j1"), d)
            j2 = score_of(judges.get("j2"), d)
            adj = score_of(judges.get("adj"), d)
            if adj is not None:
                cells.append(f"{d}={adj}*")
            elif j1 == j2 and j1 is not None:
                cells.append(f"{d}={j1}")
            else:
                cells.append(f"{d}={j1}/{j2}")
        print(f"SKILL={slug} PATTERN={pattern} " + " ".join(cells))
    print()

    # --- Per-dimension distribution ----------------------------------------
    print("=== PER_DIMENSION_DISTRIBUTION ===")
    print("# resolved score per skill per dimension; mean is across SKILLS on ONE axis")
    dim_scores = defaultdict(list)
    dim_na = defaultdict(int)
    for slug, judges in by_skill.items():
        for d in DIMS:
            adj = numeric(score_of(judges.get("adj"), d))
            j1 = score_of(judges.get("j1"), d)
            j2 = score_of(judges.get("j2"), d)
            if adj is not None:
                dim_scores[d].append(adj)
                continue
            n1, n2 = numeric(j1), numeric(j2)
            if n1 is not None and n2 is not None:
                dim_scores[d].append((n1 + n2) / 2)
            elif n1 is not None:
                dim_scores[d].append(n1)
            elif n2 is not None:
                dim_scores[d].append(n2)
            else:
                dim_na[d] += 1

    for d in DIMS:
        vals = dim_scores[d]
        if vals:
            mean = statistics.mean(vals)
            lo, hi = min(vals), max(vals)
            print(
                f"DIM={d} NAME={DIM_NAMES[d]} N={len(vals)} MEAN={mean:.2f} "
                f"MIN={lo} MAX={hi} NA={dim_na[d]}"
            )
        else:
            print(f"DIM={d} NAME={DIM_NAMES[d]} N=0 NA={dim_na[d]}")
    print()

    # --- Inter-judge reliability -------------------------------------------
    print("=== INTER_JUDGE_RELIABILITY ===")
    print("# does the rubric mean the same thing to two independent readers?")
    exact = within1 = compared = applicability = 0
    per_dim_gap = defaultdict(list)
    for slug, judges in by_skill.items():
        for d in DIMS:
            j1 = score_of(judges.get("j1"), d)
            j2 = score_of(judges.get("j2"), d)
            if j1 is None or j2 is None:
                continue
            n1, n2 = numeric(j1), numeric(j2)
            if n1 is None or n2 is None:
                if j1 != j2:
                    applicability += 1
                    compared += 1
                else:
                    exact += 1
                    within1 += 1
                    compared += 1
                continue
            compared += 1
            gap = abs(n1 - n2)
            per_dim_gap[d].append(gap)
            if gap == 0:
                exact += 1
            if gap <= 1:
                within1 += 1

    if compared:
        print(f"PAIRS_COMPARED={compared}")
        print(f"EXACT_AGREEMENT={exact} ({100.0 * exact / compared:.1f}%)")
        print(f"WITHIN_ONE_POINT={within1} ({100.0 * within1 / compared:.1f}%)")
        print(f"APPLICABILITY_DISAGREEMENTS={applicability}")
        for d in DIMS:
            gaps = per_dim_gap[d]
            if gaps:
                print(
                    f"DIM={d} NAME={DIM_NAMES[d]} MEAN_GAP={statistics.mean(gaps):.2f} "
                    f"MAX_GAP={max(gaps)} DISPUTED={sum(1 for g in gaps if g >= 2)}"
                )
    else:
        print("PAIRS_COMPARED=0")
    print()

    # --- Per-pattern view ---------------------------------------------------
    print("=== PER_PATTERN ===")
    print("# skill archetypes from golden-set.json; per-dimension means within archetype")
    by_pattern = defaultdict(lambda: defaultdict(list))
    for slug, judges in by_skill.items():
        pattern = ""
        for rec in judges.values():
            if rec.get("pattern"):
                pattern = rec["pattern"]
                break
        if not pattern:
            continue
        for d in DIMS:
            adj = numeric(score_of(judges.get("adj"), d))
            n1 = numeric(score_of(judges.get("j1"), d))
            n2 = numeric(score_of(judges.get("j2"), d))
            if adj is not None:
                by_pattern[pattern][d].append(adj)
            elif n1 is not None and n2 is not None:
                by_pattern[pattern][d].append((n1 + n2) / 2)

    for pattern in sorted(by_pattern):
        cells = []
        for d in DIMS:
            vals = by_pattern[pattern][d]
            cells.append(f"{d}={statistics.mean(vals):.1f}" if vals else f"{d}=-")
        print(f"PATTERN={pattern} " + " ".join(cells))
    print()

    adjudicated = sum(1 for s in by_skill.values() if "adj" in s)
    print(f"ADJUDICATED_SKILLS={adjudicated}")
    print("STATUS=OK")
    print("=== END CANARY RUBRIC SUMMARY ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
