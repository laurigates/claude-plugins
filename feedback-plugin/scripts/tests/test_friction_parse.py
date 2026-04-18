#!/usr/bin/env python3
"""Regression tests for friction_parse.py.

Run: python3 feedback-plugin/scripts/tests/test_friction_parse.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PARSER = HERE.parent / "friction_parse.py"
FIXTURES = HERE / "fixtures"


def run_parser(fixture: Path) -> list[dict]:
    proc = subprocess.run(
        [sys.executable, str(PARSER), "--root", str(fixture.parent), "--since", "3650d"],
        capture_output=True, text=True, check=True,
    )
    return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]


def test_tool_use_id_resolves_to_bash():
    """Regression: parser must resolve tool_use_id -> tool_name via assistant index.

    Before the fix, user-side tool errors reported tool='?' because neither
    toolUseName nor toolUseResult.toolName are populated on user records.
    (Issue #1059)
    """
    events = run_parser(FIXTURES / "bash_tool_error.jsonl")
    tools = [e["tool"] for e in events]
    assert "?" not in tools, f"parser emitted tool='?' for {len(events)} event(s): {events}"
    by_kind = {e["kind"]: e for e in events}
    assert "tool_error" in by_kind, f"expected tool_error event, got kinds={list(by_kind)}"
    assert by_kind["tool_error"]["tool"] == "Bash", by_kind["tool_error"]
    assert by_kind["tool_error"]["signature"].startswith("error:bash"), by_kind["tool_error"]
    assert "user_reject" in by_kind, f"expected user_reject event, got kinds={list(by_kind)}"
    assert by_kind["user_reject"]["tool"] == "Edit", by_kind["user_reject"]
    assert by_kind["user_reject"]["signature"] == "reject:edit", by_kind["user_reject"]


def main() -> int:
    tests = [fn for name, fn in globals().items() if name.startswith("test_") and callable(fn)]
    failed = 0
    for fn in tests:
        try:
            fn()
            print(f"PASS {fn.__name__}")
        except AssertionError as err:
            failed += 1
            print(f"FAIL {fn.__name__}: {err}")
    if failed:
        print(f"\n{failed}/{len(tests)} test(s) failed")
        return 1
    print(f"\n{len(tests)}/{len(tests)} test(s) passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
