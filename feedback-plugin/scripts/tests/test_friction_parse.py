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


def run_parser(fixture_dir: Path) -> list[dict]:
    proc = subprocess.run(
        [sys.executable, str(PARSER), "--root", str(fixture_dir), "--since", "3650d"],
        capture_output=True, text=True, check=True,
    )
    return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]


def test_plan_mode_legitimate_is_not_emitted():
    """Regression: ExitPlanMode on a change request must not emit plan_mode.

    Before the fix, every ExitPlanMode collapsed to plan:entered-plan-mode
    regardless of the preceding prompt, which inflated the cluster past
    --min-count 3 for legitimate plan-mode entries. (Issue #1061)
    """
    events = run_parser(FIXTURES / "plan_mode_legitimate")
    plan_events = [e for e in events if e["kind"] == "plan_mode"]
    assert not plan_events, f"expected 0 plan_mode events, got {plan_events}"


def test_plan_mode_qa_is_emitted():
    """ExitPlanMode after a 'how does X work?' prompt must still fire."""
    events = run_parser(FIXTURES / "plan_mode_qa")
    plan_events = [e for e in events if e["kind"] == "plan_mode"]
    assert len(plan_events) == 2, f"expected 2 plan_mode events, got {plan_events}"
    for ev in plan_events:
        assert ev["signature"] == "plan:entered-plan-mode", ev


def test_bash_antipatterns_blocked_format_classifies_by_pattern():
    """Regression: new BLOCKED-format hook output from PR #1378 must
    classify into specific sub-signatures, not the generic
    `hook:unclassified` bucket.

    Before this fix the parser only knew the old REMINDER-format needle
    table (branch-protection / pr metadata / conventional commit /
    gitleaks / pre-commit), so 26 of 29 BLOCKED-format bash-antipatterns
    events in the W22 friction window fell through to `hook:unclassified`.
    See ~/.claude/rules/friction/2026-W22-frictions.md "Proposed changes"
    #1 for the analysis.
    """
    events = run_parser(FIXTURES / "hook_block_bash_antipatterns")
    by_sig: dict[str, int] = {}
    for ev in events:
        by_sig[ev["signature"]] = by_sig.get(ev["signature"], 0) + 1

    # All 8 events should classify as hook_block kind with a specific signature.
    hook_blocks = [e for e in events if e["kind"] == "hook_block"]
    assert len(hook_blocks) == 8, f"expected 8 hook_block events, got {len(hook_blocks)}: {events}"

    # No event should fall through to the generic unclassified bucket.
    assert "hook:unclassified" not in by_sig, (
        f"BLOCKED-format events leaked into hook:unclassified: {by_sig}"
    )

    # Specific sub-signatures from PR #1378 substitution-format upgrade.
    assert by_sig.get("hook:bash-antipatterns:grep-rg") == 2, by_sig
    assert by_sig.get("hook:bash-antipatterns:find") == 1, by_sig
    assert by_sig.get("hook:bash-antipatterns:cat-head-tail") == 3, by_sig
    # Forward-compat: unrecognized bash-antipatterns BLOCKED format goes
    # to :other rather than disappearing into hook:unclassified.
    assert by_sig.get("hook:bash-antipatterns:other") == 1, by_sig
    # Sibling hook scripts classify by name, not bucketed as unclassified.
    assert by_sig.get("hook:secret-protection") == 1, by_sig


def test_tool_use_id_resolves_to_bash():
    """Regression: parser must resolve tool_use_id -> tool_name via assistant index.

    Before the fix, user-side tool errors reported tool='?' because neither
    toolUseName nor toolUseResult.toolName are populated on user records.
    (Issue #1059)
    """
    events = run_parser(FIXTURES / "bash_tool_error")
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
