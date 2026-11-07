#!/usr/bin/env python3
"""Regression tests for friction_cluster.py.

Run: python3 feedback-plugin/scripts/tests/test_friction_cluster.py
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLUSTER = HERE.parent / "friction_cluster.py"


def run_cluster(
    events: list[dict],
    min_count: int = 3,
    write_pr_body: bool = False,
    tmp_dir: Path | None = None,
) -> tuple[dict, str]:
    """Pipe events into friction_cluster.py and return (clusters_json, pr_body)."""
    stdin_text = "\n".join(json.dumps(e) for e in events) + "\n"
    args = [
        sys.executable,
        str(CLUSTER),
        "--in",
        "-",
        "--min-count",
        str(min_count),
        "--out",
        "-",
        # Hermetic: never read the runner's own plugin registry.
        "--installed-plugins",
        "",
    ]
    pr_body = ""
    if write_pr_body:
        assert tmp_dir is not None
        pr_path = tmp_dir / "pr-body.md"
        args += ["--render-pr-body", str(pr_path)]
    proc = subprocess.run(
        args, input=stdin_text, capture_output=True, text=True, check=True
    )
    clusters = json.loads(proc.stdout)
    if write_pr_body:
        pr_body = (tmp_dir / "pr-body.md").read_text(encoding="utf-8")
    return clusters, pr_body


def make_event(
    signature: str,
    kind: str = "user_reject",
    tool: str = "ExitPlanMode",
    evidence: str = "ev",
) -> dict:
    return {
        "session": "abc12345",
        "ts": "2026-04-22T10:00:00Z",
        "kind": kind,
        "signature": signature,
        "tool": tool,
        "evidence": evidence,
    }


def test_plan_mode_entry_does_not_auto_prescribe_qa_rule():
    """Regression: plan:entered-plan-mode must NOT auto-emit a hardcoded rule body.

    Before the fix, the clusterer hardcoded a "Avoid plan mode for conceptual Q&A"
    rule body for any plan:entered-plan-mode cluster, regardless of evidence.
    Issue #1110 showed this prescribed a fix that didn't match the actual signal
    (3 plan-mode entries vs 34 ExitPlanMode rejections).
    """
    events = [make_event("plan:entered-plan-mode", kind="plan_mode") for _ in range(5)]
    clusters, _ = run_cluster(events)

    [plan] = [
        p for p in clusters["actionable"] if p["signature"] == "plan:entered-plan-mode"
    ]
    assert plan["kind"] == "classify-required", plan
    assert plan["path"] == "", (
        "classify-required clusters must not write a committed file"
    )
    assert "Avoid plan mode for conceptual Q&A" not in plan["body"], (
        "auto-prescribed Q&A rule must not appear in the cluster body"
    )
    body_collapsed = " ".join(plan["body"].split())
    assert "Q&A heuristic produces false positives" in body_collapsed, (
        "classify-required body should explain the ambiguity"
    )


def test_stop_hook_feedback_clusters_are_measured_not_prescribed(tmp_path):
    """Issue #2659: `stop:*` clusters are reported for prevalence, never
    auto-prescribed. The fix for a noisy Stop hook lives in the hook itself
    (e.g. #2652 for auto-checkpoint stashes), so the clusterer must not emit a
    rule file for it the way it does for `hook:*` PreToolUse blocks.
    """
    sig = "stop:git-stash-reminder:auto-checkpoint"
    events = [make_event(sig, kind="stop_hook_feedback", tool="-") for _ in range(4)]
    clusters, pr_body = run_cluster(events, write_pr_body=True, tmp_dir=tmp_path)

    [stop] = [p for p in clusters["actionable"] if p["signature"] == sig]
    assert stop["kind"] == "watch", stop
    assert stop["path"] == "" and stop["body"] == "", (
        "a stop:* cluster must not write a committed file or render a rule body"
    )
    assert stop["title"] == f"Hook feedback: {sig}", stop["title"]
    # Prevalence is the point: the cluster appears in the report table.
    assert f"| `{sig}` | 4 | 1 | 1 | watch |" in pr_body, pr_body


def test_clusters_carry_session_prevalence_and_repeat():
    """Issue #2659's third acceptance criterion: the report must give prevalence
    and same-session repeat for `stop:*` clusters, not only a raw count. Every
    cluster therefore carries `sessions` (distinct sessions it fired in) and
    `repeat_sessions` (sessions where it fired at least twice), so the numbers
    come from the clusterer rather than being re-derived by hand each week.
    """
    sig = "stop:no-calendar-estimates"
    events = []
    for session, n in (("s1", 3), ("s2", 1), ("s3", 2)):
        for _ in range(n):
            ev = make_event(sig, kind="stop_hook_feedback", tool="-")
            ev["session"] = session
            events.append(ev)
    other = make_event("interrupt:user", kind="user_interrupt", tool="-")
    other["session"] = "s4"
    events.append(other)

    clusters, _ = run_cluster(events, min_count=1)
    [stop] = [p for p in clusters["actionable"] if p["signature"] == sig]
    assert stop["count"] == 6, stop["count"]
    assert stop["sessions"] == 3, stop
    assert stop["repeat_sessions"] == 2, stop
    assert clusters["total_sessions"] == 4, clusters["total_sessions"]


def test_pr_body_renders_prevalence_and_repeat(tmp_path):
    """Issue #2659 criterion 3 is about the REPORT, so the numbers must be in
    the rendered PR body, not only in clusters.json where the friction-learner
    agent would have to remember to copy them. Every cluster row carries its
    distinct-session count and its same-session-repeat count.
    """
    sig = "stop:no-calendar-estimates"
    events = []
    for session, n in (("s1", 3), ("s2", 1), ("s3", 2)):
        for _ in range(n):
            ev = make_event(sig, kind="stop_hook_feedback", tool="-")
            ev["session"] = session
            events.append(ev)
    _, pr_body = run_cluster(events, write_pr_body=True, tmp_dir=tmp_path)
    assert (
        "| Cluster | Count | Sessions | Repeat sessions | Deliverable | Path |"
        in pr_body
    ), pr_body
    assert f"| `{sig}` | 6 | 3 | 2 | watch |" in pr_body, pr_body


def test_exitplanmode_rejection_is_classify_required():
    """Regression: reject:exitplanmode must surface samples for human classification.

    Issue #1110: 34 ExitPlanMode rejections should not be silently demoted to
    a generic watch-only entry. The clusterer must produce a classify-required
    deliverable so the rejections appear in the PR body with sample evidence.
    """
    events = [make_event("reject:exitplanmode") for _ in range(4)]
    clusters, _ = run_cluster(events)

    [reject] = [
        p for p in clusters["actionable"] if p["signature"] == "reject:exitplanmode"
    ]
    assert reject["kind"] == "classify-required", reject
    assert reject["path"] == "", (
        "classify-required clusters must not write a committed file"
    )
    assert reject["title"].lower().startswith("exitplanmode rejections"), reject[
        "title"
    ]
    # Body must enumerate the classification options without prescribing one
    assert "Plan scope too broad" in reject["body"], reject["body"]
    assert "wanted an inline answer" in reject["body"], reject["body"]


def test_pr_body_has_classification_section(tmp_path):
    """The rendered PR body must include a 'Needs human classification' section
    when classify-required clusters exist, with sample evidence inline."""
    events = [
        make_event("plan:entered-plan-mode", kind="plan_mode", evidence="example plan")
    ] * 3 + [make_event("reject:exitplanmode", evidence="The user doesn't want")] * 4
    _, pr_body = run_cluster(events, write_pr_body=True, tmp_dir=tmp_path)

    assert "## Needs human classification" in pr_body, pr_body
    assert "Plan-mode entries" in pr_body
    assert "ExitPlanMode rejections" in pr_body
    assert "Sample evidence:" in pr_body
    # Auto-prescribed rule body must not leak into the PR
    assert "Avoid plan mode for conceptual Q&A" not in pr_body


def test_pr_body_proposed_changes_skips_classify_required(tmp_path):
    """classify-required clusters must NOT appear in the 'Proposed changes'
    section (which is meant for committed-file deliverables only)."""
    events = [make_event("plan:entered-plan-mode", kind="plan_mode")] * 3
    _, pr_body = run_cluster(events, write_pr_body=True, tmp_dir=tmp_path)

    proposed_idx = pr_body.find("## Proposed changes")
    assert proposed_idx >= 0, pr_body
    proposed_section = pr_body[proposed_idx:]
    # When classify-required is the only finding, the section should explicitly
    # state there are no auto-prescribed changes
    assert "_No auto-prescribed changes this run._" in proposed_section, (
        proposed_section
    )


PARSER = HERE.parent / "friction_parse.py"
BUILD_STAMP_FIXTURE = HERE / "fixtures" / "build_stamp"


def _cluster_fixture(tmp_path: Path, extra: list[str]) -> tuple[dict, str]:
    """Parse the build_stamp fixture and cluster it with the given flags."""
    parsed = subprocess.run(
        [
            sys.executable,
            str(PARSER),
            "--root",
            str(BUILD_STAMP_FIXTURE),
            "--since",
            "3650d",
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    pr_path = tmp_path / "pr-body.md"
    proc = subprocess.run(
        [sys.executable, str(CLUSTER), "--in", "-", "--out", "-"]
        + ["--render-pr-body", str(pr_path)]
        + extra,
        input=parsed,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout), pr_path.read_text(encoding="utf-8")


def test_build_share_per_plugin_version_with_current_marked(tmp_path):
    """#3220: the share of each plugin's build-stamped hook blocks per version,
    current release marked, in clusters.json and in the PR-body table.

    Fixture: hooks-plugin 3 blocks on 2.15.2 and 1 on 2.15.5, git-plugin 1 on
    1.40.0, one unstamped hook block, one tool error printing a cache path.
    """
    clusters, body = _cluster_fixture(
        tmp_path,
        ["--installed-plugins", "", "--current-version", "hooks-plugin=2.15.5"],
    )
    share = clusters["build_share"]
    assert share["hook_blocks"] == 6, share
    assert share["stamped_blocks"] == 5, share
    by_plugin = {p["plugin"]: p for p in share["plugins"]}
    hooks = by_plugin["hooks-plugin"]
    assert hooks["stamped_blocks"] == 4, hooks
    assert hooks["current_version"] == "2.15.5", hooks
    assert hooks["current_share_pct"] == 25.0, hooks
    assert hooks["versions"] == [
        {"version": "2.15.5", "count": 1, "share_pct": 25.0, "current": True},
        {"version": "2.15.2", "count": 3, "share_pct": 75.0, "current": False},
    ], hooks
    # Its own denominator: not diluted by hooks-plugin's blocks.
    git = by_plugin["git-plugin"]
    assert git["versions"] == [
        {"version": "1.40.0", "count": 1, "share_pct": 100.0, "current": False}
    ], git
    assert git["current_version"] is None and git["current_share_pct"] is None, git

    assert "## Build share" in body, body
    assert "Build-stamped hook blocks: 5 of 6." in body, body
    assert "| `hooks-plugin` | 2.15.5 (current) | 1 | 25.0% |" in body, body
    assert "| `hooks-plugin` | 2.15.2 | 3 | 75.0% |" in body, body
    assert "| `git-plugin` | 1.40.0 | 1 | 100.0% |" in body, body


def test_build_share_current_release_from_installed_plugins(tmp_path):
    """The user-scope entry marks the current release; a project-scope pin at
    the old version does not. A current release no block ran on is a 0.0% row,
    which is the W44 shape the row exists to expose."""
    registry = tmp_path / "installed_plugins.json"
    registry.write_text(
        json.dumps(
            {
                "version": 2,
                "plugins": {
                    "hooks-plugin@laurigates-claude-plugins": [
                        {"scope": "project", "projectPath": "/p", "version": "2.15.2"},
                        {"scope": "user", "version": "2.15.5"},
                    ],
                    "git-plugin@laurigates-claude-plugins": [
                        {"scope": "user", "version": "1.41.0"}
                    ],
                },
            }
        ),
        encoding="utf-8",
    )
    clusters, body = _cluster_fixture(tmp_path, ["--installed-plugins", str(registry)])
    by_plugin = {p["plugin"]: p for p in clusters["build_share"]["plugins"]}
    assert by_plugin["hooks-plugin"]["current_version"] == "2.15.5", by_plugin
    assert by_plugin["hooks-plugin"]["current_share_pct"] == 25.0, by_plugin
    assert by_plugin["git-plugin"]["current_share_pct"] == 0.0, by_plugin
    assert "| `git-plugin` | 1.41.0 (current) | 0 | 0.0% |" in body, body


def test_build_share_row_renders_when_nothing_is_stamped(tmp_path):
    """Standing row: present even in a window with no stamped hook blocks."""
    events = [make_event("hook:unclassified", kind="hook_block", tool="Bash")] * 3
    _, body = run_cluster(events, write_pr_body=True, tmp_dir=tmp_path)
    assert "## Build share" in body, body
    assert "_No build-stamped hook blocks in the window._" in body, body


def main() -> int:
    import inspect
    import tempfile

    tests = [
        (name, fn)
        for name, fn in globals().items()
        if name.startswith("test_") and callable(fn)
    ]
    failed = 0
    for name, fn in tests:
        try:
            sig = inspect.signature(fn)
            if "tmp_path" in sig.parameters:
                with tempfile.TemporaryDirectory() as td:
                    fn(Path(td))
            else:
                fn()
            print(f"PASS {name}")
        except AssertionError as err:
            failed += 1
            print(f"FAIL {name}: {err}")
        except Exception as err:
            failed += 1
            print(f"FAIL {name}: {type(err).__name__}: {err}")
    if failed:
        print(f"\n{failed}/{len(tests)} test(s) failed")
        return 1
    print(f"\n{len(tests)}/{len(tests)} test(s) passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
