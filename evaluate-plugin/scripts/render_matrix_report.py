#!/usr/bin/env python3
"""Render a markdown report from a model-matrix.json result file.

The matrix file records with-skill and baseline pass rates for one skill across
several pinned models (opus / sonnet / haiku). This renderer turns it into the
delta table that is the actual signal: does the skill beat the model's baseline,
does that hold on cheaper models, and did the picture move since the last run.

See ``evaluate-plugin/references/schemas.md`` (model-matrix.json) for the input
schema, and ``evaluate-plugin/docs/cross-model-evaluation.md`` for how the
verdicts are interpreted.

Usage:
  render_matrix_report.py <model-matrix.json> [--out <file.md>]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Verdict thresholds (delta = with_skill - baseline). See the design doc's 2x2.
EARNS_KEEP_DELTA = 0.15   # with-skill clearly beats baseline
REDUNDANT_BASELINE = 0.85  # baseline already strong; skill may be redundant
FIGHTING_DELTA = -0.05    # with-skill underperforms baseline


def _pct(x) -> str:
    return "—" if x is None else f"{round(x * 100)}%"


def _delta_cell(delta, prev_delta) -> str:
    if delta is None:
        return "—"
    cell = f"{'+' if delta >= 0 else ''}{round(delta * 100)}%"
    if prev_delta is not None:
        move = round((delta - prev_delta) * 100)
        if move > 0:
            cell += f" ▲{move}"
        elif move < 0:
            cell += f" ▼{abs(move)}"
        else:
            cell += " ="
    return cell


def _verdict(with_skill, baseline) -> str:
    if with_skill is None or baseline is None:
        return "n/a"
    delta = with_skill - baseline
    if delta <= FIGHTING_DELTA:
        return "⚠ fighting the model" if baseline >= 0.5 else "⚠ ineffective"
    if baseline >= REDUNDANT_BASELINE and delta < EARNS_KEEP_DELTA:
        return "possibly redundant"
    if delta >= EARNS_KEEP_DELTA:
        return "earns its keep"
    return "marginal"


def render(matrix: dict) -> str:
    meta = matrix.get("metadata", {})
    models = meta.get("models", [])
    aliases = [m["alias"] for m in models]
    by_model = matrix.get("summary", {}).get("by_model", {})

    out = []
    out.append(f"# Cross-model evaluation: {meta.get('skill_path', '?')}")
    out.append("")
    out.append(f"_Generated: {meta.get('generated_at', '?')}_  ")
    prev = meta.get("previous_run")
    out.append(f"_Previous run: {prev or 'none — first sweep'}_")
    out.append("")
    id_line = ", ".join(f"`{m['alias']}`=`{m['model_id']}`" for m in models)
    out.append(f"Pinned models: {id_line}")
    out.append("")

    # Summary delta table.
    out.append("## Summary (mean pass rate across all evals)")
    out.append("")
    out.append("| Model | With skill | Baseline | Delta (Δ vs prev) | Verdict |")
    out.append("|-------|-----------|----------|-------------------|---------|")
    for alias in aliases:
        row = by_model.get(alias, {})
        ws, bl = row.get("with_skill"), row.get("baseline")
        out.append(
            f"| {alias} | {_pct(ws)} | {_pct(bl)} | "
            f"{_delta_cell(row.get('delta'), row.get('prev_delta'))} | {_verdict(ws, bl)} |"
        )
    out.append("")

    # Per-eval breakdown (with-skill rates per model).
    evals = matrix.get("evals", [])
    if evals:
        out.append("## Per-eval breakdown (with-skill pass rate)")
        out.append("")
        out.append("| Eval | " + " | ".join(aliases) + " |")
        out.append("|------|" + "|".join(["------"] * len(aliases)) + "|")
        for ev in evals:
            cells = []
            for alias in aliases:
                cell = ev.get("by_model", {}).get(alias, {})
                cells.append(_pct(cell.get("with_skill")))
            out.append(f"| {ev.get('eval_id', '?')} | " + " | ".join(cells) + " |")
        out.append("")

    # Portability flag: opus vs haiku with-skill spread.
    opus = by_model.get("opus", {}).get("with_skill")
    haiku = by_model.get("haiku", {}).get("with_skill")
    if opus is not None and haiku is not None and (opus - haiku) >= 0.2:
        out.append(
            f"> **Portability flag:** opus with-skill ({_pct(opus)}) exceeds haiku "
            f"({_pct(haiku)}) by ≥20 points — the skill leans on reasoning the cheaper "
            f"model lacks. Consider simplifying the skill or pinning `model:` in frontmatter."
        )
        out.append("")

    return "\n".join(out)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Render cross-model eval report")
    parser.add_argument("matrix", help="Path to model-matrix.json")
    parser.add_argument("--out", help="Write markdown to this file instead of stdout")
    args = parser.parse_args(argv)

    matrix = json.loads(Path(args.matrix).read_text())
    report = render(matrix)

    if args.out:
        Path(args.out).write_text(report + "\n")
        print(f"Wrote {args.out}")
    else:
        print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
