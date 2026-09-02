#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: single-quoted grep -F needles are literal markdown backticks, not substitutions (must precede the first command)
# Regression test for the blueprint-health stale-skill report shape (#2556).
#
# The defect: `scripts/blueprint-health-check.sh` itemised every skill more than
# 90 days past its `modified:` date as its own table row. A single bulk
# `modified:` bump (110 skills sharing `2026-05-09`) therefore rendered as 110
# separate "findings", and the Recommendations block told the reader to "update
# `modified` date" on all 167 — i.e. to write a fresh date into 167 files, which
# manufactures next month's identical report.
#
# The fix has four visible parts:
#   1. the summary metric names the field it measures (`modified:`), because
#      staleness-by-`modified` and staleness-by-`reviewed` are different numbers;
#   2. the >90d band is rolled up one-row-per-date;
#   3. only the >180d tail is itemised, so the itemised row count is strictly
#      smaller than the summary count whenever a mid-band cohort exists;
#   4. the recommendation no longer orders a bulk date bump.
#
# HERMETIC: the exact-count assertions run against throwaway skill trees under a
# guarded `mktemp -d`, with `modified:` dates computed relative to today, so the
# expected cohort/tail numbers are fixed by construction and independent of both
# the live corpus and the wall clock. The script under test resolves its own
# REPO_ROOT from `${BASH_SOURCE[0]}/..` and takes no `--project-dir`, so a COPY
# of the shipped script is placed at <fixture>/scripts/ and the fixture becomes
# its repo root — the same technique as scripts/tests/test-agentic-audit-precompute.sh.
# The copy is the shipped bytes, never a re-typed reimplementation.
#
# WHY NOT DRIVE THIS OFF THE LIVE CORPUS: the earlier revision of this file
# compared two numbers derived from the real tree, which made the suite red in
# two states the generator reaches while behaving correctly — (1) every stale
# skill ageing past 180d, which is mechanical in a tree that stops editing
# SKILL.md and collapses the tail onto the total; and (2) the corpus actually
# becoming clean, which is the outcome the fix pushes toward and which leaves no
# cohort table to count. Fixtures 3 and 2 below pin those two states as PASSING
# behaviour. The live corpus is still exercised, but only as a smoke run whose
# band-dependent assertions are skipped when the >90d band is empty.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
subject="$repo_root/scripts/blueprint-health-check.sh"

pass_count=0
fail_count=0
skip_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

skip() {
  echo "SKIP: $1" >&2
  skip_count=$((skip_count + 1))
}

if [ ! -f "$subject" ]; then
  echo "FAIL: subject not found: $subject" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
if [ -z "$work_dir" ] || [ ! -d "$work_dir" ]; then
  echo "FAIL: could not create fixture directory" >&2
  exit 1
fi
trap 'rm -rf "$work_dir"' EXIT

# Portable "N days ago" — GNU first, BSD/macOS second.
days_ago() {
  date -d "$1 days ago" +%Y-%m-%d 2>/dev/null || date -v-"$1"d +%Y-%m-%d 2>/dev/null
}

# Chosen well away from the 90d and 180d band edges so a one-day slip (DST, a
# run straddling local midnight) cannot move a fixture skill between bands.
DATE_FRESH="$(days_ago 10)"    # below the 90d stale threshold
DATE_MID="$(days_ago 120)"     # stale, but inside the rolled-up cohort band
DATE_TAIL="$(days_ago 400)"    # past the 180d itemise threshold
DATE_TAIL2="$(days_ago 500)"   # ditto, a second distinct tail date
for d in "$DATE_FRESH" "$DATE_MID" "$DATE_TAIL" "$DATE_TAIL2"; do
  if [ -z "$d" ]; then
    echo "FAIL: could not compute fixture dates on this platform" >&2
    exit 1
  fi
done

##########
# Fixture construction
##########

new_root() {
  # new_root <name> -> echoes the fixture root path
  local root="$work_dir/$1"
  mkdir -p "$root/scripts" "$root/demo-plugin/.claude-plugin" "$root/demo-plugin/skills"
  cp "$subject" "$root/scripts/blueprint-health-check.sh"
  printf '# demo-plugin\n' > "$root/demo-plugin/README.md"
  cat > "$root/demo-plugin/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "demo-plugin",
  "version": "1.0.0",
  "description": "Fixture plugin for the blueprint-health report test.",
  "keywords": ["fixture"]
}
JSON
  printf '%s\n' "$root"
}

mk_skill() {
  # mk_skill <root> <skill-name> <modified-date>
  local root="$1" name="$2" modified="$3"
  mkdir -p "$root/demo-plugin/skills/$name"
  cat > "$root/demo-plugin/skills/$name/SKILL.md" <<EOF
---
name: $name
description: Fixture skill. Use when exercising the stale-skill report.
allowed-tools: Read
created: $modified
modified: $modified
reviewed: $modified
---

## When to Use This Skill

Fixture body.
EOF
}

##########
# Report accessors — one place that knows the report's shape
##########

summary_line_of() { grep -m1 '^| Stale skills' "$1" || true; }

stale_count_of() {
  # Always emits a number: a missing summary row yields 0 rather than an empty
  # string, so a broken report fails an assertion instead of erroring `[ -eq ]`.
  summary_line_of "$1" \
    | awk -F'|' '{gsub(/[^0-9]/,"",$3); print $3+0} END { if (NR == 0) print 0 }'
}

cohort_section_of() { sed -n '/^### Stale Skills by/,/^### /p' "$1"; }

cohort_rows_of() {
  cohort_section_of "$1" | grep -cE '^\| [0-9]{4}-[0-9]{2}-[0-9]{2} \| [0-9]+ \|$' || true
}

tail_section_of() { sed -n '/^### Stale Skills (>/,/^$/p' "$1"; }

tail_rows_of() {
  tail_section_of "$1" \
    | grep -cE '^\| [^|]+ \| [^|]+ \| [0-9]{4}-[0-9]{2}-[0-9]{2} \| [0-9]+ \|$' || true
}

recommendations_of() { sed -n '/^### Recommendations/,$p' "$1"; }

run_generator() {
  # run_generator <root> -> writes <root>/report.md and <root>/report.err,
  # echoes the exit status
  local root="$1"
  bash "$root/scripts/blueprint-health-check.sh" >"$root/report.md" 2>"$root/report.err"
  printf '%s\n' "$?"
}

dump_on_failure() {
  # dump_on_failure <root> — only called when a fixture's assertions failed
  echo "--- report under test ($1) ---" >&2
  sed -n '1,60p' "$1/report.md" >&2
  if [ -s "$1/report.err" ]; then
    echo "--- stderr ---" >&2
    sed 's/^/    /' "$1/report.err" >&2
  fi
}

#############################################################################
# FIXTURE 1 — mixed bands. Three skills share one 120-day-old `modified:` date
# (the bulk-bump shape), two share one 400-day-old date, one is fresh.
#
# Expected, fixed by construction: 5 stale, 2 cohort rows (3 + 2), 2 itemised
# tail rows. The 120d cohort MUST NOT be itemised — that is the whole fix.
#############################################################################
f1="$(new_root mixed)"
mk_skill "$f1" cohort-a "$DATE_MID"
mk_skill "$f1" cohort-b "$DATE_MID"
mk_skill "$f1" cohort-c "$DATE_MID"
mk_skill "$f1" tail-a "$DATE_TAIL"
mk_skill "$f1" tail-b "$DATE_TAIL"
mk_skill "$f1" fresh-a "$DATE_FRESH"

f1_status="$(run_generator "$f1")"
f1_report="$f1/report.md"
f1_before=$fail_count

echo "=== fixture 1 (mixed bands): generator contract ==="
assert "fixture 1: generator exits 0" \
  "$([ "$f1_status" -eq 0 ] && echo true || echo false)"
assert "fixture 1: generator writes nothing to stderr" \
  "$([ ! -s "$f1/report.err" ] && echo true || echo false)"
assert "fixture 1: report is non-empty" \
  "$([ -s "$f1_report" ] && echo true || echo false)"

echo "=== fixture 1: summary metric labelling ==="
f1_summary="$(summary_line_of "$f1_report")"
assert "fixture 1: summary carries a 'Stale skills' metric row" \
  "$([ -n "$f1_summary" ] && echo true || echo false)"
assert "fixture 1: summary metric names the \`modified:\` field it measures" \
  "$(printf '%s' "$f1_summary" | grep -qF 'modified:' && echo true || echo false)"
assert "fixture 1: summary counts exactly the 5 stale skills" \
  "$([ "$(stale_count_of "$f1_report")" -eq 5 ] && echo true || echo false)"
assert "fixture 1: the fresh skill is not counted as stale" \
  "$(! grep -q 'fresh-a' "$f1_report" && echo true || echo false)"

echo "=== fixture 1: cohort roll-up ==="
assert "fixture 1: report contains a 'Stale Skills by' cohort section" \
  "$(grep -q '^### Stale Skills by' "$f1_report" && echo true || echo false)"
assert "fixture 1: cohort table has exactly 2 date rows (one per distinct date)" \
  "$([ "$(cohort_rows_of "$f1_report")" -eq 2 ] && echo true || echo false)"
assert "fixture 1: the 3-skill 120d bump is ONE cohort row, not 3 findings" \
  "$(cohort_section_of "$f1_report" | grep -qxF "| $DATE_MID | 3 |" && echo true || echo false)"
assert "fixture 1: the 2-skill 400d cohort is counted as 2" \
  "$(cohort_section_of "$f1_report" | grep -qxF "| $DATE_TAIL | 2 |" && echo true || echo false)"

echo "=== fixture 1: itemised >180d tail ==="
f1_tail_rows="$(tail_rows_of "$f1_report")"
echo "    itemised tail: ${f1_tail_rows} row(s) vs summary count $(stale_count_of "$f1_report")"
assert "fixture 1: the itemised tail has exactly the 2 skills past 180d" \
  "$([ "$f1_tail_rows" -eq 2 ] && echo true || echo false)"
assert "fixture 1: tail-a is itemised" \
  "$(tail_section_of "$f1_report" | grep -q '| tail-a |' && echo true || echo false)"
assert "fixture 1: tail-b is itemised" \
  "$(tail_section_of "$f1_report" | grep -q '| tail-b |' && echo true || echo false)"
# The discriminating assertion: restoring the unfiltered 167-row table puts the
# 120d cohort members back into the itemised section.
assert "fixture 1: a 120d cohort member is NOT itemised (tail is a filter, not the full table)" \
  "$(! tail_section_of "$f1_report" | grep -q '| cohort-a |' && echo true || echo false)"
assert "fixture 1: itemised stale rows are strictly fewer than the >90d summary count" \
  "$([ "$f1_tail_rows" -lt "$(stale_count_of "$f1_report")" ] && echo true || echo false)"

echo "=== fixture 1: recommendations ==="
f1_recs="$(recommendations_of "$f1_report")"
assert "fixture 1: Recommendations section is present" \
  "$([ -n "$f1_recs" ] && echo true || echo false)"
assert "fixture 1: Recommendations do not order 'update \`modified\` date'" \
  "$(printf '%s' "$f1_recs" | grep -qF 'update `modified` date' && echo false || echo true)"
assert "fixture 1: the recommendation names the tail count (2), not the >90d total" \
  "$(printf '%s' "$f1_recs" | grep -qF 'Review the 2 skill(s)' && echo true || echo false)"
assert "fixture 1: the recommendation names the dominant cohort as one event" \
  "$(printf '%s' "$f1_recs" | grep -qF "$DATE_MID cohort (3 skills sharing one" && echo true || echo false)"

[ "$fail_count" -eq "$f1_before" ] || dump_on_failure "$f1"

#############################################################################
# FIXTURE 2 — a clean corpus. This is the outcome the fix pushes toward, and it
# is the state that reddened the previous live-corpus revision of this test:
# nothing stale means no cohort table to count. It must be a PASS.
#############################################################################
f2="$(new_root clean)"
mk_skill "$f2" fresh-a "$DATE_FRESH"
mk_skill "$f2" fresh-b "$DATE_FRESH"

f2_status="$(run_generator "$f2")"
f2_report="$f2/report.md"
f2_before=$fail_count

echo "=== fixture 2 (clean corpus): no stale band at all ==="
assert "fixture 2: generator exits 0 on a clean corpus" \
  "$([ "$f2_status" -eq 0 ] && echo true || echo false)"
assert "fixture 2: generator writes nothing to stderr" \
  "$([ ! -s "$f2/report.err" ] && echo true || echo false)"
assert "fixture 2: the stale metric reads 0" \
  "$([ "$(stale_count_of "$f2_report")" -eq 0 ] && echo true || echo false)"
assert "fixture 2: no cohort section is emitted when nothing is stale" \
  "$(! grep -q '^### Stale Skills by' "$f2_report" && echo true || echo false)"
assert "fixture 2: no itemised tail section is emitted when nothing is stale" \
  "$(! grep -q '^### Stale Skills (>' "$f2_report" && echo true || echo false)"
assert "fixture 2: Recommendations report a clean bill of health" \
  "$(recommendations_of "$f2_report" | grep -qF 'All checks passed' && echo true || echo false)"

[ "$fail_count" -eq "$f2_before" ] || dump_on_failure "$f2"

#############################################################################
# FIXTURE 3 — every stale skill is past the itemise threshold, so the tail and
# the >90d total are the SAME number. Mechanical in a tree that stops editing
# SKILL.md; the previous revision's `tail < total` comparison went red here with
# the generator behaving correctly. Pin it as a PASS.
#############################################################################
f3="$(new_root all-tail)"
mk_skill "$f3" tail-a "$DATE_TAIL"
mk_skill "$f3" tail-b "$DATE_TAIL"
mk_skill "$f3" tail-c "$DATE_TAIL2"

f3_status="$(run_generator "$f3")"
f3_report="$f3/report.md"
f3_before=$fail_count

echo "=== fixture 3 (whole band past 180d): tail equals total ==="
assert "fixture 3: generator exits 0" \
  "$([ "$f3_status" -eq 0 ] && echo true || echo false)"
assert "fixture 3: generator writes nothing to stderr" \
  "$([ ! -s "$f3/report.err" ] && echo true || echo false)"
assert "fixture 3: summary counts all 3 stale skills" \
  "$([ "$(stale_count_of "$f3_report")" -eq 3 ] && echo true || echo false)"
assert "fixture 3: cohort table still rolls the 2 distinct dates up" \
  "$([ "$(cohort_rows_of "$f3_report")" -eq 2 ] && echo true || echo false)"
assert "fixture 3: all 3 skills are itemised when the whole band is past 180d" \
  "$([ "$(tail_rows_of "$f3_report")" -eq 3 ] && echo true || echo false)"
assert "fixture 3: Recommendations do not order 'update \`modified\` date'" \
  "$(recommendations_of "$f3_report" | grep -qF 'update `modified` date' && echo false || echo true)"

[ "$fail_count" -eq "$f3_before" ] || dump_on_failure "$f3"

#############################################################################
# LIVE-CORPUS SMOKE — the generator must still run clean against the real tree.
# Only the corpus-independent contract is asserted unconditionally; the
# band-dependent comparison is bounded (`-le`) and skipped outright when the
# >90d band is empty, so a corpus that becomes clean cannot fail the suite.
#############################################################################
live="$work_dir/live"
mkdir -p "$live"
live_report="$live/report.md"
bash "$subject" >"$live_report" 2>"$live/report.err"
live_status=$?

echo "=== live corpus smoke ==="
assert "live: generator exits 0" \
  "$([ "$live_status" -eq 0 ] && echo true || echo false)"
assert "live: generator writes nothing to stderr" \
  "$([ ! -s "$live/report.err" ] && echo true || echo false)"
assert "live: report is non-empty" \
  "$([ -s "$live_report" ] && echo true || echo false)"
assert "live: summary metric names the \`modified:\` field it measures" \
  "$(summary_line_of "$live_report" | grep -qF 'modified:' && echo true || echo false)"
assert "live: Recommendations do not order 'update \`modified\` date'" \
  "$(recommendations_of "$live_report" | grep -qF 'update `modified` date' && echo false || echo true)"

live_stale="$(stale_count_of "$live_report")"
live_tail="$(tail_rows_of "$live_report")"
live_cohorts="$(cohort_rows_of "$live_report")"
echo "    live corpus: ${live_stale:-0} stale, ${live_cohorts:-0} cohort row(s), ${live_tail:-0} itemised row(s)"
if [ "${live_stale:-0}" -gt 0 ]; then
  assert "live: a non-empty >90d band emits a cohort roll-up" \
    "$([ "${live_cohorts:-0}" -gt 0 ] && echo true || echo false)"
  assert "live: itemised rows never exceed the >90d summary count" \
    "$([ "${live_tail:-0}" -le "${live_stale:-0}" ] && echo true || echo false)"
else
  skip "live corpus has an empty >90d band — band-dependent assertions not applicable"
fi

echo ""
echo "Passed: $pass_count, Failed: $fail_count, Skipped: $skip_count"
[ "$fail_count" -eq 0 ]
