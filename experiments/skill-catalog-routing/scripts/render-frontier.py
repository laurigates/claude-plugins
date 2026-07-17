#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Render the accuracy-vs-length frontier from a run's results.json.

Answers the experiment's headline questions as curves, per model:
  1. accuracy vs catalog size (C0→C4): does the catalog help, and where is the
     diminishing-returns knee?
  2. false-trigger rate vs catalog size: does a bigger catalog over-trigger?
  3. per-model degradation slope (top1[C4] − top1[C2]): weak models leaning on
     description length is the portability signal (cf. evaluate-plugin's
     opus−haiku ≥ 0.2 flag).

Usage: render-frontier.py [<run-id>]   (defaults to results/LATEST)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARMS = ["C0", "C1", "C2", "C3", "C4"]
ARM_CATALOG = {"C0": "none", "C1": "names", "C2": "short", "C3": "medium", "C4": "full"}
MODELS = ["haiku", "sonnet", "opus"]
PORTABILITY_THRESHOLD = 0.15


def resolve_run_id(argv: list[str]) -> str:
    if len(argv) > 1 and argv[1] != "latest":
        return argv[1]
    latest = ROOT / "results" / "LATEST"
    if not latest.exists():
        sys.exit("no results/LATEST — pass a run-id")
    return latest.read_text().strip()


def main() -> int:
    run_id = resolve_run_id(sys.argv)
    results_path = ROOT / "results" / run_id / "results.json"
    if not results_path.exists():
        sys.exit(f"no results.json for {run_id} — run compare.py first")
    data = json.loads(results_path.read_text())
    conds = data["conditions"]
    tokens = data.get("catalog_tokens", {})

    lines = [f"# Frontier — run {run_id}", ""]

    if tokens:
        lines += ["## Measured catalog tokens", ""]
        lines += ["| arm | catalog | tokens |", "|---|---|---|"]
        for arm in ARMS:
            cat = ARM_CATALOG[arm]
            lines.append(f"| {arm} | {cat} | {tokens.get(cat, '—')} |")
        lines.append("")

    # Per-model tables.
    for model in MODELS:
        present = [a for a in ARMS if f"{model}-{a}" in conds]
        if not present:
            continue
        lines += [f"## {model}", "",
                  "| arm | catalog | tokens | top1 | near_miss | false_trigger | abstain |",
                  "|---|---|---|---|---|---|---|"]
        for arm in present:
            r = conds[f"{model}-{arm}"]
            cat = ARM_CATALOG[arm]
            tok = tokens.get(cat, "—")
            lines.append(
                f"| {arm} | {cat} | {tok} | {r['top1']:.2f} | {r['near_miss']:.2f} "
                f"| {r['false_trigger']:.2f} | {r['abstain']:.2f} |"
            )
        lines.append("")

    # Headline deltas.
    lines += ["## Headline signals", ""]
    lines += ["| model | C4−C0 (catalog value) | C4−C1 (desc value) | "
              "C4−C2 (length slope) | C3 vs C4 top1 |",
              "|---|---|---|---|---|"]
    slopes = {}
    for model in MODELS:
        def g(arm: str, key: str = "top1"):
            c = conds.get(f"{model}-{arm}")
            return c[key] if c else None
        c0, c1, c2, c3, c4 = (g(a) for a in ARMS)
        if c4 is None:
            continue
        catalog_value = f"{c4 - c0:+.2f}" if c0 is not None else "—"
        desc_value = f"{c4 - c1:+.2f}" if c1 is not None else "—"
        slope = (c4 - c2) if c2 is not None else None
        slopes[model] = slope
        slope_s = f"{slope:+.2f}" if slope is not None else "—"
        c3c4 = f"{c3:.2f} vs {c4:.2f}" if c3 is not None else "—"
        lines.append(f"| {model} | {catalog_value} | {desc_value} | {slope_s} | {c3c4} |")
    lines.append("")

    # Portability read.
    if "haiku" in slopes and "opus" in slopes and slopes["haiku"] is not None and slopes["opus"] is not None:
        gap = slopes["haiku"] - slopes["opus"]
        lines += ["## Portability", ""]
        if gap >= PORTABILITY_THRESHOLD:
            lines.append(
                f"⚠️ haiku degrades {gap:+.2f} more than opus when descriptions shrink "
                f"(C4−C2 slope gap ≥ {PORTABILITY_THRESHOLD}). Weak models lean on "
                "description length — shortening is safe on opus but harms haiku."
            )
        else:
            lines.append(
                f"Shortening headroom is comparable across models (haiku−opus slope gap "
                f"{gap:+.2f} < {PORTABILITY_THRESHOLD}). Shorter descriptions are "
                "roughly as safe on the weak model as on the strong one."
            )
        lines.append("")

    report = "\n".join(lines)
    print(report)
    (ROOT / "results" / run_id / "frontier.md").write_text(report + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
