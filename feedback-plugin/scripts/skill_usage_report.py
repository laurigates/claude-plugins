#!/usr/bin/env python3
"""Rank skills by last use, so the slow loop can target its analysis.

Reads two sources and merges them, newest-wins per skill:

  1. ``~/.claude/skill-usage.jsonl`` — the durable per-invocation log written by
     ``hooks/skill-usage-log.sh`` (opt-in). Never trimmed, so it is the source
     that accumulates.
  2. ``~/.claude/projects/**/*.jsonl`` — session transcripts, mined for
     ``attributionSkill`` and ``Skill`` tool calls (``--include-transcripts``).
     These EXPIRE, which is the whole reason source 1 exists; use them to
     backfill history predating the hook.

Against the installed skill catalog this yields three buckets:

  active    used inside the window
  dormant   used, but not inside the window
  never     in the catalog with no record in either source

`never` is a FLOOR, not a verdict. A skill last used before the earliest record
in either source is indistinguishable from one never used — the report prints
COVERAGE_SINCE so the reader can tell how far back "never" actually reaches.

Output follows .claude/rules/structured-script-output.md (KEY=VALUE inside
=== SECTION === delimiters); --json emits the same data for an agent to consume.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
DEFAULT_LOG = HOME / ".claude" / "skill-usage.jsonl"
DEFAULT_TRANSCRIPTS = HOME / ".claude" / "projects"
# The marketplace checkout this script ships inside: <repo>/feedback-plugin/scripts/
DEFAULT_CATALOG = Path(__file__).resolve().parents[2]

# Whitespace-tolerant: live transcripts are compact ("k":"v"), but any producer
# using json.dumps defaults emits ("k": "v") and would silently never match.
ATTRIBUTION_RE = re.compile(r'"attributionSkill"\s*:\s*"([^"]+)"')
TIMESTAMP_RE = re.compile(r'"timestamp"\s*:\s*"([^"]+)"')


def parse_since(spec: str) -> timedelta:
    """Accept 7d / 24h / 90m, matching friction_parse.py's --since."""
    m = re.fullmatch(r"(\d+)([dhm])", spec.strip())
    if not m:
        raise argparse.ArgumentTypeError(f"expected e.g. 30d, 24h, 90m — got {spec!r}")
    n, unit = int(m.group(1)), m.group(2)
    return {"d": timedelta(days=n), "h": timedelta(hours=n), "m": timedelta(minutes=n)}[
        unit
    ]


def normalize_ts(raw: str) -> str:
    """ISO 8601 → UTC ISO 8601, so log (local offset) and transcript (Z) sort together."""
    if not raw:
        return ""
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return ""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


def record(usage: dict, skill: str, ts: str, source: str) -> None:
    if not skill or not ts:
        return
    entry = usage.setdefault(
        skill, {"skill": skill, "last": "", "count": 0, "sources": set()}
    )
    entry["count"] += 1
    entry["sources"].add(source)
    if ts > entry["last"]:
        entry["last"] = ts


def read_log(path: Path, usage: dict) -> int:
    """Read the hook's JSONL log (plus one rotation) into `usage`."""
    lines = 0
    for candidate in (path, path.with_suffix(path.suffix + ".1")):
        if not candidate.is_file():
            continue
        with candidate.open(errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                lines += 1
                record(
                    usage, rec.get("skill", ""), normalize_ts(rec.get("ts", "")), "log"
                )
    return lines


def read_transcripts(root: Path, usage: dict) -> int:
    """Mine transcripts for attributionSkill and Skill tool calls."""
    files = 0
    for path in root.glob("**/*.jsonl"):
        files += 1
        try:
            fh = path.open(errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                has_attr = '"attributionSkill"' in line
                has_skill = '"Skill"' in line
                if not (has_attr or has_skill):
                    continue
                ts_match = TIMESTAMP_RE.search(line)
                ts = normalize_ts(ts_match.group(1) if ts_match else "")
                if has_attr:
                    m = ATTRIBUTION_RE.search(line)
                    if m:
                        record(usage, m.group(1), ts, "transcript")
                if has_skill:
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    content = (rec.get("message") or {}).get("content")
                    if not isinstance(content, list):
                        continue
                    for block in content:
                        if (
                            isinstance(block, dict)
                            and block.get("type") == "tool_use"
                            and block.get("name") == "Skill"
                        ):
                            name = (block.get("input") or {}).get("skill")
                            record(usage, name or "", ts, "transcript")
    return files


def read_catalog(roots: list[Path]) -> set[str]:
    """Enumerate installed skills as `plugin:skill` (or bare name for root SKILL.md)."""
    catalog: set[str] = set()
    for root in roots:
        if not root.is_dir():
            continue
        for skill_md in root.glob("*/skills/*/SKILL.md"):
            plugin = skill_md.parents[2].name
            # Project-scoped skills under .claude/skills/ are invoked by bare
            # name — namespacing them as ".claude:x" would never match a record.
            catalog.add(
                skill_md.parent.name
                if plugin.startswith(".")
                else f"{plugin}:{skill_md.parent.name}"
            )
        for skill_md in root.glob("*/SKILL.md"):
            catalog.add(skill_md.parent.name)
    return catalog


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--log", type=Path, default=DEFAULT_LOG, help="hook log path")
    ap.add_argument("--since", default="30d", help="active window (default 30d)")
    ap.add_argument(
        "--catalog", type=Path, action="append", help="marketplace root (repeatable)"
    )
    ap.add_argument("--transcripts", type=Path, default=DEFAULT_TRANSCRIPTS)
    ap.add_argument(
        "--include-transcripts",
        action="store_true",
        help="backfill from expiring transcripts",
    )
    ap.add_argument(
        "--top", type=int, default=25, help="rows in the ranked section (0 = all)"
    )
    ap.add_argument(
        "--json", action="store_true", help="emit JSON instead of KEY=VALUE"
    )
    args = ap.parse_args()

    usage: dict = {}
    log_records = read_log(args.log, usage)
    transcript_files = (
        read_transcripts(args.transcripts, usage) if args.include_transcripts else 0
    )

    catalog = read_catalog(args.catalog or [DEFAULT_CATALOG])
    cutoff = (datetime.now(timezone.utc) - parse_since(args.since)).isoformat()

    rows = sorted(usage.values(), key=lambda r: r["last"], reverse=True)
    for row in rows:
        row["sources"] = sorted(row["sources"])
        row["in_catalog"] = row["skill"] in catalog
    active = [r for r in rows if r["last"] >= cutoff]
    dormant = [r for r in rows if r["last"] < cutoff]
    never = sorted(catalog - set(usage))
    coverage_since = rows[-1]["last"] if rows else ""

    if args.json:
        json.dump(
            {
                "window": args.since,
                "coverage_since": coverage_since,
                "log_records": log_records,
                "transcript_files": transcript_files,
                "catalog": len(catalog),
                "active": active,
                "dormant": dormant,
                "never": never,
            },
            sys.stdout,
            indent=2,
        )
        print()
        return 0

    limit = None if args.top == 0 else args.top
    print("=== SKILL USAGE ===")
    print(f"LOG={args.log}")
    print(f"LOG_RECORDS={log_records}")
    print(f"TRANSCRIPT_FILES={transcript_files}")
    print(f"WINDOW={args.since}")
    print(f"COVERAGE_SINCE={coverage_since or '-'}")
    print(f"CATALOG_SKILLS={len(catalog)}")
    print(f"ACTIVE={len(active)}")
    print(f"DORMANT={len(dormant)}")
    print(f"NEVER_SEEN={len(never)}")
    if log_records == 0 and not args.include_transcripts:
        # Distinguish "nothing used" from "nothing recorded" — an empty log and a
        # quiet month produce identical bucket counts otherwise.
        print("STATUS=NO_DATA")
        print(
            "HINT=enable CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG=1, or pass --include-transcripts"
        )
    else:
        print("STATUS=OK")
    print(f"ISSUE_COUNT={len(never)}")
    print("=== END SKILL USAGE ===")

    print()
    print("=== RANKED BY LAST USE ===")
    for row in rows[:limit]:
        flag = "" if row["in_catalog"] else "\tuncatalogued"
        print(f"{row['last'][:16]}\t{row['count']}\t{row['skill']}{flag}")
    print("=== END RANKED BY LAST USE ===")

    print()
    print("=== NEVER SEEN ===")
    for name in never[:limit]:
        print(name)
    if limit is not None and len(never) > limit:
        print(f"... {len(never) - limit} more (--top 0 for all)")
    print("=== END NEVER SEEN ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
