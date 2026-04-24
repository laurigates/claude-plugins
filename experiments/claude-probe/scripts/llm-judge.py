#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""LLM-as-judge: evaluate fuzzy checks against a transcript.

For each check of `type: llm_judge` in a test's YAML, render a judge
prompt and invoke `claude -p` (default system prompt, cheap model) as
the judge. Parse a PASS/FAIL/INDETERMINATE verdict from the first line
of the judge's reply.

The judge does NOT run with any `--system-prompt` override — we want
its behaviour to be the harness baseline, not the condition under test.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
JUDGE_MODEL = os.environ.get("PROBE_JUDGE_MODEL", "claude-haiku-4-5-20251001")


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


def transcript_to_text(events: list[dict[str, Any]]) -> str:
    """Render transcript as a compact plain-text conversation for the judge."""
    parts = []
    for ev in events:
        msg = ev.get("message") or ev
        if not isinstance(msg, dict):
            continue
        role = msg.get("role")
        content = msg.get("content")
        if role not in ("user", "assistant") or not isinstance(content, list):
            continue
        lines = [f"[{role}]"]
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "text":
                lines.append(block.get("text", ""))
            elif btype == "tool_use":
                inp = json.dumps(block.get("input", {}), sort_keys=True)
                lines.append(f"<tool_use name={block.get('name')}>{inp}</tool_use>")
            elif btype == "tool_result":
                lines.append(f"<tool_result>{str(block.get('content',''))[:400]}</tool_result>")
        parts.append("\n".join(lines))
    return "\n\n".join(parts)


JUDGE_INSTRUCTIONS = """\
You are an impartial judge scoring an assistant's response against a rubric.

OUTPUT FORMAT — first line MUST be exactly one of:
  VERDICT: PASS
  VERDICT: FAIL
  VERDICT: INDETERMINATE

Then a single line of reasoning (<= 200 chars). Do NOT write anything else.
"""


def render_prompt(rubric: str, prompt: str, transcript_text: str) -> str:
    return f"""{JUDGE_INSTRUCTIONS}

--- RUBRIC ---
{rubric}

--- ORIGINAL USER PROMPT ---
{prompt}

--- ASSISTANT TRANSCRIPT ---
{transcript_text}

--- YOUR VERDICT ---
"""


def run_judge(prompt_text: str) -> tuple[str, str]:
    if not shutil.which("claude"):
        return "ERROR", "claude CLI not on PATH"
    proc = subprocess.run(
        ["claude", "-p", prompt_text, "--model", JUDGE_MODEL, "--output-format", "text"],
        capture_output=True,
        text=True,
        check=False,
    )
    out = (proc.stdout or "").strip()
    if proc.returncode != 0:
        return "ERROR", f"judge exit={proc.returncode}: {(proc.stderr or '').strip()[:200]}"
    m = re.match(r"VERDICT:\s*(PASS|FAIL|INDETERMINATE)\b(.*)", out, re.IGNORECASE | re.DOTALL)
    if not m:
        return "ERROR", f"unparseable: {out[:200]}"
    verdict = m.group(1).upper()
    reason = m.group(2).strip().splitlines()[0] if m.group(2).strip() else ""
    return verdict, reason[:300]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    args = ap.parse_args()

    tpath = Path(args.transcript)
    stem = tpath.name[: -len(".jsonl")] if tpath.name.endswith(".jsonl") else tpath.stem
    mpath = tpath.with_name(stem + ".meta.json")

    with mpath.open() as f:
        meta = json.load(f)

    test_path = ROOT / "tests" / f"{meta['test_id']}.yaml"
    with test_path.open() as f:
        test = yaml.safe_load(f)

    judge_checks = [c for c in test.get("checks", []) if c.get("type") == "llm_judge"]
    if not judge_checks:
        return 0  # nothing to do

    events = load_transcript(tpath)
    transcript_text = transcript_to_text(events)

    for i, check in enumerate(judge_checks):
        cid = check.get("id") or f"judge{i+1}"
        rubric = check.get("rubric", "")
        prompt = render_prompt(rubric, test.get("prompt", ""), transcript_text)
        verdict, reason = run_judge(prompt)
        result = {
            "VERDICT: PASS": "PASS",
            "PASS": "PASS",
            "FAIL": "FAIL",
            "INDETERMINATE": "SKIP",
            "ERROR": "ERROR",
        }.get(verdict, "ERROR")
        print(
            "\t".join(
                [
                    meta["test_id"],
                    meta["condition_id"],
                    str(meta["run_n"]),
                    cid,
                    result,
                    reason.replace("\t", " "),
                ]
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
