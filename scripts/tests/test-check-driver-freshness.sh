#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2002   # file-level: test idioms (cmd && pass || fail; cat fixtures)
# Regression test for scripts/check-driver-freshness.sh (issue #1704).
#
# #1704: the check intermittently reported a dependency whose `modified:` date
# was EQUAL to the driver's `reviewed:` date as "newer", failing a pre-commit
# run, and "could not be reproduced afterward". ROOT CAUSE (found via the epoch
# diagnostics this test once only proved existed): BSD `date -j -f "%Y-%m-%d"`
# fills the unspecified time fields with the *current* time-of-day, so the
# driver epoch (parsed first) and a dep epoch (parsed ~1s later in the loop)
# differ by 1s whenever the two calls straddle a second boundary — making equal
# dates compare `-gt`. The fix pins parsing to `00:00:00` so the epoch is a pure
# function of the date.
#
# Asserts:
#   - dependency `modified:` == driver `reviewed:`  → exit 0, prints OK (#1704 core)
#   - dependency `modified:` >  driver `reviewed:`  → exit 1, FAIL output carries
#     the epoch integers (proves the diagnostics)
#   - parsing the same date twice across a second boundary is STABLE (the
#     determinism invariant that actually fixes #1704)
#
# Hermetic: each case builds a throwaway "mini-repo" under a temp dir, copies the
# real check script into <fixture>/scripts/ so the script's own `cd $(dirname
# $0)/..` lands at the fixture root (it resolves dependency paths relative to
# that root), and runs it there with a far-future --max-age-days so the
# driver-age staleness branch never confounds the dependency comparison.
set -uo pipefail

src_check="$(cd "$(dirname "$0")/.." && pwd)/check-driver-freshness.sh"

pass=0
fail=0

ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }

# assert_has <desc> <text> <needle>
assert_has() {
  if printf '%s' "$2" | grep -q -- "$3"; then ok "$1"; else ko "$1"; fi
}

# Cross-platform date → epoch seconds. MUST mirror the check script's helper —
# pinned to 00:00:00 — so the expected epoch integers match what the (fixed)
# script computes. If the script regresses to bare "%Y-%m-%d" (current-time)
# parsing, its reported epochs will be current-time values while this helper
# computes midnight, so TEST B's "epoch <N>" assertions fail — turning them into
# a determinism guard.
date_to_epoch_portable() {
  if date -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" "+%s" >/dev/null 2>&1; then
    date -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" "+%s"
  else
    date -d "$1 00:00:00" "+%s"
  fi
}

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

# Dep path (repo-relative) must satisfy the discovery regex
# '[a-z][a-z0-9-]+/skills/[a-z0-9-]+/SKILL\.md'.
DEP_REL="test-plugin/skills/test-dep/SKILL.md"
DRIVER_REL="test-plugin/skills/test-driver/SKILL.md"

# build_fixture <fixture-dir> <dep-modified-date> <driver-reviewed-date>
build_fixture() {
  local root="$1" dep_date="$2" driver_date="$3"
  mkdir -p "$root/scripts" "$root/$(dirname "$DEP_REL")" "$root/$(dirname "$DRIVER_REL")"
  cp "$src_check" "$root/scripts/check-driver-freshness.sh"

  cat > "$root/$DEP_REL" <<EOF
---
name: test-dep
description: A test dependency skill. Use when testing freshness.
modified: $dep_date
reviewed: $dep_date
---

# Test Dependency
EOF

  cat > "$root/$DRIVER_REL" <<EOF
---
name: test-driver
description: A test driver skill. Use when testing freshness.
reviewed: $driver_date
---

# Test Driver

## Dependencies

| Skill | Path |
|-------|------|
| \`/test:dep\` | \`$DEP_REL\` |
EOF
}

# run_fixture <fixture-dir>  → echoes combined stdout/stderr; exit code preserved
run_fixture() {
  bash "$1/scripts/check-driver-freshness.sh" \
    --driver "$DRIVER_REL" --max-age-days 100000 2>&1
}

# --- TEST A: equal dates pass (the #1704 invariant) ---------------------------
a="$tmp_root/equal"
build_fixture "$a" "2026-01-01" "2026-01-01"
out_a="$(run_fixture "$a")"; rc_a=$?
if [ "$rc_a" -eq 0 ]; then ok "equal dep date == driver reviewed → exit 0 (#1704)"; else ko "equal dep date == driver reviewed → exit 0 (#1704) [got exit $rc_a]"; fi
assert_has "equal-date run prints OK" "$out_a" "OK: Driver is fresh"

# --- TEST B: newer dep fails AND surfaces the compared epochs -----------------
b="$tmp_root/newer"
build_fixture "$b" "2026-02-01" "2026-01-01"
out_b="$(run_fixture "$b")"; rc_b=$?
if [ "$rc_b" -eq 1 ]; then ok "newer dep date → exit 1"; else ko "newer dep date → exit 1 [got exit $rc_b]"; fi
assert_has "FAIL output reports the dependency as newer" "$out_b" "newer than driver"
# Prove the new diagnostics: the raw epoch integers compared must appear. Derive
# them from the running platform's date so the test stays portable.
dep_epoch="$(date_to_epoch_portable "2026-02-01")"
driver_epoch="$(date_to_epoch_portable "2026-01-01")"
assert_has "FAIL output surfaces the dep epoch integer" "$out_b" "epoch ${dep_epoch}"
assert_has "FAIL output surfaces the driver epoch integer" "$out_b" "epoch ${driver_epoch}"

# --- TEST C: date→epoch parsing is time-of-day independent (the #1704 fix) ----
# The bug was that BSD `date -j -f "%Y-%m-%d"` substitutes the current
# time-of-day, so the same date string parsed a second apart yields different
# epochs. Parse the same date twice across a forced second boundary and assert
# the epochs are identical — the invariant the midnight-pinned parse guarantees.
c_first="$(date_to_epoch_portable "2026-02-01")"
sleep 1
c_second="$(date_to_epoch_portable "2026-02-01")"
if [ "$c_first" = "$c_second" ]; then
  ok "same date parses to a stable epoch across a second boundary (#1704 root cause)"
else
  ko "date parse is time-of-day dependent ($c_first != $c_second) — #1704 regressed"
fi

echo ""
echo "RESULTS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
