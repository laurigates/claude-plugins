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


def run_cluster(events: list[dict], min_count: int = 3, write_pr_body: bool = False, tmp_dir: Path | None = None) -> tuple[dict, str]:
    """Pipe events into friction_cluster.py and return (clusters_json, pr_body)."""
    stdin_text = "\n".join(json.dumps(e) for e in events) + "\n"
    args = [sys.executable, str(CLUSTER), "--in", "-", "--min-count", str(min_count), "--out", "-"]
    pr_body = ""
    if write_pr_body:
        assert tmp_dir is not None
        pr_path = tmp_dir / "pr-body.md"
        args += ["--render-pr-body", str(pr_path)]
    proc = subprocess.run(args, input=stdin_text, capture_output=True, text=True, check=True)
    clusters = json.loads(proc.stdout)
    if write_pr_body:
        pr_body = (tmp_dir / "pr-body.md").read_text(encoding="utf-8")
    return clusters, pr_body


def make_event(signature: str, kind: str = "user_reject", tool: str = "ExitPlanMode", evidence: str = "ev") -> dict:
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

    [plan] = [p for p in clusters["actionable"] if p["signature"] == "plan:entered-plan-mode"]
    assert plan["kind"] == "classify-required", plan
    assert plan["path"] == "", "classify-required clusters must not write a committed file"
    assert "Avoid plan mode for conceptual Q&A" not in plan["body"], (
        "auto-prescribed Q&A rule must not appear in the cluster body"
    )
    body_collapsed = " ".join(plan["body"].split())
    assert "Q&A heuristic produces false positives" in body_collapsed, (
        "classify-required body should explain the ambiguity"
    )


def test_exitplanmode_rejection_is_classify_required():
    """Regression: reject:exitplanmode must surface samples for human classification.

    Issue #1110: 34 ExitPlanMode rejections should not be silently demoted to
    a generic watch-only entry. The clusterer must produce a classify-required
    deliverable so the rejections appear in the PR body with sample evidence.
    """
    events = [make_event("reject:exitplanmode") for _ in range(4)]
    clusters, _ = run_cluster(events)

    [reject] = [p for p in clusters["actionable"] if p["signature"] == "reject:exitplanmode"]
    assert reject["kind"] == "classify-required", reject
    assert reject["path"] == "", "classify-required clusters must not write a committed file"
    assert reject["title"].lower().startswith("exitplanmode rejections"), reject["title"]
    # Body must enumerate the classification options without prescribing one
    assert "Plan scope too broad" in reject["body"], reject["body"]
    assert "wanted an inline answer" in reject["body"], reject["body"]


def test_pr_body_has_classification_section(tmp_path):
    """The rendered PR body must include a 'Needs human classification' section
    when classify-required clusters exist, with sample evidence inline."""
    events = (
        [make_event("plan:entered-plan-mode", kind="plan_mode", evidence="example plan")]
        * 3
        + [make_event("reject:exitplanmode", evidence="The user doesn't want")] * 4
    )
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
    assert "_No auto-prescribed changes this run._" in proposed_section, proposed_section


def main() -> int:
    import inspect
    import tempfile

    tests = [
        (name, fn) for name, fn in globals().items()
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
