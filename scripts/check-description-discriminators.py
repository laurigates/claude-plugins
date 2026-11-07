#!/usr/bin/env python3
"""Pin the discriminating phrase each sibling skill's description relies on.

Issue #2244: sibling skills that describe one intent in the same words give
the router nothing to tell them apart. A cluster is fixed by rewriting each
member's description so that it leads with what that skill owns and drops
territory a sibling owns. Nothing kept those rewrites in place: the
description-length pass in #2119 compresses descriptions toward a short
capability head, which is exactly where a discriminator lives, and a
length-only gate passes a description that lost it.

This check reads pins from `scripts/description-discriminators.tsv`:

    <SKILL.md path>  <require|forbid>  <regex>  <reason>

* `require`: the description must match the regex (case-insensitive,
  Python `re.search`; anchor with `^` to pin the head).
* `forbid`: the description must not match it. Use it for a trigger phrase
  that belongs to a sibling, so it cannot creep back in.

Descriptions come from `scripts/audit-skill-descriptions.py --json --all
--list` and its `description_full` key (the `description` key is a 120-char
preview, and a pinned phrase past it would be invisible). A pin naming a
skill the audit does not report is an ERROR (`stale_pin`), so renaming or
deleting a skill cannot silently retire its pins.

Output follows .claude/rules/structured-script-output.md. Any violated pin
is `STATUS=ERROR` (exit 1). Unreadable input, a malformed pin line, or zero
pins is also ERROR, so a misfire never reads as a clean corpus (#2219).

Usage:
    python3 scripts/check-description-discriminators.py
    python3 scripts/check-description-discriminators.py --pins FILE --input audit.json
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PINS = REPO_ROOT / "scripts" / "description-discriminators.tsv"
MODES = ("require", "forbid")


def emit(counters: dict[str, object], issues: list[tuple[str, str]]) -> int:
    print("=== DESCRIPTION DISCRIMINATORS ===")
    for key, value in counters.items():
        print(f"{key}={value}")
    status = "ERROR" if issues else "OK"
    print(f"STATUS={status}")
    if issues:
        first_type, first_msg = issues[0]
        more = f" (+{len(issues) - 1} more)" if len(issues) > 1 else ""
        cause = " ".join(f"{first_type}: {first_msg}".split())[:180]
        print(f"REASON={cause}{more}")
    print(f"ISSUE_COUNT={len(issues)}")
    if issues:
        print("ISSUES:")
        for issue_type, msg in issues:
            print(f"  - SEVERITY=ERROR TYPE={issue_type} MSG={msg}")
    print("=== END DESCRIPTION DISCRIMINATORS ===")
    return 1 if issues else 0


def load_pins(
    path: Path,
) -> tuple[list[tuple[int, str, str, re.Pattern[str], str]], list[tuple[str, str]]]:
    pins: list[tuple[int, str, str, re.Pattern[str], str]] = []
    errors: list[tuple[str, str]] = []
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return pins, [("unreadable_pins", f"cannot read {path}: {exc}")]
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 4 or not all(f.strip() for f in fields):
            errors.append(
                (
                    "malformed_pin",
                    f"{path.name}:{lineno} needs 4 non-empty tab-separated fields",
                )
            )
            continue
        skill_path, mode, pattern, reason = (f.strip() for f in fields)
        if mode not in MODES:
            errors.append(
                (
                    "malformed_pin",
                    f"{path.name}:{lineno} mode '{mode}' is not require or forbid",
                )
            )
            continue
        try:
            regex = re.compile(pattern, re.IGNORECASE)
        except re.error as exc:
            errors.append(
                ("malformed_pin", f"{path.name}:{lineno} regex does not compile: {exc}")
            )
            continue
        pins.append((lineno, skill_path, mode, regex, reason))
    return pins, errors


def load_descriptions(args: argparse.Namespace) -> tuple[dict[str, str] | None, str]:
    if args.input is not None:
        try:
            raw = (
                sys.stdin.read()
                if args.input == "-"
                else Path(args.input).read_text(encoding="utf-8")
            )
        except OSError as exc:
            return None, f"cannot read input: {exc}"
    else:
        audit = Path(args.project_dir) / "scripts" / "audit-skill-descriptions.py"
        cmd = [sys.executable, str(audit), "--json", "--all", "--list"]
        try:
            proc = subprocess.run(
                cmd, capture_output=True, text=True, check=False, cwd=args.project_dir
            )
        except OSError as exc:
            return None, f"cannot run audit: {exc}"
        if proc.returncode != 0:
            first = (proc.stderr.strip().splitlines() or ["no stderr"])[0]
            return None, f"audit exited {proc.returncode}: {first}"
        raw = proc.stdout
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"input is not JSON: {exc}"
    if not isinstance(data, list):
        return None, "input is not a JSON array of audit records"
    descriptions: dict[str, str] = {}
    for record in data:
        if not isinstance(record, dict) or not isinstance(record.get("path"), str):
            continue
        full = record.get("description_full")
        if not isinstance(full, str):
            return (
                None,
                f"record {record['path']} has no description_full (preview-only input)",
            )
        descriptions[record["path"]] = full
    return descriptions, ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--pins",
        default=str(DEFAULT_PINS),
        help="pin file (default scripts/description-discriminators.tsv)",
    )
    ap.add_argument(
        "--input",
        help="read audit JSON from FILE ('-' for stdin) instead of running the audit",
    )
    ap.add_argument(
        "--project-dir",
        default=str(REPO_ROOT),
        help="repo root holding scripts/audit-skill-descriptions.py",
    )
    args = ap.parse_args()

    pins, issues = load_pins(Path(args.pins))
    descriptions, err = load_descriptions(args)
    if descriptions is None:
        return emit(
            {"PINS": len(pins), "PINS_CHECKED": 0}, [*issues, ("malformed_input", err)]
        )
    if not descriptions:
        return emit(
            {"PINS": len(pins), "PINS_CHECKED": 0},
            [*issues, ("nothing_scanned", "audit reported zero skills")],
        )
    if not pins and not issues:
        return emit(
            {"PINS": 0, "PINS_CHECKED": 0},
            [("nothing_scanned", f"no pins in {args.pins}")],
        )

    checked = 0
    for lineno, skill_path, mode, regex, reason in pins:
        desc = descriptions.get(skill_path)
        if desc is None:
            issues.append(
                (
                    "stale_pin",
                    f"line {lineno}: {skill_path} is not in the audit (renamed or deleted?)",
                )
            )
            continue
        checked += 1
        matched = regex.search(desc) is not None
        if mode == "require" and not matched:
            issues.append(
                (
                    "missing_discriminator",
                    f"{skill_path} must match /{regex.pattern}/ ({reason})",
                )
            )
        elif mode == "forbid" and matched:
            issues.append(
                (
                    "sibling_trigger",
                    f"{skill_path} must not match /{regex.pattern}/ ({reason})",
                )
            )

    return emit(
        {
            "SKILLS_SCANNED": len(descriptions),
            "PINS": len(pins),
            "PINS_CHECKED": checked,
        },
        issues,
    )


if __name__ == "__main__":
    sys.exit(main())
