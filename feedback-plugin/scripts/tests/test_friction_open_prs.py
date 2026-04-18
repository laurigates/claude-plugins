#!/usr/bin/env python3
"""Unit tests for friction_open_prs.py pure-logic helpers."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "friction_open_prs.py"

spec = importlib.util.spec_from_file_location("friction_open_prs", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)  # type: ignore[union-attr]


def test_repo_slug_accepts_slug():
    assert module.repo_slug("laurigates/claude-plugins") == "laurigates/claude-plugins"


def test_repo_slug_accepts_https_url():
    assert module.repo_slug("https://github.com/laurigates/claude-plugins.git") \
        == "laurigates/claude-plugins"


def test_repo_slug_accepts_ssh_url():
    assert module.repo_slug("git@github.com:laurigates/claude-plugins.git") \
        == "laurigates/claude-plugins"


def test_repo_short():
    assert module.repo_short("laurigates/claude-plugins") == "claude-plugins"


def test_quiet_window_skips_without_gh_or_repos():
    """CLI must early-exit on total_events < min-total-events.

    Regression: if this short-circuit breaks, the script would try to clone
    target repos on any run regardless of signal volume.
    """
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        clusters = tmp_path / "clusters.json"
        clusters.write_text(json.dumps({
            "total_events": 1, "actionable": [{"path": "x", "body": "y"}],
        }))
        body = tmp_path / "pr-body.md"
        body.write_text("# body")

        proc = subprocess.run(
            [sys.executable, str(SCRIPT),
             "--clusters", str(clusters),
             "--pr-body", str(body),
             "--target-repo", "laurigates/claude-plugins",
             "--min-total-events", "5",
             "--dry-run"],
            capture_output=True, text=True,
        )
        assert proc.returncode == 0, proc.stderr
        assert "quiet window" in proc.stderr, proc.stderr


def test_no_actionable_clusters_skips():
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        clusters = tmp_path / "clusters.json"
        clusters.write_text(json.dumps({"total_events": 99, "actionable": []}))
        body = tmp_path / "pr-body.md"
        body.write_text("# body")

        proc = subprocess.run(
            [sys.executable, str(SCRIPT),
             "--clusters", str(clusters),
             "--pr-body", str(body),
             "--target-repo", "laurigates/claude-plugins",
             "--dry-run"],
            capture_output=True, text=True,
        )
        assert proc.returncode == 0, proc.stderr
        assert "no actionable clusters" in proc.stderr, proc.stderr


def main() -> int:
    tests = [fn for name, fn in globals().items()
             if name.startswith("test_") and callable(fn)]
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
