#!/usr/bin/env bash
# Flag two scheduled workflows whose crons fire in the same minute.
#
# Background (issue #2554): the routine that planned the config-drift audit
# recorded `53 9 * * 1` as a free Monday slot. It had listed the crons that name
# a weekday (changelog-review 09:13, fleet-drift 09:37, ...) and missed that
# fix-release-conflicts.yml runs `23,53 * * * *` -- every hour, every day,
# including 09:53 on Mondays. A cron STRING that names no weekday still fires on
# every weekday; the only honest comparison is between expanded fire times.
#
# The convention this pins lives in the workflows' own comments (stranded-work,
# fleet-drift, scheduled-audits): schedule off the top of the hour, and offset
# from the crons already there. This guard turns "offset" into a check:
#
#   cron_collision   ERROR  two cron entries share at least one fire time
#   cron_unparseable ERROR  a cron the checker cannot expand -- a slot it never
#                           compared is the same blind spot one layer down
#   top_of_hour      WARN   minute 0, GitHub's scheduler surge
#
# Two crons collide when their minute sets intersect, their hour sets intersect,
# and some calendar date satisfies both day specs. Days are matched with POSIX
# semantics: when BOTH day-of-month and day-of-week are restricted, a date
# matches if EITHER does. Dates are enumerated over 28 years from 2026-01-01,
# which contains every (month, day-of-month, weekday) combination -- Feb 29
# included, since seven leap days in 28 years land on seven different weekdays.
#
# Usage:
#   bash scripts/check-workflow-cron-collisions.sh [--strict] [--project-dir DIR]
#
#   --strict        exit 1 when ERROR_COUNT > 0 (default: report only)
#   --project-dir   repo root to scan (default: this script's repo)
#
# Exit codes:
#   0 - no ERROR finding (or not --strict)
#   1 - --strict and at least one ERROR finding
#   2 - unknown argument / missing dependency

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STRICT=0

usage() {
  echo "Usage: check-workflow-cron-collisions.sh [--strict] [--project-dir DIR]" >&2
}

# An unknown argument is REJECTED, never swallowed (#2057).
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-workflow-cron-collisions.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      ROOT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "check-workflow-cron-collisions.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-workflow-cron-collisions.sh: python3 not found on PATH" >&2
  exit 2
fi

python3 - "$ROOT_DIR/.github/workflows" "$STRICT" <<'PY'
import datetime as dt
import os
import sys

workflow_dir, strict = sys.argv[1], sys.argv[2] == "1"

try:
    import yaml
except ImportError:
    print("check-workflow-cron-collisions.sh: PyYAML not available", file=sys.stderr)
    sys.exit(2)

MONTHS = {m: i for i, m in enumerate(
    "JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC".split(), start=1)}
DAYS = {d: i for i, d in enumerate("SUN MON TUE WED THU FRI SAT".split())}
WEEKDAY = "Mon Tue Wed Thu Fri Sat Sun".split()  # indexed by date.weekday()

# (low, high, names) per field, in cron order.
FIELDS = [
    (0, 59, {}),      # minute
    (0, 23, {}),      # hour
    (1, 31, {}),      # day of month
    (1, 12, MONTHS),  # month
    (0, 7, DAYS),     # day of week; 7 is Sunday too
]


class Unparseable(ValueError):
    pass


def _value(tok, names):
    if tok.upper() in names:
        return names[tok.upper()]
    if not tok.isdigit():
        raise Unparseable(f"not a number: {tok!r}")
    return int(tok)


def expand(field, low, high, names):
    """Expand one cron field into the set of values it fires on."""
    out = set()
    for item in field.split(","):
        if not item:
            raise Unparseable("empty list item")
        base, _, step_s = item.partition("/")
        if step_s:
            if not step_s.isdigit() or int(step_s) == 0:
                raise Unparseable(f"bad step: {item!r}")
            step = int(step_s)
        else:
            step = 1
        if base == "*":
            lo, hi = low, high
        elif "-" in base:
            a, _, b = base.partition("-")
            lo, hi = _value(a, names), _value(b, names)
        else:
            lo = _value(base, names)
            # `a/n` means a, a+n, ... up to the field maximum.
            hi = high if step_s else lo
        if not (low <= lo <= high and low <= hi <= high) or lo > hi:
            raise Unparseable(f"out of range: {item!r}")
        out.update(range(lo, hi + 1, step))
    return out


def parse(cron):
    parts = cron.split()
    if len(parts) != 5:
        raise Unparseable(f"expected 5 fields, got {len(parts)}")
    sets = [expand(p, lo, hi, names) for p, (lo, hi, names) in zip(parts, FIELDS)]
    minutes, hours, doms, months, dows = sets
    dows = {0 if d == 7 else d for d in dows}
    # Vixie/POSIX: a day field "is restricted" unless it begins with `*`.
    dom_star, dow_star = parts[2].startswith("*"), parts[4].startswith("*")
    return minutes, hours, doms, months, dows, dom_star, dow_star


START = dt.date(2026, 1, 1)
DATES = [START + dt.timedelta(days=i) for i in range((dt.date(2054, 1, 1) - START).days)]


def day_mask(doms, months, dows, dom_star, dow_star):
    """Bitmask over DATES of the days this cron's day spec matches."""
    mask = 0
    for i, d in enumerate(DATES):
        if d.month not in months:
            continue
        dom_ok = d.day in doms
        dow_ok = (d.weekday() + 1) % 7 in dows  # cron: Sunday = 0
        if dom_star and dow_star:
            ok = True
        elif dom_star:
            ok = dow_ok
        elif dow_star:
            ok = dom_ok
        else:
            ok = dom_ok or dow_ok
        if ok:
            mask |= 1 << i
    return mask


rows, errors, warns = [], 0, 0
entries = []  # (label, minutes, hours, mask)
workflows_scanned = crons_total = unparseable = 0

names = sorted(os.listdir(workflow_dir)) if os.path.isdir(workflow_dir) else []
for fname in names:
    if not fname.endswith((".yml", ".yaml")):
        continue
    try:
        with open(os.path.join(workflow_dir, fname), encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except Exception as exc:  # noqa: BLE001 - report, don't crash the gate
        rows.append(f"  - SEVERITY=WARN TYPE=unparseable_workflow WORKFLOW={fname} MSG={exc}")
        warns += 1
        continue
    if not isinstance(doc, dict):
        continue
    workflows_scanned += 1
    # `on:` parses as the YAML boolean True under YAML 1.1.
    triggers = doc.get("on", doc.get(True)) or {}
    schedule = triggers.get("schedule") if isinstance(triggers, dict) else None
    for item in schedule or []:
        cron = item.get("cron") if isinstance(item, dict) else None
        if not isinstance(cron, str):
            continue
        crons_total += 1
        label = f"{fname}[{cron}]"
        try:
            minutes, hours, doms, months, dows, dom_star, dow_star = parse(cron)
        except Unparseable as exc:
            unparseable += 1
            errors += 1
            rows.append(
                f"  - SEVERITY=ERROR TYPE=cron_unparseable CRON={label} MSG={exc} -- "
                "a cron the checker cannot expand is a slot it never compared"
            )
            continue
        if 0 in minutes:
            warns += 1
            rows.append(
                f"  - SEVERITY=WARN TYPE=top_of_hour CRON={label} MSG=fires at minute 0, "
                "GitHub's scheduler surge -- pick an off-the-hour minute"
            )
        entries.append((label, minutes, hours, day_mask(doms, months, dows, dom_star, dow_star)))

collisions = 0
for i in range(len(entries)):
    for j in range(i + 1, len(entries)):
        la, ma, ha, da = entries[i]
        lb, mb, hb, db = entries[j]
        common_m, common_h, common_d = ma & mb, ha & hb, da & db
        if not (common_m and common_h and common_d):
            continue
        collisions += 1
        errors += 1
        first = DATES[(common_d & -common_d).bit_length() - 1]
        example = (f"{WEEKDAY[first.weekday()]} {min(common_h):02d}:{min(common_m):02d} "
                   f"(first on {first.isoformat()})")
        rows.append(
            f"  - SEVERITY=ERROR TYPE=cron_collision A={la} B={lb} AT={example} "
            "MSG=both fire in the same minute -- move one to a free off-the-hour minute"
        )

parsed = crons_total - unparseable
status = "ERROR" if errors else ("WARN" if rows else "OK")
print("=== WORKFLOW CRON COLLISIONS ===")
print(f"WORKFLOWS_SCANNED={workflows_scanned}")
print(f"SCANNED_EMPTY={'true' if workflows_scanned == 0 else 'false'}")
print(f"CRONS_PARSED={parsed}")
print(f"UNPARSEABLE_COUNT={unparseable}")
print(f"COLLISION_COUNT={collisions}")
print(f"STATUS={status}")
if status != "OK" and rows:
    # REASON= names the worst finding (.claude/rules/structured-script-output.md, #2691).
    worst = next((r for r in rows if f"SEVERITY={status} " in r), rows[0])
    rtype = worst.split("TYPE=", 1)[1].split(" ", 1)[0]
    rmsg = worst.split(" MSG=", 1)[1] if " MSG=" in worst else worst.split("TYPE=", 1)[1]
    print(f"REASON={(rtype + ': ' + rmsg)[:200]}")
print(f"ISSUE_COUNT={len(rows)}")
print(f"ERROR_COUNT={errors}")
if rows:
    print("ISSUES:")
    for r in rows:
        print(r)
print("=== END WORKFLOW CRON COLLISIONS ===")
sys.exit(1 if (strict and errors) else 0)
PY
