#!/usr/bin/env bash
# Regression test for scripts/check-workflow-cron-collisions.sh (issue #2554).
#
# The load-bearing case is B: it replays the slot the planning routine recorded
# as free for the config-drift audit -- `53 9 * * 1` -- against the hourly
# `23,53 * * * *` in fix-release-conflicts.yml. The routine's free-slot check
# scanned the Monday crons only and never expanded the hourly one, so it called
# a colliding slot free. A checker that compared cron STRINGS, or that only
# looked at crons naming a weekday, would repeat that mistake and pass case B.
#
# Every "not flagged" case is paired with a count assertion (CRONS_PARSED,
# WORKFLOWS_SCANNED) so it cannot pass against a checker that parsed nothing.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-workflow-cron-collisions.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

# Whole-line match for KEY=VALUE rows: an unanchored `CRONS_PARSED=1` would also
# be satisfied by `CRONS_PARSED=12` (the #2297 anchoring lesson).
has_line() { printf '%s\n' "$1" | grep -qxF -- "$2" && echo true || echo false; }
lacks_line() { printf '%s\n' "$1" | grep -qxF -- "$2" && echo false || echo true; }
contains() { printf '%s' "$1" | grep -qF -- "$2" && echo true || echo false; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && echo false || echo true; }
rc_is() { [ "$1" -eq "$2" ] && echo true || echo false; }

fx="$(mktemp -d)"
if [ -z "$fx" ] || [ ! -d "$fx" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$fx"' EXIT

# mkwf <root> <file> <cron>... -- one scheduled workflow carrying the given crons.
mkwf() {
  local root="$1" file="$2"; shift 2
  mkdir -p "$root/.github/workflows"
  {
    echo "name: \"Test: $file\""
    echo "on:"
    echo "  schedule:"
    local c
    for c in "$@"; do echo "    - cron: '$c'"; done
    echo "  workflow_dispatch:"
    echo "jobs:"
    echo "  j:"
    echo "    runs-on: ubuntu-latest"
    echo "    steps:"
    echo "      - run: echo ok"
  } > "$root/.github/workflows/$file"
}

# --- TEST A: the real repo is clean ------------------------------------------
echo "=== TEST A: real repo has no colliding crons ==="
out="$(bash "$checker" --strict 2>&1)"; rc=$?
assert "A: real repo exits 0 under --strict" "$(rc_is "$rc" 0)"
assert "A: real repo STATUS=OK" "$(has_line "$out" 'STATUS=OK')"
assert "A: real repo is not SCANNED_EMPTY" "$(has_line "$out" 'SCANNED_EMPTY=false')"
assert "A: real repo parsed at least one cron" \
  "$(lacks_line "$out" 'CRONS_PARSED=0')"
assert "A: real repo reports no unparseable cron" "$(lacks "$out" 'cron_unparseable')"

# --- TEST B: the routine's "free" slot collides with an hourly cron ----------
echo "=== TEST B: 53 9 * * 1 collides with the hourly 23,53 * * * * ==="
b="$fx/b"
mkwf "$b" fix-release-conflicts.yml '23,53 * * * *'
mkwf "$b" config-drift-audit.yml '53 9 * * 1'
out="$(bash "$checker" --project-dir "$b" --strict 2>&1)"; rc=$?
assert "B: collision exits 1 under --strict" "$(rc_is "$rc" 1)"
assert "B: collision reports STATUS=ERROR" "$(has_line "$out" 'STATUS=ERROR')"
assert "B: REASON= names the collision" "$(printf '%s\n' "$out" | grep -qE '^REASON=cron_collision: ' && echo true || echo false)"
assert "B: collision is typed cron_collision" "$(contains "$out" 'TYPE=cron_collision')"
assert "B: collision names the hourly workflow" "$(contains "$out" 'fix-release-conflicts.yml[23,53 * * * *]')"
assert "B: collision names the new workflow" "$(contains "$out" 'config-drift-audit.yml[53 9 * * 1]')"
assert "B: collision reports a concrete co-fire time on a Monday at 09:53" "$(contains "$out" 'Mon 09:53')"
assert "B: exactly one collision" "$(has_line "$out" 'COLLISION_COUNT=1')"
assert "B: both crons were parsed" "$(has_line "$out" 'CRONS_PARSED=2')"
out="$(bash "$checker" --project-dir "$b" 2>&1)"; rc=$?
assert "B: without --strict the run still exits 0" "$(rc_is "$rc" 0)"
assert "B: without --strict the finding is still reported" "$(has_line "$out" 'COLLISION_COUNT=1')"

# --- TEST C: same minute and hour on different weekdays do not collide -------
# The repo's own Monday/Tuesday/Wednesday 09:13 crons (changelog-review,
# obsidian-cli-changelog, research-radar) are exactly this shape. A checker that
# compared only (minute, hour) would flag all three pairs.
echo "=== TEST C: 13 9 on Mon vs Tue is not a collision ==="
c="$fx/c"
mkwf "$c" mon.yml '13 9 * * 1'
mkwf "$c" tue.yml '13 9 * * 2'
out="$(bash "$checker" --project-dir "$c" --strict 2>&1)"; rc=$?
assert "C: different weekdays exit 0" "$(rc_is "$rc" 0)"
assert "C: different weekdays STATUS=OK" "$(has_line "$out" 'STATUS=OK')"
assert "C: no REASON= on the OK path" "$(lacks "$out" 'REASON=')"
assert "C: both crons were parsed" "$(has_line "$out" 'CRONS_PARSED=2')"
assert "C: no collision reported" "$(has_line "$out" 'COLLISION_COUNT=0')"

# --- TEST D: day-of-month vs day-of-week can coincide --------------------------
# `19 9 1 * *` runs on the 1st of every month; `19 9 * * 1` every Monday. The
# 1st falls on a Monday several times a year, so they co-fire. Compared by day
# FIELD they share nothing, which is the mistake this case pins.
echo "=== TEST D: the 1st of the month vs every Monday ==="
d="$fx/d"
mkwf "$d" monthly.yml '19 9 1 * *'
mkwf "$d" weekly.yml '19 9 * * 1'
out="$(bash "$checker" --project-dir "$d" --strict 2>&1)"; rc=$?
assert "D: dom-vs-dow coincidence exits 1" "$(rc_is "$rc" 1)"
assert "D: dom-vs-dow coincidence is reported" "$(has_line "$out" 'COLLISION_COUNT=1')"
d2="$fx/d2"
mkwf "$d2" first.yml '19 9 1 * *'
mkwf "$d2" second.yml '19 9 2 * *'
out="$(bash "$checker" --project-dir "$d2" --strict 2>&1)"; rc=$?
assert "D2: 1st vs 2nd of the month exits 0" "$(rc_is "$rc" 0)"
assert "D2: 1st vs 2nd of the month is not a collision" "$(has_line "$out" 'COLLISION_COUNT=0')"
# POSIX OR-semantics: with BOTH day fields restricted a cron fires when EITHER
# matches, so `5 3 15 * 5` fires on every 15th AND every Friday -- and collides
# with a 16th-of-the-month cron whenever the 16th is a Friday. Read with AND
# semantics it would fire only on Friday-the-15ths and never meet the 16th, so
# this pair discriminates the two readings.
d3="$fx/d3"
mkwf "$d3" either.yml '5 3 15 * 5'
mkwf "$d3" sixteenth.yml '5 3 16 * *'
out="$(bash "$checker" --project-dir "$d3" --strict 2>&1)"; rc=$?
assert "D3: dom+dow OR-semantics collide on the dow arm" "$(has_line "$out" 'COLLISION_COUNT=1')"

# --- TEST E: steps and ranges are expanded -------------------------------------
echo "=== TEST E: */15 and ranges ==="
e="$fx/e"
mkwf "$e" quarter.yml '*/15 * * * *'
mkwf "$e" daily.yml '30 4 * * *'
out="$(bash "$checker" --project-dir "$e" --strict 2>&1)"; rc=$?
assert "E: */15 covers :30" "$(has_line "$out" 'COLLISION_COUNT=1')"
e2="$fx/e2"
mkwf "$e2" quarter.yml '*/15 * * * *'
mkwf "$e2" odd.yml '7 1-5/2 * * *'
out="$(bash "$checker" --project-dir "$e2" --strict 2>&1)"; rc=$?
assert "E2: */15 never hits :07" "$(has_line "$out" 'COLLISION_COUNT=0')"
assert "E2: a range-with-step cron parses" "$(has_line "$out" 'CRONS_PARSED=2')"
# `a/n` starts at a and steps to the field maximum: 5/20 is 5, 25, 45.
e3="$fx/e3"
mkwf "$e3" stepped.yml '5/20 * * * *'
mkwf "$e3" late.yml '45 2 * * *'
out="$(bash "$checker" --project-dir "$e3" --strict 2>&1)"; rc=$?
assert "E3: 5/20 reaches :45" "$(has_line "$out" 'COLLISION_COUNT=1')"

# --- TEST F: disjoint months never co-fire ------------------------------------
echo "=== TEST F: January vs February ==="
f="$fx/f"
mkwf "$f" jan.yml '5 3 * 1 *'
mkwf "$f" feb.yml '5 3 * FEB *'
out="$(bash "$checker" --project-dir "$f" --strict 2>&1)"; rc=$?
assert "F: disjoint months exit 0" "$(rc_is "$rc" 0)"
assert "F: disjoint months are not a collision" "$(has_line "$out" 'COLLISION_COUNT=0')"
assert "F: a month name parses" "$(has_line "$out" 'CRONS_PARSED=2')"

# --- TEST G: an unparseable cron is an ERROR, never silently skipped ----------
# A skipped cron is a slot the checker never compared -- the same blind spot as
# the routine's, one layer down.
echo "=== TEST G: unparseable cron ==="
g="$fx/g"
mkwf "$g" bad.yml '0 0 L * *'
mkwf "$g" short.yml '5 4 * *'
out="$(bash "$checker" --project-dir "$g" --strict 2>&1)"; rc=$?
assert "G: unparseable crons exit 1 under --strict" "$(rc_is "$rc" 1)"
assert "G: unparseable cron is typed cron_unparseable" "$(contains "$out" 'TYPE=cron_unparseable')"
assert "G: both bad crons are reported" "$(has_line "$out" 'UNPARSEABLE_COUNT=2')"
assert "G: nothing was counted as parsed" "$(has_line "$out" 'CRONS_PARSED=0')"

# --- TEST H: a :00 minute is a WARN, not a blocker -----------------------------
echo "=== TEST H: top of the hour ==="
h="$fx/h"
mkwf "$h" hourly.yml '0 9 * * 1'
out="$(bash "$checker" --project-dir "$h" --strict 2>&1)"; rc=$?
assert "H: a :00 cron alone exits 0 under --strict" "$(rc_is "$rc" 0)"
assert "H: a :00 cron is reported as top_of_hour" "$(contains "$out" 'TYPE=top_of_hour')"
assert "H: a :00 cron makes STATUS=WARN" "$(has_line "$out" 'STATUS=WARN')"
assert "H: REASON= names the WARN finding" "$(printf '%s\n' "$out" | grep -qE '^REASON=top_of_hour: ' && echo true || echo false)"

# --- TEST I: two entries in ONE workflow can collide too ----------------------
echo "=== TEST I: same-workflow overlap, and Sunday spelled 0 and 7 ==="
i="$fx/i"
mkwf "$i" twice.yml '1 1 * * 0' '1 1 * * 7'
out="$(bash "$checker" --project-dir "$i" --strict 2>&1)"; rc=$?
assert "I: dow 0 and dow 7 are both Sunday" "$(has_line "$out" 'COLLISION_COUNT=1')"
assert "I: a same-workflow collision exits 1" "$(rc_is "$rc" 1)"

# --- TEST J: nothing to scan is legitimately empty ----------------------------
echo "=== TEST J: no workflows directory ==="
j="$fx/j"; mkdir -p "$j"
out="$(bash "$checker" --project-dir "$j" --strict 2>&1)"; rc=$?
assert "J: no workflows exits 0" "$(rc_is "$rc" 0)"
assert "J: no workflows is marked SCANNED_EMPTY" "$(has_line "$out" 'SCANNED_EMPTY=true')"
j2="$fx/j2"; mkdir -p "$j2/.github/workflows"
printf 'name: x\non:\n  push:\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' \
  > "$j2/.github/workflows/push.yml"
out="$(bash "$checker" --project-dir "$j2" --strict 2>&1)"; rc=$?
assert "J2: a workflow with no schedule is scanned" "$(has_line "$out" 'WORKFLOWS_SCANNED=1')"
assert "J2: a workflow with no schedule parses no cron" "$(has_line "$out" 'CRONS_PARSED=0')"
assert "J2: a workflow with no schedule exits 0" "$(rc_is "$rc" 0)"

# --- TEST K: an unknown argument is rejected, not swallowed (#2057) ----------
echo "=== TEST K: unknown argument ==="
out="$(bash "$checker" --strcit 2>&1)"; rc=$?
assert "K: unknown argument exits 2" "$(rc_is "$rc" 2)"
assert "K: unknown argument is named" "$(contains "$out" 'unknown argument: --strcit')"

echo
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
