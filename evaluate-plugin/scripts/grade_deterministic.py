#!/usr/bin/env python3
"""Deterministic grader for skill eval expectations.

Grades the machine-checkable expectations in an evals.json eval case against a
captured skill output, WITHOUT spending LLM judge tokens. Expectations whose
``check`` type is ``judge`` (or plain-string expectations, which default to
``judge``) are reported as DEFERRED so the LLM grader only ever runs on the
genuinely fuzzy assertions.

This is the core token-frugality lever of the cross-model evaluation framework:
on the git-commit eval set ~70% of expectations are regex/substring checks that
cost zero model tokens to grade.

Expectation forms accepted in evals.json (``expectations`` may mix both):

  "Commit message starts with feat("          # string -> check: judge

  {                                            # object -> typed check
    "assertion": "Commit message starts with feat(",
    "check": "regex",
    "pattern": "^feat\\(",
    "scope": "subject"
  }

Check types:
  regex          pattern matches (re.search) within scope
  substring      value is present within scope
  substring_all  every entry in values[] is present within scope
  absent_regex   pattern does NOT match within scope
  judge          deferred to the LLM grader (default for bare strings)

Optional fields on a typed check:
  scope   full | subject | body   (default: full)
  flags   any of "imsx"           (regex flags; applied to regex/absent_regex)

Usage:
  grade_deterministic.py --evals <evals.json> --eval-id <id> \
    --output <file|-> [--json] [--strict]

Output: structured KEY=value section by default; full JSON with --json.
Exit code: 0 normally; with --strict, 1 when a deterministic check fails.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def _scope_text(text: str, scope: str) -> str:
    """Return the slice of ``text`` named by ``scope``."""
    if scope == "subject":
        for line in text.splitlines():
            if line.strip():
                return line
        return ""
    if scope == "body":
        parts = text.split("\n\n", 1)
        return parts[1] if len(parts) == 2 else ""
    return text


def _compile_flags(flags: str) -> int:
    table = {"i": re.IGNORECASE, "m": re.MULTILINE, "s": re.DOTALL, "x": re.VERBOSE}
    value = 0
    for ch in flags or "":
        if ch not in table:
            raise ValueError(f"unknown regex flag: {ch!r}")
        value |= table[ch]
    return value


def grade_expectation(exp, output: str) -> dict:
    """Grade one expectation. Returns a result dict with a ``deferred`` flag."""
    # Bare string -> deferred to the LLM judge.
    if isinstance(exp, str):
        return {"assertion": exp, "check": "judge", "deferred": True}

    assertion = exp.get("assertion", "")
    check = exp.get("check", "judge")
    scope = exp.get("scope", "full")
    text = _scope_text(output, scope)

    if check == "judge":
        return {"assertion": assertion, "check": "judge", "deferred": True}

    try:
        if check == "regex":
            flags = _compile_flags(exp.get("flags", ""))
            ok = re.search(exp["pattern"], text, flags) is not None
            evidence = f"/{exp['pattern']}/ {'matched' if ok else 'no match'} in {scope}"
        elif check == "absent_regex":
            flags = _compile_flags(exp.get("flags", ""))
            ok = re.search(exp["pattern"], text, flags) is None
            evidence = f"/{exp['pattern']}/ {'absent (ok)' if ok else 'present (fail)'} in {scope}"
        elif check == "substring":
            ok = exp["value"] in text
            evidence = f"{exp['value']!r} {'found' if ok else 'missing'} in {scope}"
        elif check == "substring_all":
            missing = [v for v in exp["values"] if v not in text]
            ok = not missing
            evidence = "all present" if ok else f"missing {missing!r} in {scope}"
        else:
            return {
                "assertion": assertion,
                "check": check,
                "deferred": True,
                "evidence": f"unknown check type {check!r} -> deferred",
            }
    except KeyError as err:
        return {
            "assertion": assertion,
            "check": check,
            "passed": False,
            "deferred": False,
            "evidence": f"malformed check, missing field {err}",
        }

    return {
        "assertion": assertion,
        "check": check,
        "passed": ok,
        "deferred": False,
        "evidence": evidence,
    }


def grade_eval_case(eval_case: dict, output: str) -> dict:
    results = [grade_expectation(e, output) for e in eval_case.get("expectations", [])]
    deterministic = [r for r in results if not r.get("deferred")]
    deferred = [r for r in results if r.get("deferred")]
    passed = sum(1 for r in deterministic if r.get("passed"))
    failed = len(deterministic) - passed
    return {
        "eval_id": eval_case.get("id", ""),
        "deterministic": deterministic,
        "deferred": deferred,
        "summary": {
            "deterministic_total": len(deterministic),
            "deterministic_passed": passed,
            "deterministic_failed": failed,
            "judge_pending": len(deferred),
        },
    }


def render_structured(graded: dict) -> tuple[str, int]:
    """Render the KEY=value section. Returns (text, exit_status_severity)."""
    s = graded["summary"]
    if s["deterministic_failed"] > 0:
        status, severity = "ERROR", 1
    elif s["judge_pending"] > 0:
        status, severity = "WARN", 0
    else:
        status, severity = "OK", 0

    lines = ["=== DETERMINISTIC GRADING ==="]
    lines.append(f"EVAL_ID={graded['eval_id']}")
    lines.append(f"DETERMINISTIC_TOTAL={s['deterministic_total']}")
    lines.append(f"DETERMINISTIC_PASSED={s['deterministic_passed']}")
    lines.append(f"DETERMINISTIC_FAILED={s['deterministic_failed']}")
    lines.append(f"JUDGE_PENDING={s['judge_pending']}")
    lines.append(f"STATUS={status}")
    lines.append(f"ISSUE_COUNT={s['deterministic_failed']}")
    lines.append("RESULTS:")
    for r in graded["deterministic"]:
        verdict = "PASS" if r.get("passed") else "FAIL"
        lines.append(f"  - CHECK={r['check']} RESULT={verdict} ASSERTION={r['assertion']!r}")
    for r in graded["deferred"]:
        lines.append(f"  - CHECK={r['check']} RESULT=DEFERRED ASSERTION={r['assertion']!r}")
    lines.append("=== END DETERMINISTIC GRADING ===")
    return "\n".join(lines), severity


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Deterministic skill-eval grader")
    parser.add_argument("--evals", required=True, help="Path to evals.json")
    parser.add_argument("--eval-id", required=True, help="Eval case id to grade")
    parser.add_argument("--output", required=True, help="Skill output file, or - for stdin")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of KEY=value")
    parser.add_argument("--strict", action="store_true", help="Exit 1 when a deterministic check fails")
    args = parser.parse_args(argv)

    evals = json.loads(Path(args.evals).read_text())
    eval_case = next((e for e in evals.get("evals", []) if e.get("id") == args.eval_id), None)
    if eval_case is None:
        print(f"ERROR: eval id {args.eval_id!r} not found in {args.evals}", file=sys.stderr)
        return 2

    output = sys.stdin.read() if args.output == "-" else Path(args.output).read_text()
    graded = grade_eval_case(eval_case, output)

    if args.json:
        print(json.dumps(graded, indent=2))
        severity = 1 if graded["summary"]["deterministic_failed"] > 0 else 0
    else:
        text, severity = render_structured(graded)
        print(text)

    return severity if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
