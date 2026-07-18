#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Validate the task set: schema, gold/near_miss resolve to catalog ids, and the
lexical-leakage gate.

The leakage gate is the study's most important instrument. If a task echoes its
gold skill's own NAME tokens, then names-only (C1) can win by string overlap and
description length stops mattering — the experiment would measure nothing. We
compute `name_overlap` = fraction of the gold skill's distinctive name tokens
that appear in the task prompt, and flag anything above the threshold.

Emits a structured `=== TASK AUDIT ===` report (see
.claude/rules/structured-script-output.md). `--strict` exits 1 on any ERROR.

Usage:
    check-tasks.py            # audit, human report
    check-tasks.py --strict   # exit 1 on schema errors or leakage over threshold
    check-tasks.py --json     # machine-readable
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent

NAME_OVERLAP_ERROR = 0.5   # over half the name tokens echoed → hard leak
NAME_OVERLAP_WARN = 0.34   # a third echoed → review

# Generic tokens that appear in many skill names AND naturally in symptom prose;
# echoing these is not meaningful leakage.
GENERIC = {
    "code", "test", "tests", "git", "check", "run", "build", "file", "files",
    "search", "review", "audit", "plugin", "config", "python", "rust", "node",
    "management", "development", "workflow", "tool", "tools", "analysis", "add",
    "status", "install", "advanced", "cli", "quality", "docs", "data",
}
STOP = {
    "a", "an", "the", "to", "of", "for", "in", "on", "and", "or", "with", "my",
    "i", "is", "are", "it", "this", "that", "how", "do", "can", "need", "want",
    "am", "have", "has", "get", "there", "when", "use", "using", "some", "any",
    "me", "we", "our", "your", "but", "so", "up", "out", "into", "from", "at",
}


def tokenize(text: str) -> set[str]:
    words = re.findall(r"[a-z0-9]+", text.lower())
    out = set()
    for w in words:
        if w in STOP or len(w) < 3:
            continue
        # crude singularization
        if w.endswith("s") and len(w) > 3:
            w = w[:-1]
        out.add(w)
    return out


def name_tokens(skill_id: str) -> set[str]:
    slug = skill_id.split("/", 1)[-1]
    toks = {t for t in re.split(r"[-_]", slug.lower()) if len(t) >= 3}
    # drop the plugin-name echo and generic tokens
    return {t for t in toks if t not in GENERIC}


def catalog_ids() -> set[str]:
    path = ROOT / "catalogs" / "catalog.names.json"
    if not path.exists():
        sys.exit("no catalog.names.json — run build-catalogs.py first")
    return {e["id"] for e in json.loads(path.read_text())["entries"]}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    ids = catalog_ids()
    task_files = sorted((ROOT / "tasks").glob("*.yaml"))
    rows = []
    errors = 0
    warns = 0

    for tf in task_files:
        rec = {"task": tf.stem, "issues": []}
        try:
            t = yaml.safe_load(tf.read_text())
        except yaml.YAMLError as e:
            rec["issues"].append(("ERROR", f"yaml parse: {e}"))
            rows.append(rec); errors += 1
            continue
        prompt = str(t.get("prompt", "")).strip()
        gold = str(t.get("gold", "")).strip()
        near = t.get("near_miss")
        rec["gold"] = gold

        if not prompt:
            rec["issues"].append(("ERROR", "missing prompt"))
        if not gold:
            rec["issues"].append(("ERROR", "missing gold"))
        is_none = gold.upper() == "NONE"
        if not is_none and gold not in ids:
            rec["issues"].append(("ERROR", f"gold not in catalog: {gold}"))
        if near:
            if near not in ids:
                rec["issues"].append(("ERROR", f"near_miss not in catalog: {near}"))
            if near == gold:
                rec["issues"].append(("ERROR", "near_miss equals gold"))

        # Leakage gate (only meaningful for route tasks with a real gold).
        overlap = 0.0
        if not is_none and gold in ids:
            nt = name_tokens(gold)
            pt = tokenize(prompt)
            if nt:
                hit = nt & pt
                overlap = round(len(hit) / len(nt), 3)
                rec["leaked_tokens"] = sorted(hit)
                if overlap >= NAME_OVERLAP_ERROR:
                    rec["issues"].append(("ERROR", f"name_overlap {overlap} ≥ {NAME_OVERLAP_ERROR}: {sorted(hit)}"))
                elif overlap >= NAME_OVERLAP_WARN:
                    rec["issues"].append(("WARN", f"name_overlap {overlap} ≥ {NAME_OVERLAP_WARN}: {sorted(hit)}"))
        rec["name_overlap"] = overlap

        for sev, _ in rec["issues"]:
            if sev == "ERROR":
                errors += 1
            elif sev == "WARN":
                warns += 1
        rows.append(rec)

    if args.json:
        print(json.dumps(rows, indent=2))
    else:
        print("=== TASK AUDIT ===")
        n_none = sum(1 for r in rows if r.get("gold", "").upper() == "NONE")
        n_route = len(rows) - n_none
        print(f"TASK_COUNT={len(rows)}")
        print(f"ROUTE_TASKS={n_route}")
        print(f"NONE_TASKS={n_none}")
        print(f"ERROR_COUNT={errors}")
        print(f"WARN_COUNT={warns}")
        if errors or warns:
            print("ISSUES:")
            for r in rows:
                for sev, msg in r["issues"]:
                    print(f"  - SEVERITY={sev} TASK={r['task']} MSG={msg}")
        print(f"STATUS={'ERROR' if errors else ('WARN' if warns else 'OK')}")
        print(f"ISSUE_COUNT={errors + warns}")
        print("=== END TASK AUDIT ===")

    if args.strict and errors:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
