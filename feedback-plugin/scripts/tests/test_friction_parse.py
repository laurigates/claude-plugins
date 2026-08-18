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
REPO_ROOT = HERE.parent.parent.parent
HOOK_SCRIPT = REPO_ROOT / "hooks-plugin" / "hooks" / "bash-antipatterns.sh"


def deployed_head_tail_block_message() -> str:
    """Extract the head/tail block message from the DEPLOYED hook source.

    A retyped copy of the message is not the message: its byte length is what
    decides whether the tail survives truncation, so the fixture must be built
    from the shipped text, not from an approximation of it.
    """
    raw = subprocess.run(
        [
            "sed",
            "-n",
            '/if ast_matched "head-tail-read"; then/,/^    fi$/p',
            str(HOOK_SCRIPT),
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    start = raw.index('block "') + len('block "')
    end = raw.rindex('"')
    return raw[start:end].replace('\\"', '"')


def fixture_evidence_source(fixture_dir: Path) -> str:
    """The untruncated tool_result content the fixture feeds the parser."""
    for line in (fixture_dir / "t.jsonl").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        for item in rec.get("message", {}).get("content", []) or []:
            if isinstance(item, dict) and item.get("type") == "tool_result":
                return item["content"]
    raise AssertionError(f"no tool_result in {fixture_dir}")


def run_parser(fixture_dir: Path) -> list[dict]:
    proc = subprocess.run(
        [sys.executable, str(PARSER), "--root", str(fixture_dir), "--since", "3650d"],
        capture_output=True,
        text=True,
        check=True,
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
    assert len(hook_blocks) == 8, (
        f"expected 8 hook_block events, got {len(hook_blocks)}: {events}"
    )

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
    assert "?" not in tools, (
        f"parser emitted tool='?' for {len(events)} event(s): {events}"
    )
    by_kind = {e["kind"]: e for e in events}
    assert "tool_error" in by_kind, (
        f"expected tool_error event, got kinds={list(by_kind)}"
    )
    assert by_kind["tool_error"]["tool"] == "Bash", by_kind["tool_error"]
    assert by_kind["tool_error"]["signature"].startswith("error:bash"), by_kind[
        "tool_error"
    ]
    assert "user_reject" in by_kind, (
        f"expected user_reject event, got kinds={list(by_kind)}"
    )
    assert by_kind["user_reject"]["tool"] == "Edit", by_kind["user_reject"]
    assert by_kind["user_reject"]["signature"] == "reject:edit", by_kind["user_reject"]


def test_not_found_signature_matches_only_shell_forms():
    """Regression: `error:bash:not-found` must not absorb every payload that
    happens to say "not found".

    The signature regex used a bare `\\bnot found\\b`, so any tool output
    reporting an absent *thing* (kubectl `pods "x" not found`, Blender
    `enum "X" not found`) was clustered as a shell/PATH lookup failure. In the
    W32 window that made `error:bash:not-found` the 3rd-largest signature by
    raw count -- 28 events / 20 sessions -- of which exactly 1 was genuine
    (3.6%), a 4.7x growth in the artifact over W31's 6 events.
    See ~/.claude/friction-reports/2026-W32-frictions.md.
    """
    events = run_parser(FIXTURES / "regex_overmatch")

    kubectl = next(e for e in events if "Error from server" in e["evidence"])
    assert kubectl["signature"] == "error:bash", (
        f"kubectl NotFound must not classify as not-found: {kubectl}"
    )

    blender = next(e for e in events if "bpy_struct" in e["evidence"])
    assert blender["signature"] == "error:bash", (
        f"Blender enum lookup must not classify as not-found: {blender}"
    )

    pnpm = next(e for e in events if "pnpm" in e["evidence"])
    assert pnpm["signature"] == "error:bash:not-found", (
        f"a real `command not found` must still classify as not-found: {pnpm}"
    )


def test_exit_code_2_is_not_a_hook_block():
    """Regression: `hook_block` must be identified by the harness's own
    wrapper prose, never by a bare "exit code 2" appearing in tool output.

    `ugrep` exits 2 on a missing file and says so in its output, so those
    events landed in `hook_block` and fell through to `hook:unclassified`.
    In W32 that was 6 events -- 27% of all `hook_block` events were not hook
    blocks at all, silently inflating the hook-friction numbers the weekly
    report is built on.
    """
    events = run_parser(FIXTURES / "regex_overmatch")

    ugrep = next(e for e in events if "ugrep" in e["evidence"])
    assert ugrep["kind"] == "tool_error", (
        f"exit-code-2 tool output must not classify as hook_block: {ugrep}"
    )
    assert ugrep["signature"] != "hook:unclassified", ugrep

    hook = next(e for e in events if "PreToolUse:Bash hook error" in e["evidence"])
    assert hook["kind"] == "hook_block", (
        f"a real PreToolUse hook error must still classify as hook_block: {hook}"
    )
    assert hook["signature"] == "hook:bash-antipatterns:cat-head-tail", hook


def test_evidence_budget_reaches_hook_message_tail():
    """Regression: `evidence` must survive far enough to carry the marker that
    distinguishes the post-#2148 head/tail block message from its ancestor.

    The harness wraps a hook block as
    "PreToolUse:Bash hook error: [bash <abs-path>/bash-antipatterns.sh]: ...",
    so the hook's own prose starts ~150 chars in. At the former 400-char
    truncation the message was cut before "This fires only when the read is the
    WHOLE command", making the current message indistinguishable from the
    pre-#2148 one in parser output. In the W33 window that manufactured 12
    phantom "legacy" hook blocks: a naive read of parser output gave 15
    post-fix / 12 legacy, while recovering the same events from the raw
    transcripts gave 27 / 0.
    See ~/.claude/friction-reports/2026-W33-frictions.md.
    """
    fixture = FIXTURES / "evidence_budget"
    marker = "WHOLE command"

    # Fixture validity: the marker must genuinely sit past the old boundary,
    # or this test would pass against the unpatched constant.
    source = fixture_evidence_source(fixture)
    offset = source.index(marker)
    assert offset > 400, (
        f"fixture does not exercise the truncation: marker at char {offset}"
    )

    # The fixture must carry the message the hook actually ships, byte for byte.
    deployed = deployed_head_tail_block_message()
    assert deployed in source, (
        "fixture drifted from hooks-plugin/hooks/bash-antipatterns.sh; "
        "regenerate it from the deployed block message"
    )

    events = run_parser(fixture)
    hook_blocks = [e for e in events if e["kind"] == "hook_block"]
    assert len(hook_blocks) == 1, f"expected 1 hook_block event, got {events}"

    evidence = hook_blocks[0]["evidence"]
    assert marker in evidence, (
        f"evidence truncated before the message tail (len={len(evidence)}, "
        f"marker at {offset} in the source): {evidence!r}"
    )


def test_worktree_isolation_splits_out_of_generic_error_bash():
    """Regression: the harness's worktree-isolation refusal must carry its own
    signature instead of falling into the generic `error:bash` bucket.

    The guard is emitted by the Claude Code binary (2.1.231-2.1.233), not by a
    hook, so it never carries the PreToolUse wrapper `HOOK_BLOCK_RE` keys on
    and lands in `tool_error`. In the W34 window it was 176 events: 52.0% of
    the `error:bash` bucket and 31.8% of ALL friction. Merged into the bucket
    it made `error:bash` clear both of W33's pre-registered escalation axes
    (85.1% prevalence / 64.9% repeat) while the residual was flat against W33
    (64.9% / 52.7% vs 65.6% / 52.5%) -- i.e. the gate fired on a confound.
    See ~/.claude/friction-reports/2026-W34-frictions.md (PR-READY 2).
    """
    events = run_parser(FIXTURES / "worktree_isolation")
    by_sig = {e["signature"]: e for e in events}

    # No guard refusal may remain in the generic bucket...
    guard = [e for e in events if "isolated in the worktree" in e["evidence"]]
    assert len(guard) == 4, f"expected 4 guard events, got {len(guard)}: {events}"
    for ev in guard:
        assert ":worktree-isolation:" in ev["signature"], (
            f"guard refusal left in the generic bucket: {ev}"
        )

    # ...and the variants split by OWNER, which is the point of the split.
    assert "error:bash:worktree-isolation:unverifiable" in by_sig, (
        f"missing the upstream-false-positive variant: {sorted(by_sig)}"
    )
    assert "error:bash:worktree-isolation:cross-repo" in by_sig, (
        f"missing the dispatch-defect variant: {sorted(by_sig)}"
    )
    assert "error:bash:worktree-isolation:worktree-gone" in by_sig, (
        f"missing the cleanup-defect variant: {sorted(by_sig)}"
    )

    # Ordering trap: the worktree-gone message also names the "shared
    # checkout" (as the recovery target), so a cross-repo test placed first
    # would swallow it.
    gone = by_sig["error:bash:worktree-isolation:worktree-gone"]
    assert "shared checkout" in gone["evidence"], (
        "fixture no longer exercises the ordering trap; regenerate it from a "
        "real working-directory-gone refusal"
    )

    # The guard also fires on Monitor's shell argument (9 of the W34 176), so
    # the signature stays tool-keyed rather than hardcoding `bash`.
    assert "error:monitor:worktree-isolation:unverifiable" in by_sig, (
        f"Monitor-tool guard events must not be flattened into bash: {sorted(by_sig)}"
    )


def test_plain_bash_error_still_classifies_as_error_bash():
    """Control: an ordinary Bash failure keeps the generic `error:bash` key.

    The split must move only the guard refusals; a zero-delta on every other
    signature is what makes W35's `error:bash` reading comparable to W33's.
    """
    events = run_parser(FIXTURES / "worktree_isolation")
    plain = [e for e in events if "isolated in the worktree" not in e["evidence"]]
    assert len(plain) == 1, f"expected 1 non-guard event, got {plain}"
    assert plain[0]["signature"] == "error:bash", (
        f"a plain bash error must stay in the generic bucket: {plain[0]}"
    )


def main() -> int:
    tests = [
        fn
        for name, fn in globals().items()
        if name.startswith("test_") and callable(fn)
    ]
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
