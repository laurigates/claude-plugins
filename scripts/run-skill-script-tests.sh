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
#   - `./scripts/tests/test-*.sh` — the self-tests of the repo-root `check-*.sh`
#     guards. Anchored at the scan root on purpose: the walk runs from INSIDE
#     the root against `.`-relative paths (see the `find` below), so `./scripts`
#     means "this tree's scripts dir" and nothing else. A `*/scripts/tests/…`
#     spelling would also swallow unrelated nested trees, and an ABSOLUTE
#     spelling would reintroduce the #2219 prune collapse. Before this glob, a
#     guard at `scripts/check-*.sh` had a self-test the runner never picked up,
#     so it got no CI signal unless someone hand-wired a step into
#     plugin-pr-checks.yml — three guards shipped that way (#2219, #2221, #2333).
#
# Deliberate overlap, not an oversight: 27 of the 44 repo-root tests ALSO run as
# their own hand-wired step in `plugin-pr-checks.yml` (paired with the matching
# `check-*.sh --strict` run). That workflow carries NO `paths:` filter because
# `compliance` is a required check, so those steps are the only ALWAYS-ON signal
# for those guards; this runner is path-filtered. Both are kept on purpose — the
# steps stay locality-paired with the guard they validate, and the runner is the
# blanket net that catches the 17 tests no workflow step names at all. If you
# prune the duplicated steps later, note that you are moving them behind a path
# filter and off the required check.
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
# Scoping: `--only <glob>` (repeatable) restricts the run to discovered tests
# whose REPO-RELATIVE path matches at least one glob. The pattern is a plain
# shell glob matched with `case`, so `*` DOES cross `/`:
# `--only '*-plugin/hooks/test-*.sh'` selects every hook suite. Scoping exists
# so a caller can run a cheap subset without dragging a heavy toolchain
# (ast-grep, cargo-generate, a source-built taskwarrior) into a required check.
# It is NOT a way to make a red run green.
#
# A required test OUTSIDE the requested scope is **not in scope** — it is
# neither run nor counted as skipped, and it raises neither
# `required_test_skipped` nor `required_test_missing`. It is DEFERRED to the
# unscoped run, which is the only run that discharges the whole manifest. A
# scoped run therefore can never claim the manifest was satisfied:
# `REQUIRED_IN_SCOPE=` and `REQUIRED_OUT_OF_SCOPE=` are always emitted so the
# output states which. Inside the scope the ratchet keeps its full teeth — an
# in-scope required test that skips is still an ERROR, as is an in-scope
# manifest entry that no discovered test matches.
#
# A `--only` that matches NOTHING is an ERROR (`TYPE=scope_matched_nothing`),
# not a WARN: the caller named a scope explicitly, so matching zero suites is a
# misfire — a typo'd glob, or a plugin that moved — and must never read as a
# pass. That is the anti-mass-SKIP guard for scoped callers. `DISCOVERED=`
# (files found BEFORE scoping) is emitted beside `TOTAL=` so a scope misfire is
# distinguishable from a discovery collapse. An UNSCOPED empty corpus keeps its
# greenfield-safe WARN (see above) — that contract is unchanged.
#
# Usage: bash scripts/run-skill-script-tests.sh [--root <dir>] [--required-file <path>] [--only <glob>]...
#
# Exit codes: 0 = OK or WARN, 1 = ERROR (a failure, a required-test violation,
#             or a --only that matched nothing), 2 = unknown argument, an empty
#             --only value, or a --root that does not resolve.

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/run-skill-script-tests.sh [--root <dir>] [--required-file <path>] [--only <glob>]...

  --root <dir>            Directory to discover tests under (default: .)
  --required-file <path>  Manifest of tests that must not SKIP
                          (default: <root>/scripts/required-to-run-tests.txt;
                           absent file = no required set)
  --only <glob>           Run only discovered tests whose repo-relative path
                          matches this shell glob. Repeatable (any match wins).
                          `*` crosses `/`. A required test outside the scope is
                          DEFERRED, not skipped — see REQUIRED_OUT_OF_SCOPE=.
                          A glob matching nothing is an ERROR, never a pass.
EOF
}

root_dir="."
required_file=""
required_file_given=0
scope_patterns=()

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "run-skill-script-tests.sh: --root needs a value" >&2; exit 2; }
      root_dir="$2"; shift 2 ;;
    --required-file)
      [ $# -ge 2 ] || { echo "run-skill-script-tests.sh: --required-file needs a value" >&2; exit 2; }
      required_file="$2"; required_file_given=1; shift 2 ;;
    --only)
      [ $# -ge 2 ] || { echo "run-skill-script-tests.sh: --only needs a value" >&2; exit 2; }
      # An empty glob matches nothing, which would surface as a scope misfire
      # rather than as the argument error it actually is. Reject it up front.
      [ -n "$2" ] || { echo "run-skill-script-tests.sh: --only needs a non-empty glob" >&2; exit 2; }
      scope_patterns+=("$2"); shift 2 ;;
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

# Absolute form of the root, used only to invoke a discovered test. Discovery
# itself runs from INSIDE the root against relative paths (see the `find` below),
# so the loop needs the absolute base back to build a runnable path without
# depending on the caller's cwd.
root_abs="$(cd "$root_dir" 2>/dev/null && pwd)" || root_abs=""
if [ -z "$root_abs" ]; then
  # A root that does not resolve must not read as "found nothing" — that is the
  # same silent-empty-corpus failure this runner reports on (#2219). Fail fast.
  echo "run-skill-script-tests.sh: --root does not resolve to a directory: $root_dir" >&2
  exit 2
fi

# Repo-relative form of a discovered path, for manifest matching and reporting.
# Discovery runs from inside the root, so every path arrives as `./<rel>`
# regardless of how --root was spelled; stripping the `./` is all that is needed.
norm_path() {
  local p="$1"
  printf '%s' "${p#./}"
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

scope_count=${#scope_patterns[@]}

# Per-pattern match counters. An AGGREGATE "did anything match?" guard is not
# enough: with one good glob and one stale one, the stale glob is silently
# ignored and the run still reports STATUS=OK. That is strictly weaker than the
# hand-written `run: bash scripts/tests/test-foo.sh` steps this scoping replaced,
# which failed loudly (exit 127) the moment a test was renamed. A renamed test
# must not be able to fall out of a REQUIRED check while the check stays green.
scope_hits=()
for _ in ${scope_patterns[@]+"${scope_patterns[@]}"}; do scope_hits+=(0); done
# in_scope() is called over BOTH discovered tests and required-manifest entries.
# Only discovery counts as a real match — a manifest entry is a declaration, not
# a file on disk, so letting it mark a glob "hit" would mask a stale glob.
scope_record_hits=1

# A repo-relative path is in scope when no --only was given, or when it matches
# at least one --only glob. `$pattern` is deliberately UNQUOTED inside `case` so
# it is expanded as a glob rather than compared literally.
in_scope() {
  local candidate="$1" pattern i=0 hit=1
  [ "$scope_count" -eq 0 ] && return 0
  for pattern in ${scope_patterns[@]+"${scope_patterns[@]}"}; do
    # shellcheck disable=SC2254
    case "$candidate" in
      $pattern)
        if [ "$scope_record_hits" -eq 1 ]; then
          scope_hits[$i]=$(( ${scope_hits[$i]} + 1 ))
        fi
        hit=0 ;;
    esac
    i=$(( i + 1 ))
  done
  return "$hit"
}

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
discovered=0
out_of_scope=0
required_violations=0
seen_required=""
issues=""
skip_list=""

# Prune `.claude/worktrees/` (sibling agent clones of the whole repo, #1492) so
# we don't run the same test many times over from worktree copies.
#
# Discovery runs from INSIDE the root against RELATIVE paths (#2219). With an
# absolute base, the bare `*/.claude/worktrees/*` prune fires on the whole tree
# whenever the root is ITSELF an agent worktree — its own path contains
# `/.claude/worktrees/`, so every descendant matches, the scan root is pruned
# entirely, and the runner reports TOTAL=0 having discovered nothing. Since
# worktree-isolated subagents are this repo's normal way of doing plugin work,
# that made an agent's own local `--root "$PWD"` verification structurally
# incapable of finding a test. Relative paths make the root `.`, so its absolute
# prefix cannot match while worktree copies nested ANYWHERE below it still prune
# correctly. Same fix, and same reasoning, as scripts/check-agent-model.sh and
# scripts/check-subagent-types.sh.
while IFS= read -r -d '' test_file; do
  rel="$(norm_path "$test_file")"
  discovered=$((discovered + 1))
  # Scope filter. An out-of-scope test is neither run nor counted: it is
  # DEFERRED, never SKIPPED. Folding it into SKIPPED= would make every scoped
  # run look like the mass-SKIP the accounting ratchet exists to catch.
  if ! in_scope "$rel"; then
    out_of_scope=$((out_of_scope + 1))
    continue
  fi
  total=$((total + 1))
  log_file="$(mktemp)"
  # </dev/null: the loop's stdin IS the find stream — a test that reads stdin
  # would otherwise swallow the remaining file list (and mis-parse it as its
  # own input). Observed with hooks-plugin/hooks/test-verification.sh.
  if bash "${root_abs}/${rel}" >"$log_file" 2>&1 </dev/null; then
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
done < <(cd "$root_abs" && find . \
  -path '*/.claude/worktrees/*' -prune -o \
  \( -path '*/skills/*/scripts/tests/test-*.sh' -o -path '*-plugin/scripts/tests/test-*.sh' -o -path '*/hooks/test-*.sh' -o -path './scripts/tests/test-*.sh' \) \
  -type f -print0 | sort -z)

# A manifest entry that matched no discovered test is drift — the guard would
# silently stop guarding that path (the allowlist-drift class).
#
# Scoping narrows WHICH entries that rule applies to. An entry outside the
# requested scope was never eligible to run, so calling it missing would turn
# every scoped run into a false ERROR; it is counted as out-of-scope instead and
# left to the unscoped run. An entry INSIDE the scope keeps the full rule.
scope_record_hits=0
required_in_scope=0
required_out_of_scope=0
for entry in ${required_tests[@]+"${required_tests[@]}"}; do
  if ! in_scope "$entry"; then
    required_out_of_scope=$((required_out_of_scope + 1))
    continue
  fi
  required_in_scope=$((required_in_scope + 1))
  if ! printf '%s' "$seen_required" | grep -qxF "$entry"; then
    required_violations=$((required_violations + 1))
    issues="${issues}  - SEVERITY=ERROR TYPE=required_test_missing TEST=${entry}\n"
  fi
done

# An explicit --only that selected nothing is a caller misfire, not an empty
# corpus — the anti-mass-SKIP guard. DISCOVERED= tells the two apart.
scope_misfires=0
if [ "$scope_count" -gt 0 ] && [ "$total" -eq 0 ]; then
  scope_misfires=1
  issues="${issues}  - SEVERITY=ERROR TYPE=scope_matched_nothing DISCOVERED=${discovered} MSG=no discovered test matched any --only glob\n"
fi

# Each individual glob must match something too. This is the guard that keeps a
# renamed or deleted test from quietly leaving a scoped required check.
scope_index=0
for scope_pattern in ${scope_patterns[@]+"${scope_patterns[@]}"}; do
  if [ "${scope_hits[$scope_index]}" -eq 0 ]; then
    scope_misfires=$(( scope_misfires + 1 ))
    issues="${issues}  - SEVERITY=ERROR TYPE=scope_pattern_matched_nothing PATTERN=${scope_pattern} DISCOVERED=${discovered} MSG=glob matched no discovered test - renamed or deleted?\n"
  fi
  scope_index=$(( scope_index + 1 ))
done

issue_count=$((failed + required_violations + scope_misfires))

echo "DISCOVERED=${discovered}"
echo "TOTAL=${total}"
echo "PASSED=${passed}"
echo "SKIPPED=${skipped}"
echo "FAILED=${failed}"
if [ "$scope_count" -gt 0 ]; then
  echo "SCOPED=true"
else
  echo "SCOPED=false"
fi
echo "SCOPE_PATTERN_COUNT=${scope_count}"
scope_index=0
for scope_pattern in ${scope_patterns[@]+"${scope_patterns[@]}"}; do
  echo "SCOPE_PATTERN_$((scope_index + 1))=${scope_pattern}"
  echo "SCOPE_PATTERN_$((scope_index + 1))_MATCHED=${scope_hits[$scope_index]}"
  scope_index=$((scope_index + 1))
done
echo "OUT_OF_SCOPE=${out_of_scope}"
echo "REQUIRED_DECLARED=${#required_tests[@]}"
echo "REQUIRED_IN_SCOPE=${required_in_scope}"
echo "REQUIRED_OUT_OF_SCOPE=${required_out_of_scope}"
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
