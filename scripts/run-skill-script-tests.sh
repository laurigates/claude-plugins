#!/usr/bin/env bash
# Run every skill-local and hook regression test in the repo.
#
# Discovers and runs:
#   - `*/skills/*/scripts/tests/test-*.sh` — colocated tests next to a skill's
#     extracted scripts (canonical reference:
#     health-plugin/skills/health-check/scripts/tests/test-check-settings.sh)
#   - `*-plugin/scripts/tests/test-*.sh` — plugin-level shared-script suites
#     (e.g. session-plugin/scripts/tests/test-session-survey.sh)
#   - `*/hooks/test-*.sh` — plugin hook regression suites (bash-antipatterns,
#     branch-protection, pr-metadata, session-end-nudge, …). Before this glob
#     was added the hook suites only ran when invoked by hand.
#
# Used by the `just test-skill-scripts` recipe and the `Test: Skill scripts`
# CI workflow so local and CI run the identical discovery (local↔CI parity).
#
# A test may SKIP (exit 0 having emitted nothing but `SKIP:` / `SKIP -` notices)
# when a dependency is absent. **A skip is not a pass.** It is reported as
# `SKIP=<path>`, counted in `SKIPPED=`, and itemised with its reason under
# `SKIPS:`. This runner used to print `PASS=` for a skipped test, which is how
# the foundryvtt template-parity acceptance gate ran nowhere for weeks while
# the CI log read entirely green (issue #2221) — a test that did not run and a
# test that passed must never be indistinguishable.
#
# Tests listed in `scripts/required-to-run-tests.txt` are *expected* to execute
# on the CI runner — the workflow installs their dependency on purpose. A skip
# there is an ERROR (exit 1), not a warning, as is a listed path that no longer
# exists (the manifest must not drift from the corpus it declares).
#
# Exits 0 when no tests are found (greenfield) so the runner is safe to wire in
# before any test exists — but reports `SCANNED_EMPTY=true` and `STATUS=WARN`
# rather than a clean `OK`, because "found nothing" and "checked nothing" must
# not look alike either (the denominator half of #2221, same hole #2255/#2290
# found in the `check-*.sh` guards: a value assertion with no companion check
# that anything was scanned). Note that a non-empty required-test manifest
# already converts a discovery collapse into an ERROR by construction — every
# declared entry raises `required_test_missing` — so in this repo, where five
# tests are declared, TOTAL=0 exits 1 rather than warning.
#
# Emits the `structured-script-output.md` contract: `=== … ===` delimiters,
# `KEY=VALUE` body, `STATUS=`, `ISSUE_COUNT=`.
#
# Usage: bash scripts/run-skill-script-tests.sh [--root <dir>] [--required-file <path>]
#
# Exit codes: 0 = OK or WARN, 1 = ERROR (a failure or a required-test violation),
#             2 = unknown argument.

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/run-skill-script-tests.sh [--root <dir>] [--required-file <path>]

  --root <dir>            Directory to discover tests under (default: .)
  --required-file <path>  Manifest of tests that must not SKIP
                          (default: <root>/scripts/required-to-run-tests.txt;
                           absent file = no required set)
EOF
}

root_dir="."
required_file=""
required_file_given=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "run-skill-script-tests.sh: --root needs a value" >&2; exit 2; }
      root_dir="$2"; shift 2 ;;
    --required-file)
      [ $# -ge 2 ] || { echo "run-skill-script-tests.sh: --required-file needs a value" >&2; exit 2; }
      required_file="$2"; required_file_given=1; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "run-skill-script-tests.sh: unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

if [ "$required_file_given" -eq 0 ]; then
  required_file="${root_dir}/scripts/required-to-run-tests.txt"
fi

# Repo-relative form of a discovered path, so it can be matched against the
# manifest regardless of whether --root was `.` or an absolute fixture dir.
norm_path() {
  local p="$1"
  p="${p#"$root_dir"/}"
  p="${p#./}"
  printf '%s' "$p"
}

# A run counts as SKIPPED when it exited 0 and every non-empty, non-indented
# line it produced is a SKIP notice. Indented lines are continuation detail
# (`      Install: npm install -g @ast-grep/cli`), so they do not disqualify a
# skip; a non-indented line that is not a SKIP notice means real work ran, so a
# *partial* skip inside an otherwise-executing suite is correctly a PASS.
is_skipped_log() {
  local log="$1"
  grep -qE '^SKIP([: ]|$)' "$log" || return 1
  # Any non-indented line that is NOT a SKIP notice disqualifies the skip.
  if grep -E '^[^[:space:]]' "$log" | grep -qvE '^SKIP([: ]|$)'; then
    return 1
  fi
  return 0
}

skip_reason() {
  local log="$1"
  grep -m1 -E '^SKIP([: ]|$)' "$log" | sed -E 's/^SKIP[[:space:]]*[:-]?[[:space:]]*//'
}

required_tests=()
if [ -f "$required_file" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$line" ] && required_tests+=("$line")
  done < "$required_file"
fi

is_required() {
  local candidate="$1" entry
  for entry in ${required_tests[@]+"${required_tests[@]}"}; do
    [ "$entry" = "$candidate" ] && return 0
  done
  return 1
}

echo "=== SKILL SCRIPT TESTS ==="

failed=0
passed=0
skipped=0
total=0
required_violations=0
seen_required=""
issues=""
skip_list=""

# Prune `.claude/worktrees/` (sibling agent clones of the whole repo, #1492) so
# we don't run the same test many times over from worktree copies.
while IFS= read -r -d '' test_file; do
  total=$((total + 1))
  rel="$(norm_path "$test_file")"
  log_file="$(mktemp)"
  # </dev/null: the loop's stdin IS the find stream — a test that reads stdin
  # would otherwise swallow the remaining file list (and mis-parse it as its
  # own input). Observed with hooks-plugin/hooks/test-verification.sh.
  if bash "$test_file" >"$log_file" 2>&1 </dev/null; then
    if is_skipped_log "$log_file"; then
      reason="$(skip_reason "$log_file")"
      echo "SKIP=${test_file}"
      skipped=$((skipped + 1))
      skip_list="${skip_list}  - ${rel} (${reason})\n"
      if is_required "$rel"; then
        required_violations=$((required_violations + 1))
        issues="${issues}  - SEVERITY=ERROR TYPE=required_test_skipped TEST=${rel} MSG=${reason}\n"
      fi
    else
      echo "PASS=${test_file}"
      passed=$((passed + 1))
    fi
  else
    echo "FAIL=${test_file}"
    sed 's/^/  | /' "$log_file"
    failed=$((failed + 1))
    issues="${issues}  - SEVERITY=ERROR TYPE=test_failed TEST=${rel}\n"
  fi
  if is_required "$rel"; then
    seen_required="${seen_required}${rel}"$'\n'
  fi
  rm -f "$log_file"
done < <(find "$root_dir" \
  -path '*/.claude/worktrees/*' -prune -o \
  \( -path '*/skills/*/scripts/tests/test-*.sh' -o -path '*-plugin/scripts/tests/test-*.sh' -o -path '*/hooks/test-*.sh' \) \
  -type f -print0 | sort -z)

# A manifest entry that matched no discovered test is drift — the guard would
# silently stop guarding that path (the allowlist-drift class).
for entry in ${required_tests[@]+"${required_tests[@]}"}; do
  if ! printf '%s' "$seen_required" | grep -qxF "$entry"; then
    required_violations=$((required_violations + 1))
    issues="${issues}  - SEVERITY=ERROR TYPE=required_test_missing TEST=${entry}\n"
  fi
done

issue_count=$((failed + required_violations))

echo "TOTAL=${total}"
echo "PASSED=${passed}"
echo "SKIPPED=${skipped}"
echo "FAILED=${failed}"
echo "REQUIRED_DECLARED=${#required_tests[@]}"
echo "REQUIRED_VIOLATIONS=${required_violations}"
if [ "$total" -eq 0 ]; then
  echo "SCANNED_EMPTY=true"
else
  echo "SCANNED_EMPTY=false"
fi
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
elif [ "$skipped" -gt 0 ] || [ "$total" -eq 0 ]; then
  echo "STATUS=WARN"
else
  echo "STATUS=OK"
fi
echo "ISSUE_COUNT=${issue_count}"
if [ "$skipped" -gt 0 ]; then
  echo "SKIPS:"
  printf '%b' "$skip_list"
fi
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%b' "$issues"
fi
echo "=== END SKILL SCRIPT TESTS ==="

[ "$issue_count" -eq 0 ]
