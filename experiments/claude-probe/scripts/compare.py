#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Aggregate scored transcripts for a run-id into a comparison table.

Walks results/<run_id>/*.jsonl, runs score-run.py and llm-judge.py
against each, then prints a markdown table of (test x condition)
pass-rates plus a per-check breakdown.
"""

from __future__ import annotations

import argparse
import collections
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def score_transcript(transcript: Path, use_judge: bool) -> list[list[str]]:
    rows = []
    proc = subprocess.run(
        [str(HERE / "score-run.py"), str(transcript)],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        print(f"WARN: score-run.py failed for {transcript.name}: {proc.stderr}", file=sys.stderr)
    for line in proc.stdout.splitlines():
        if line.strip():
            rows.append(line.split("\t"))

    if use_judge:
        proc = subprocess.run(
            [str(HERE / "llm-judge.py"), str(transcript)],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            print(f"WARN: llm-judge.py failed for {transcript.name}: {proc.stderr}", file=sys.stderr)
        for line in proc.stdout.splitlines():
            if line.strip():
                rows.append(line.split("\t"))
    return rows


def resolve_run_id(arg: str | None) -> str:
    if arg and arg != "latest":
        return arg
    latest = ROOT / "results" / "LATEST"
    if not latest.exists():
        sys.exit("no results/LATEST — pass a run-id explicitly")
    return latest.read_text().strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id", nargs="?", default="latest")
    ap.add_argument("--no-judge", action="store_true", help="skip LLM judge checks")
    ap.add_argument("--out", help="write full markdown report to this path")
    args = ap.parse_args()

    run_id = resolve_run_id(args.run_id)
    run_dir = ROOT / "results" / run_id
    if not run_dir.is_dir():
        sys.exit(f"no such run: {run_dir}")

    transcripts = sorted(run_dir.glob("*.jsonl"))
    if not transcripts:
        sys.exit(f"no transcripts under {run_dir}")

    all_rows: list[list[str]] = []
    for t in transcripts:
        all_rows.extend(score_transcript(t, use_judge=not args.no_judge))

    # Persist raw scores.
    scores_path = run_dir / "scores.tsv"
    with scores_path.open("w") as f:
        f.write("test_id\tcondition_id\trun_n\tcheck_id\tresult\tdetail\n")
        for r in all_rows:
            f.write("\t".join(r) + "\n")

    # Aggregate: (test, condition) -> pass/total ignoring INFO/SKIP.
    agg: dict[tuple[str, str], list[int]] = collections.defaultdict(lambda: [0, 0])
    for test_id, cond_id, _run_n, _cid, result, _detail in all_rows:
        if result in ("INFO", "SKIP"):
            continue
        agg[(test_id, cond_id)][1] += 1
        if result == "PASS":
            agg[(test_id, cond_id)][0] += 1

    tests = sorted({k[0] for k in agg})
    conds = sorted({k[1] for k in agg})

    lines = [f"# claude-probe run {run_id}", "", f"Transcripts: {len(transcripts)}", ""]
    lines.append("| test | " + " | ".join(conds) + " |")
    lines.append("|" + "---|" * (len(conds) + 1))
    for t in tests:
        row = [t]
        for c in conds:
            p, n = agg[(t, c)]
            row.append(f"{p}/{n}" if n else "-")
        lines.append("| " + " | ".join(row) + " |")

    lines.extend(["", "## Raw scores", "", f"See `{scores_path.relative_to(ROOT)}`", ""])

    report = "\n".join(lines)
    print(report)

    if args.out:
        Path(args.out).write_text(report)
    else:
        (run_dir / "report.md").write_text(report)

    return 0


if __name__ == "__main__":
    sys.exit(main())
