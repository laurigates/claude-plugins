#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Aggregate scored routing transcripts for a run-id into per-condition metrics.

Walks results/<run_id>/*.jsonl, scores each with score-run.py, joins against the
task metadata (gold type: route / near_miss / none), and emits:

  * results/<run_id>/scores.tsv      raw per-transcript rows
  * results/<run_id>/results.json    per-condition metrics (for render-frontier.py)
  * results/<run_id>/report.md       a markdown metrics table

Metrics per condition (pooled over runs):
  n_route        gradeable route tasks (gold != NONE)
  top1           top-1 routing accuracy over route tasks
  near_miss      accuracy over the near-miss discrimination subset
  top2_nearmiss  (predicted OR runner_up == gold) over near-miss subset
  false_trigger  fraction of gold=NONE tasks where a skill was (wrongly) picked
  abstain        fraction of gold=NONE tasks correctly answered NONE
  parse_fail     fraction of all transcripts whose decision did not parse
"""

from __future__ import annotations

import argparse
import collections
import json
import subprocess
import sys
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def resolve_run_id(arg: str | None) -> str:
    if arg and arg != "latest":
        return arg
    latest = ROOT / "results" / "LATEST"
    if not latest.exists():
        sys.exit("no results/LATEST — pass a run-id explicitly")
    return latest.read_text().strip()


def load_task_meta() -> dict[str, dict]:
    meta = {}
    for tf in sorted((ROOT / "tasks").glob("*.yaml")):
        t = yaml.safe_load(tf.read_text())
        gold = str(t.get("gold", "NONE"))
        is_none = gold.strip().upper() == "NONE"
        meta[tf.stem] = {
            "gold": gold,
            "is_none": is_none,
            "is_near_miss": bool(t.get("near_miss")) and not is_none,
        }
    return meta


def score(transcript: Path) -> list[str] | None:
    proc = subprocess.run(
        [str(HERE / "score-run.py"), str(transcript)],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode != 0:
        print(f"WARN: score-run failed for {transcript.name}: {proc.stderr}", file=sys.stderr)
        return None
    line = proc.stdout.strip()
    return line.split("\t") if line else None


def wilson(p: float, n: int) -> tuple[float, float]:
    """95% Wilson interval half-widths are folded into (lo, hi)."""
    if n == 0:
        return (0.0, 0.0)
    z = 1.96
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id", nargs="?", default="latest")
    args = ap.parse_args()

    run_id = resolve_run_id(args.run_id)
    run_dir = ROOT / "results" / run_id
    if not run_dir.is_dir():
        sys.exit(f"no such run: {run_dir}")

    transcripts = sorted(run_dir.glob("*.jsonl"))
    if not transcripts:
        sys.exit(f"no transcripts under {run_dir}")

    task_meta = load_task_meta()
    rows = [r for t in transcripts if (r := score(t))]

    # Persist raw scores.
    header = ["task_id", "condition_id", "run_n", "gold", "predicted",
              "runner_up", "confidence", "correct", "parse"]
    with (run_dir / "scores.tsv").open("w") as f:
        f.write("\t".join(header) + "\n")
        for r in rows:
            f.write("\t".join(r) + "\n")

    # Aggregate per condition.
    agg: dict[str, dict] = collections.defaultdict(lambda: {
        "route_correct": 0, "route_n": 0,
        "nm_correct": 0, "nm_top2": 0, "nm_n": 0,
        "none_abstain": 0, "none_n": 0,
        "parse_fail": 0, "total": 0,
    })
    for task_id, cond, _run_n, gold, predicted, runner_up, _conf, correct, parse in rows:
        m = task_meta.get(task_id)
        if m is None:
            continue
        a = agg[cond]
        a["total"] += 1
        if parse != "ok":
            a["parse_fail"] += 1
        if m["is_none"]:
            a["none_n"] += 1
            if parse == "ok" and predicted == "NONE":
                a["none_abstain"] += 1
        else:
            a["route_n"] += 1
            if correct == "1":
                a["route_correct"] += 1
            if m["is_near_miss"]:
                a["nm_n"] += 1
                if correct == "1":
                    a["nm_correct"] += 1
                if parse == "ok" and (predicted == m["gold"] or runner_up == m["gold"]):
                    a["nm_top2"] += 1

    # Optional measured catalog tokens.
    tokens = {}
    tok_path = run_dir.parent.parent / "catalogs" / "catalog_tokens.json"
    if tok_path.exists():
        tokens = json.loads(tok_path.read_text())

    def rate(num: int, den: int) -> float:
        return round(num / den, 4) if den else 0.0

    results = {}
    for cond, a in sorted(agg.items()):
        top1 = rate(a["route_correct"], a["route_n"])
        lo, hi = wilson(top1, a["route_n"])
        results[cond] = {
            "n_route": a["route_n"],
            "top1": top1,
            "top1_ci": [round(lo, 4), round(hi, 4)],
            "near_miss": rate(a["nm_correct"], a["nm_n"]),
            "top2_nearmiss": rate(a["nm_top2"], a["nm_n"]),
            "false_trigger": rate(a["none_n"] - a["none_abstain"], a["none_n"]),
            "abstain": rate(a["none_abstain"], a["none_n"]),
            "parse_fail": rate(a["parse_fail"], a["total"]),
            "total": a["total"],
        }
    out = {"run_id": run_id, "conditions": results, "catalog_tokens": tokens}
    (run_dir / "results.json").write_text(json.dumps(out, indent=2) + "\n")

    # Markdown report.
    cols = ["top1", "near_miss", "top2_nearmiss", "false_trigger", "abstain", "parse_fail"]
    lines = [f"# skill-catalog-routing run {run_id}", "",
             f"Transcripts: {len(transcripts)}  ·  scored rows: {len(rows)}", "",
             "| condition | " + " | ".join(cols) + " | n_route |",
             "|" + "---|" * (len(cols) + 2)]
    for cond in sorted(results):
        r = results[cond]
        cells = [f"{r[c]:.2f}" for c in cols]
        lines.append(f"| {cond} | " + " | ".join(cells) + f" | {r['n_route']} |")
    report = "\n".join(lines)
    print(report)
    (run_dir / "report.md").write_text(report + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
