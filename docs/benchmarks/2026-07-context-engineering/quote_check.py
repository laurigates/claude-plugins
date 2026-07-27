#!/usr/bin/env python3
"""quote_check.py — mechanically verify every judgment's evidence quotes.

The integrity rule this enforces (rubric.md, "How to score"):

    Every score of 1, 2, 4, or 5 requires a verbatim quote from the unit,
    reproduced exactly so it can be mechanically string-matched against the
    file. A score you cannot quote for must be a 3.

A judge that fabricates or paraphrases evidence produces confident, unfalsifiable
findings — the exact failure mode an anchored rubric is supposed to prevent. This
script is the falsifier: it reads every judgments/*.json, resolves each quote
against the unit file on disk, and reports any that do not match.

Normalisation is deliberately minimal — whitespace runs collapse and smart
quotes/dashes fold to ASCII, because a judge retyping a line will differ there
and nowhere else that matters. Everything else must match exactly.

Exit 1 if any quote fails to match or any extreme score lacks evidence.

    python3 quote_check.py [--project-dir PATH] [--judgments DIR]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

EXTREME_SCORES = {1, 2, 4, 5}
FOLD = {
    "‘": "'",
    "’": "'",
    "“": '"',
    "”": '"',
    "–": "-",
    "—": "-",
    "…": "...",
    " ": " ",
}


def normalise(text: str) -> str:
    for src, dst in FOLD.items():
        text = text.replace(src, dst)
    return re.sub(r"\s+", " ", text).strip()


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir", default=os.path.abspath(os.path.join(here, "..", "..", ".."))
    )
    ap.add_argument("--judgments", default=os.path.join(here, "judgments"))
    args = ap.parse_args()

    cache: dict[str, str] = {}
    checked = failed = missing_evidence = 0
    problems: list[str] = []

    for path in sorted(glob.glob(os.path.join(args.judgments, "*.json"))):
        name = os.path.basename(path)
        try:
            data = json.load(open(path, encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            problems.append(f"{name}: unreadable ({exc})")
            failed += 1
            continue

        unit = data.get("unit", "")
        unit_path = os.path.join(args.project_dir, unit)
        if unit not in cache:
            try:
                cache[unit] = normalise(
                    open(unit_path, encoding="utf-8", errors="replace").read()
                )
            except OSError:
                cache[unit] = ""
                problems.append(f"{name}: unit file not found: {unit}")
        haystack = cache[unit]

        for dim, body in sorted(data.get("dimensions", {}).items()):
            score = body.get("score")
            evidence = body.get("evidence") or []
            if isinstance(score, int) and score in EXTREME_SCORES and not evidence:
                missing_evidence += 1
                problems.append(f"{name} {dim}: score {score} with no evidence quote")
            for item in evidence:
                quote = normalise(item.get("quote", ""))
                checked += 1
                if not quote:
                    failed += 1
                    problems.append(f"{name} {dim}: empty quote")
                elif quote not in haystack:
                    failed += 1
                    problems.append(
                        f"{name} {dim}: quote not found in {unit}: {quote[:110]!r}"
                    )

    print("=== QUOTE CHECK ===")
    print(f"JUDGMENT_FILES={len(glob.glob(os.path.join(args.judgments, '*.json')))}")
    print(f"QUOTES_CHECKED={checked}")
    print(f"QUOTES_VERIFIED={checked - failed}")
    print(f"QUOTES_FAILED={failed}")
    print(f"EXTREME_SCORES_WITHOUT_EVIDENCE={missing_evidence}")
    print(f"STATUS={'OK' if failed == 0 and missing_evidence == 0 else 'ERROR'}")
    print(f"ISSUE_COUNT={len(problems)}")
    if problems:
        print("ISSUES:")
        for p in problems:
            print(f"  - {p}")
    print("=== END QUOTE CHECK ===")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
