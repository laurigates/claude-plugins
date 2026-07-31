#!/usr/bin/env bash
# Smoke test for the scheduled-audits scripts (scripts/blueprint-health-check.sh
# and scripts/infra-compliance-check.sh).
#
# Guards the class of bug that froze the monthly scheduled-audits.yml jobs:
# under `set -euo pipefail`, both scripts must run to completion and exit 0.
#
# Two footguns motivated this test:
#   1. `((var++))` / `((var += N))` returns exit 1 when the pre-increment value
#      is 0, which `set -e` turns into a silent script-killing abort. Fixed by
#      switching to the assignment form `var=$((var+1))` (always exit 0).
#   2. A `declare -a arr` array with no element ever assigned is treated as
#      UNSET under `set -u`, so a later "${#arr[@]}" / "${arr[@]}" on a still-
#      empty array aborts the script. Fixed by seeding with `arr=()`.
#
# Both bugs are invisible in CI's failure log (the script dies before emitting
# anything), so a positive "exit 0 and produced output" assertion is the only
# reliable regression signal.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

run_audit() {
  # run_audit <label> <script-path> <expected-first-line-substring>
  local label="$1" script="$2" needle="$3"
  local out err audit_status
  out="$(mktemp)"
  err="$(mktemp)"

  bash "$script" >"$out" 2>"$err"
  audit_status=$?

  echo "=== $label ==="
  assert "$label exits 0 under set -euo pipefail" \
    "$([ "$audit_status" -eq 0 ] && echo true || echo false)"
  assert "$label writes nothing to stderr" \
    "$([ ! -s "$err" ] && echo true || echo false)"
  assert "$label produces a non-empty markdown report" \
    "$([ -s "$out" ] && echo true || echo false)"
  assert "$label report contains '$needle'" \
    "$(grep -q "$needle" "$out" && echo true || echo false)"

  if [ "$audit_status" -ne 0 ] && [ -s "$err" ]; then
    echo "  stderr:" >&2
    sed 's/^/    /' "$err" >&2
  fi

  rm -f "$out" "$err"
}

run_audit "blueprint-health-check.sh" \
  "$repo_root/scripts/blueprint-health-check.sh" \
  "Monthly Blueprint Health"

run_audit "infra-compliance-check.sh" \
  "$repo_root/scripts/infra-compliance-check.sh" \
  "Infrastructure Compliance Dashboard"


##########
# Unbounded-recursive-walk guard (#2214 class)
##########
#
# infra-compliance-check.sh once carried `find . -path '*/skills/*' -iname SKILL.md`
# with no prune. Every agent worktree under `.claude/worktrees/` is a full repo
# clone, so in a checkout with 63 worktrees that walked ~26,000 files instead of
# ~408 and the whole script timed out past 120s. It was removed with the
# bare-Bash detector it served.
#
# A wall-clock bound ALONE cannot guard this: CI checks out a clean tree with no
# worktrees, so a reintroduced unpruned walk would be fast there and the bound
# would pass. The load-bearing half is therefore STRUCTURAL — assert that every
# `find` in the audit scripts is bounded — with the timing check kept only as a
# cheap backstop for a local run, where worktrees do exist.
#
# A find is bounded when it either:
#   - carries -maxdepth, or
#   - prunes .claude/worktrees, or
#   - starts from a specific subdirectory rather than `.` (e.g. "$plugin/skills",
#     .github/workflows) — such a walk cannot reach .claude/worktrees.

assert_finds_bounded() {
  # assert_finds_bounded <label> <script-path>
  local label="$1" script="$2" line n=0 bad=0
  # Strip whole-line comments BEFORE extracting, so the prose explaining the
  # removed unpruned walk (which necessarily quotes it) is not itself a finding.
  local code
  code="$(grep -vE '^[[:space:]]*#' "$script")"
  while IFS= read -r line; do
    n=$((n + 1))
    if grep -qE -- '-maxdepth' <<<"$line"; then continue; fi
    if grep -qE -- '\.claude/worktrees' <<<"$line"; then continue; fi
    # `find <path>` where <path> is not a bare `.`
    if grep -qE -- 'find[[:space:]]+("?\$|[^.[:space:]])' <<<"$line"; then continue; fi
    echo "  unbounded: $line" >&2
    bad=$((bad + 1))
  done < <(grep -oE 'find[[:space:]]+[^|)]*' <<<"$code" | grep -v '^find[[:space:]]*$')

  echo "=== $label: find-boundedness ==="
  assert "$label has at least one find (guard is not vacuous)" \
    "$([ "$n" -gt 0 ] && echo true || echo false)"
  assert "$label has no unbounded recursive find" \
    "$([ "$bad" -eq 0 ] && echo true || echo false)"
}

assert_finds_bounded "blueprint-health-check.sh" "$repo_root/scripts/blueprint-health-check.sh"
assert_finds_bounded "infra-compliance-check.sh" "$repo_root/scripts/infra-compliance-check.sh"

# Wall-clock backstop. Generous on purpose: it is a catastrophe detector, not a
# performance budget. Post-fix the script runs ~5s on a clean tree and the
# pre-fix version exceeded 120s in a 63-worktree checkout. Override for a slow
# box with AUDIT_SCRIPT_MAX_SECONDS.
max_seconds="${AUDIT_SCRIPT_MAX_SECONDS:-90}"
now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(int(time.time()*1000))'
  else
    echo $(( $(date +%s) * 1000 ))
  fi
}
for audit_script in blueprint-health-check.sh infra-compliance-check.sh; do
  t0=$(now_ms)
  bash "$repo_root/scripts/$audit_script" >/dev/null 2>&1 || true
  t1=$(now_ms)
  elapsed_ms=$(( t1 - t0 ))
  echo "=== $audit_script: ${elapsed_ms}ms (bound ${max_seconds}s) ==="
  assert "$audit_script completes within ${max_seconds}s" \
    "$([ "$elapsed_ms" -lt $(( max_seconds * 1000 )) ] && echo true || echo false)"
done

echo ""
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
