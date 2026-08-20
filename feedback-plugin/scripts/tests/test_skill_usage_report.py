#!/usr/bin/env python3
"""Regression tests for skill_usage_report.py.

Run: python3 feedback-plugin/scripts/tests/test_skill_usage_report.py

The fixtures mirror shapes taken from real data, not invented ones: the hook log
record is what hooks/skill-usage-log.sh emits, and the transcript lines carry
`attributionSkill` plus a `Skill` tool_use block as observed in
~/.claude/projects/**/*.jsonl.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORT = HERE.parent / "skill_usage_report.py"

FAILURES: list[str] = []


def check(desc: str, expected, actual) -> None:
    if expected == actual:
        print(f"  PASS: {desc}")
    else:
        FAILURES.append(desc)
        print(
            f"  FAIL: {desc}\n        expected: {expected!r}\n        actual:   {actual!r}"
        )


def iso(days_ago: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days_ago)).isoformat()


def write_log(path: Path, entries: list[tuple[str, str]]) -> None:
    with path.open("w") as fh:
        for skill, ts in entries:
            fh.write(
                json.dumps({"v": 1, "ts": ts, "src": "tool", "skill": skill}) + "\n"
            )


def make_catalog(root: Path, skills: list[tuple[str, str]]) -> None:
    for plugin, skill in skills:
        d = root / plugin / "skills" / skill
        d.mkdir(parents=True, exist_ok=True)
        (d / "SKILL.md").write_text("---\nname: x\n---\n")


def run_report(log: Path, catalog: Path, *extra: str) -> dict:
    proc = subprocess.run(
        [
            sys.executable,
            str(REPORT),
            "--log",
            str(log),
            "--catalog",
            str(catalog),
            "--json",
            *extra,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        log = tmp_path / "skill-usage.jsonl"
        catalog = tmp_path / "marketplace"
        empty_transcripts = tmp_path / "no-transcripts"
        empty_transcripts.mkdir()
        make_catalog(
            catalog,
            [
                ("git-plugin", "git-pr"),
                ("git-plugin", "git-triage"),
                ("x-plugin", "unused"),
            ],
        )

        print("=== bucketing ===")
        write_log(
            log, [("git-plugin:git-pr", iso(1)), ("git-plugin:git-triage", iso(45))]
        )
        out = run_report(
            log, catalog, "--since", "30d", "--transcripts", str(empty_transcripts)
        )
        check("catalog enumerated", 3, out["catalog"])
        check(
            "recent use is active",
            ["git-plugin:git-pr"],
            [r["skill"] for r in out["active"]],
        )
        check(
            "old use is dormant",
            ["git-plugin:git-triage"],
            [r["skill"] for r in out["dormant"]],
        )
        check("catalogued but unseen is never", ["x-plugin:unused"], out["never"])
        check("log records counted", 2, out["log_records"])

        print("=== counts and recency ===")
        write_log(
            log,
            [
                ("git-plugin:git-pr", iso(5)),
                ("git-plugin:git-pr", iso(2)),
                ("git-plugin:git-pr", iso(9)),
            ],
        )
        out = run_report(
            log, catalog, "--since", "30d", "--transcripts", str(empty_transcripts)
        )
        row = out["active"][0]
        check("invocations counted", 3, row["count"])
        check("last use is the newest, not the last line", True, row["last"] > iso(3))

        print("=== rotation is read ===")
        write_log(log, [("git-plugin:git-pr", iso(1))])
        write_log(
            log.with_suffix(log.suffix + ".1"), [("git-plugin:git-triage", iso(2))]
        )
        out = run_report(
            log, catalog, "--since", "30d", "--transcripts", str(empty_transcripts)
        )
        check("rotated log merged", 2, out["log_records"])

        print("=== transcript backfill ===")
        # An expiring transcript carries the same skill by two encodings.
        proj = tmp_path / "projects" / "p"
        proj.mkdir(parents=True)
        ts = iso(3)
        (proj / "s.jsonl").write_text(
            json.dumps({"timestamp": ts, "attributionSkill": "x-plugin:unused"})
            + "\n"
            + json.dumps(
                {
                    "timestamp": ts,
                    "message": {
                        "content": [
                            {
                                "type": "tool_use",
                                "name": "Skill",
                                "input": {"skill": "x-plugin:unused"},
                            }
                        ]
                    },
                }
            )
            + "\n"
        )
        write_log(log, [("git-plugin:git-pr", iso(1))])
        log.with_suffix(log.suffix + ".1").unlink()
        out = run_report(
            log, catalog, "--since", "30d", "--transcripts", str(proj.parent)
        )
        # git-triage has no record in either source here, so it stays "never"
        # in both runs; x-plugin:unused is the one the backfill should rescue.
        check(
            "transcripts ignored unless asked",
            ["git-plugin:git-triage", "x-plugin:unused"],
            out["never"],
        )
        out = run_report(
            log,
            catalog,
            "--since",
            "30d",
            "--transcripts",
            str(proj.parent),
            "--include-transcripts",
        )
        check(
            "backfilled skill leaves never-bucket",
            ["git-plugin:git-triage"],
            out["never"],
        )
        check("transcript files counted", 1, out["transcript_files"])

        print("=== empty log is distinguishable from no usage ===")
        log.write_text("")
        proc = subprocess.run(
            [
                sys.executable,
                str(REPORT),
                "--log",
                str(log),
                "--catalog",
                str(catalog),
                "--transcripts",
                str(empty_transcripts),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        check("STATUS=NO_DATA on an empty log", True, "STATUS=NO_DATA" in proc.stdout)
        check(
            "hint names the opt-in var",
            True,
            "CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG" in proc.stdout,
        )

        print("=== control: the harness can observe a real difference ===")
        # Without this, every assertion above would also pass against a report
        # that always emitted empty buckets.
        write_log(log, [("git-plugin:git-pr", iso(1))])
        out = run_report(
            log, catalog, "--since", "30d", "--transcripts", str(empty_transcripts)
        )
        check("control: one active row", 1, len(out["active"]))

    print()
    if FAILURES:
        print(f"FAILED={len(FAILURES)}")
        print("STATUS=ERROR")
        return 1
    print("FAILED=0")
    print("STATUS=OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
