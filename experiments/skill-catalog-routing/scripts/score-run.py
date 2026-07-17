#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Score one routing transcript against its task's gold label.

Reads a stream-JSON transcript (from `claude -p --output-format stream-json`),
extracts the router's decision from the LAST JSON object in the final assistant
text (the "grade the answer, not the preamble" discipline from claude-probe),
and grades it against the task YAML's `gold` field.

Emits ONE TSV data row to stdout:

    task_id  condition_id  run_n  gold  predicted  runner_up  confidence  correct  parse

  * gold       — the task's correct skill id, or NONE
  * predicted  — the router's chosen id (normalized), or NONE, or PARSE_FAIL
  * runner_up  — the router's second choice (normalized), or NONE
  * confidence — the router's stated confidence (or "")
  * correct    — 1 if predicted == gold (after normalization), else 0
  * parse      — ok | parse_fail | empty

Normalization: case-insensitive; a bare `<skill>` with no plugin prefix is
resolved against the catalog id set if unambiguous. Ids not in the catalog are
kept verbatim (they simply won't match a gold that is in the catalog).

The scorer never needs an LLM — routing is a deterministic id match.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


@lru_cache(maxsize=1)
def catalog_ids() -> tuple[frozenset[str], dict[str, str]]:
    """Return (full id set, bare-name -> id map for unambiguous bare names)."""
    path = ROOT / "catalogs" / "catalog.names.json"
    ids = set()
    if path.exists():
        data = json.loads(path.read_text())
        ids = {e["id"] for e in data["entries"]}
    bare_counts: dict[str, list[str]] = {}
    for rid in ids:
        bare = rid.split("/", 1)[-1]
        bare_counts.setdefault(bare.lower(), []).append(rid)
    bare_map = {b: v[0] for b, v in bare_counts.items() if len(v) == 1}
    return frozenset(ids), bare_map


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


def final_answer_text(events: list[dict[str, Any]]) -> str:
    """Text of the final assistant turn that produced prose (claude-probe)."""
    last = ""
    for ev in events:
        msg = ev.get("message") or ev
        if msg.get("role") != "assistant":
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        parts = [
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        ]
        joined = "\n".join(p for p in parts if p)
        if joined.strip():
            last = joined
    return last


_JSON_OBJ_RE = re.compile(r"\{[^{}]*\}")


def parse_decision(text: str) -> dict | None:
    """Return the LAST parseable JSON object with a `skill` key, or None."""
    candidates = _JSON_OBJ_RE.findall(text)
    for blob in reversed(candidates):
        try:
            obj = json.loads(blob)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and "skill" in obj:
            return obj
    return None


def normalize(value: Any) -> str:
    """Normalize a predicted id to a catalog id or NONE."""
    if value is None:
        return "NONE"
    s = str(value).strip().strip("`'\"").strip()
    if not s or s.upper() == "NONE":
        return "NONE"
    ids, bare_map = catalog_ids()
    # exact (case-insensitive) match against catalog ids
    for rid in ids:
        if rid.lower() == s.lower():
            return rid
    # bare skill name, unambiguous
    bare = s.split("/", 1)[-1].lower()
    if bare in bare_map:
        return bare_map[bare]
    # unknown id — keep as-is (won't match an in-catalog gold)
    return s


def load_task(task_id: str) -> dict[str, Any]:
    return yaml.safe_load((ROOT / "tasks" / f"{task_id}.yaml").read_text())


def parse_name(transcript: Path) -> tuple[str, str, int]:
    """(task_id, condition_id, run_n) from '<task>.<condition>.run<N>.jsonl'."""
    stem = transcript.name[: -len(".jsonl")]
    m = re.match(r"^(?P<task>.+)\.(?P<cond>[^.]+)\.run(?P<n>\d+)$", stem)
    if not m:
        raise ValueError(f"cannot parse transcript name: {transcript.name}")
    return m["task"], m["cond"], int(m["n"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    args = ap.parse_args()

    transcript = Path(args.transcript)
    task_id, cond_id, run_n = parse_name(transcript)
    task = load_task(task_id)
    gold = normalize(task.get("gold"))

    events = load_transcript(transcript)
    text = final_answer_text(events)
    decision = parse_decision(text)

    if not text.strip():
        parse = "empty"
        predicted, runner_up, conf = "PARSE_FAIL", "NONE", ""
    elif decision is None:
        parse = "parse_fail"
        predicted, runner_up, conf = "PARSE_FAIL", "NONE", ""
    else:
        parse = "ok"
        predicted = normalize(decision.get("skill"))
        runner_up = normalize(decision.get("runner_up"))
        conf = str(decision.get("confidence", ""))

    correct = 1 if (parse == "ok" and predicted == gold) else 0
    row = [task_id, cond_id, str(run_n), gold, predicted, runner_up, conf, str(correct), parse]
    print("\t".join(row))
    return 0


if __name__ == "__main__":
    sys.exit(main())
