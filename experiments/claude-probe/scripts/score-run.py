#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Score a single transcript against its test's checks.

Reads a stream-JSON transcript (one JSON object per line as emitted by
`claude -p --output-format stream-json`) and applies the checks declared
in the corresponding test YAML. Writes one TSV row to stdout per check
plus a summary row:

    test_id  condition_id  run_n  check_id  result  detail

Result values: PASS | FAIL | SKIP | ERROR.

Deterministic checks only. LLM-judge checks are marked SKIP here; run
llm-judge.py separately for those.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def load_transcript(path: Path) -> list[dict[str, Any]]:
    events = []
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def load_test(test_id: str) -> dict[str, Any]:
    path = ROOT / "tests" / f"{test_id}.yaml"
    with path.open() as f:
        return yaml.safe_load(f)


def iter_tool_uses(events: list[dict[str, Any]]):
    """Yield (tool_name, tool_input) pairs across all assistant messages."""
    for ev in events:
        msg = ev.get("message") or ev
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                yield block.get("name", ""), block.get("input", {}) or {}


def final_text(events: list[dict[str, Any]]) -> str:
    """Concatenate assistant text blocks from the final assistant turn(s)."""
    out = []
    for ev in events:
        msg = ev.get("message") or ev
        if msg.get("role") != "assistant":
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                out.append(block.get("text", ""))
    return "\n".join(out)


def usage_totals(events: list[dict[str, Any]]) -> dict[str, int]:
    """Sum input/output tokens from usage blocks if present."""
    totals = {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0}
    for ev in events:
        msg = ev.get("message") or ev
        usage = msg.get("usage") if isinstance(msg, dict) else None
        if isinstance(usage, dict):
            for k in totals:
                v = usage.get(k)
                if isinstance(v, int):
                    totals[k] += v
    return totals


def assistant_turn_count(events: list[dict[str, Any]]) -> int:
    count = 0
    for ev in events:
        msg = ev.get("message") or ev
        if isinstance(msg, dict) and msg.get("role") == "assistant":
            count += 1
    return count


def check_tool_used(tool_uses, spec) -> tuple[bool, str]:
    """spec: either a string (tool name) or {name, arg_pattern}."""
    if isinstance(spec, str):
        name, pattern = spec, None
    else:
        name = spec.get("name", "")
        pattern = spec.get("arg_pattern")
    regex = re.compile(pattern) if pattern else None
    for tn, ti in tool_uses:
        if tn != name:
            continue
        if regex is None:
            return True, f"found {name}"
        blob = json.dumps(ti, sort_keys=True)
        if regex.search(blob):
            return True, f"found {name} matching /{pattern}/"
    return False, f"{name} not used" + (f" matching /{pattern}/" if pattern else "")


def check_tool_not_used(tool_uses, spec) -> tuple[bool, str]:
    ok, detail = check_tool_used(tool_uses, spec)
    return (not ok), ("absent as required" if not ok else f"unexpected: {detail}")


def check_max_turns(events, n) -> tuple[bool, str]:
    actual = assistant_turn_count(events)
    return (actual <= n), f"turns={actual} limit={n}"


def check_max_output_tokens(events, n) -> tuple[bool, str]:
    totals = usage_totals(events)
    actual = totals["output_tokens"]
    return (actual <= n), f"output_tokens={actual} limit={n}"


def check_output_matches(events, pattern) -> tuple[bool, str]:
    text = final_text(events)
    ok = re.search(pattern, text) is not None
    return ok, f"/{pattern}/ {'matched' if ok else 'NOT matched'}"


def check_output_not_matches(events, pattern) -> tuple[bool, str]:
    text = final_text(events)
    ok = re.search(pattern, text) is None
    return ok, f"/{pattern}/ {'absent' if ok else 'unexpectedly matched'}"


def run_checks(test: dict[str, Any], events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    tool_uses = list(iter_tool_uses(events))
    results = []
    for i, check in enumerate(test.get("checks", [])):
        cid = check.get("id") or f"check{i+1}"
        kind = check.get("type")
        try:
            if kind == "tool_used":
                ok, detail = check_tool_used(tool_uses, check["spec"])
            elif kind == "tool_not_used":
                ok, detail = check_tool_not_used(tool_uses, check["spec"])
            elif kind == "max_turns":
                ok, detail = check_max_turns(events, int(check["value"]))
            elif kind == "max_output_tokens":
                ok, detail = check_max_output_tokens(events, int(check["value"]))
            elif kind == "output_matches":
                ok, detail = check_output_matches(events, check["pattern"])
            elif kind == "output_not_matches":
                ok, detail = check_output_not_matches(events, check["pattern"])
            elif kind == "llm_judge":
                results.append({"id": cid, "type": kind, "result": "SKIP", "detail": "run llm-judge.py"})
                continue
            else:
                results.append({"id": cid, "type": kind, "result": "ERROR", "detail": f"unknown type: {kind}"})
                continue
            results.append({"id": cid, "type": kind, "result": "PASS" if ok else "FAIL", "detail": detail})
        except Exception as e:  # noqa: BLE001
            results.append({"id": cid, "type": kind, "result": "ERROR", "detail": repr(e)})
    return results


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript", help="path to .jsonl transcript")
    ap.add_argument("--format", choices=["tsv", "json"], default="tsv")
    args = ap.parse_args()

    tpath = Path(args.transcript)
    mpath = tpath.with_suffix(".meta.json") if tpath.suffix == ".jsonl" else None
    if mpath is None or not mpath.exists():
        # Derive meta path by stripping .jsonl and appending .meta.json
        stem = tpath.name[: -len(".jsonl")] if tpath.name.endswith(".jsonl") else tpath.stem
        mpath = tpath.with_name(stem + ".meta.json")

    with mpath.open() as f:
        meta = json.load(f)

    test = load_test(meta["test_id"])
    events = load_transcript(tpath)
    results = run_checks(test, events)

    totals = usage_totals(events)
    turns = assistant_turn_count(events)

    if args.format == "json":
        out = {"meta": meta, "usage": totals, "turns": turns, "checks": results}
        print(json.dumps(out, indent=2))
        return 0

    # TSV: one row per check.
    for r in results:
        print(
            "\t".join(
                [
                    meta["test_id"],
                    meta["condition_id"],
                    str(meta["run_n"]),
                    r["id"],
                    r["result"],
                    r["detail"].replace("\t", " "),
                ]
            )
        )
    # Summary row (turns/tokens) as a synthetic "stats" check.
    print(
        "\t".join(
            [
                meta["test_id"],
                meta["condition_id"],
                str(meta["run_n"]),
                "_stats",
                "INFO",
                f"turns={turns} in={totals['input_tokens']} out={totals['output_tokens']} cache_r={totals['cache_read_input_tokens']}",
            ]
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
