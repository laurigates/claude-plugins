#!/usr/bin/env bash
# Regression test for scripts/check-delegation-reachability.sh (issue #2442).
#
# SEMANTIC, not syntactic: every case EXECUTES the checker against a planted
# fixture tree and asserts on its structured output. A grep for a phrase in the
# checker would pass against a checker that never fires — the #1417 -> #1819
# lesson.
#
# The defect being guarded is a catalog-present skill whose prose tells the
# agent to act via a `disable-model-invocation: true` sibling it cannot reach.
# The risk in guarding it is the mirror image: a checker that flags every
# mention of a gated skill would be wrong in the common case (a "Related
# Skills" pointer, or a recommendation for the USER to run it), so the negative
# controls carry as much weight as the positive ones.

set -uo pipefail

# Neutralize inherited git context so sandbox git ops cannot reach the real
# checkout (issue #1745). This suite runs no git commands itself, but the
# checker falls back to `git rev-parse --show-toplevel`.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-delegation-reachability.sh"

pass_count=0
fail_count=0

ok() {
  pass_count=$((pass_count + 1))
  printf '  ok: %s\n' "$1"
}

bad() {
  fail_count=$((fail_count + 1))
  printf '  FAIL: %s\n' "$1"
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in
    *"$needle"*) ok "$label" ;;
    *) bad "$label (missing: $needle)" ;;
  esac
}

assert_lacks() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in
    *"$needle"*) bad "$label (unexpectedly present: $needle)" ;;
    *) ok "$label" ;;
  esac
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" = "$expected" ]; then
    ok "$label"
  else
    bad "$label (got '$actual', wanted '$expected')"
  fi
}

tmp_root="$(mktemp -d)"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "FAIL: could not create sandbox dir" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

# ---------------------------------------------------------------------------
# Fixture builder
#
#   $1  fixture root
#   $2  gated?          "gated" | "open"   (the SIBLING's frontmatter)
#   $3  section heading the reference sits under
#   $4  the reaction-table line referencing the sibling
# ---------------------------------------------------------------------------
build_fixture() {
  local root="$1" gated="$2" section="$3" ref_line="$4"
  local watch_dir="$root/demo-plugin/skills/demo-watch"
  local fb_dir="$root/demo-plugin/skills/demo-feedback"
  mkdir -p "$watch_dir" "$fb_dir"

  {
    printf -- '---\n'
    printf 'name: demo-feedback\n'
    if [ "$gated" = "gated" ]; then
      printf 'disable-model-invocation: true\n'
    fi
    printf 'description: "Address review threads. Use when acting on reviewer feedback."\n'
    printf -- '---\n\n'
    printf '# /demo:feedback\n\nBody.\n'
  } > "$fb_dir/SKILL.md"

  {
    printf -- '---\n'
    printf 'name: demo-watch\n'
    printf 'description: "Watch a PR. Use when monitoring a PR."\n'
    printf -- '---\n\n'
    printf '# /demo:watch\n\n'
    printf '## %s\n\n' "$section"
    printf '%s\n' "$ref_line"
  } > "$watch_dir/SKILL.md"
}

run_checker() {
  local root="$1"
  CHECK_DELEGATION_SCOPE="demo-plugin/skills/demo-watch/SKILL.md" \
    bash "$checker" --project-dir "$root" 2>&1
}

IMPERATIVE='| Review comment | Address it via **`/demo:feedback`** (the canonical engine) |'
HEDGED='| Review comment | Summarise the thread and **recommend the user run `/demo:feedback`** |'

echo "TEST A: the real repo passes, non-vacuously"
out="$(bash "$checker" --project-dir "$repo_root" 2>&1)"; rc=$?
assert_contains "$out" "STATUS=OK" "A1 real repo STATUS=OK"
assert_eq "$rc" "0" "A2 real repo exit 0"
# Guard integrity: STATUS=OK over zero files is what a collapsed scan reports
# (issue #2219), so the clean verdict must be attributable to a real read.
assert_contains "$out" "SCANNED_EMPTY=false" "A4 real repo scan not empty"
# The default scope must cover EVERY git-plugin skill that references a gated
# sibling from an action section. A one-file default reported STATUS=OK over a
# tree holding three live instances (#2442 review), so the scope is asserted by
# name rather than by count alone.
scanned_line="$(printf '%s\n' "$out" | grep -m1 '^FILES_SCANNED=' || true)"
scope_line="$(printf '%s\n' "$out" | grep -m1 '^SCOPE=' || true)"
assert_eq "$scanned_line" "FILES_SCANNED=${scanned_line#FILES_SCANNED=}" "A3 real repo reports a scan count"
if [ "${scanned_line#FILES_SCANNED=}" -ge 3 ] 2>/dev/null; then
  ok "A3b real repo scanned >= 3 skills (got ${scanned_line#FILES_SCANNED=})"
else
  bad "A3b real repo scanned >= 3 skills (got '$scanned_line')"
fi
assert_eq "$scope_line" "SCOPE=${scanned_line#FILES_SCANNED=}" "A3c every scoped path resolved to a file"
for scoped in git-pr-watch git-pr-sync-check git-triage; do
  assert_contains "$out" "git-plugin/skills/$scoped/SKILL.md" "A5 AUDITED names $scoped"
done
# STATUS=OK must never read as "the marketplace is clean".
assert_contains "$out" "SCOPE_IS_REPO_WIDE=false" "A6 audit set declared as scoped"

echo "TEST B: imperative delegation to a GATED sibling is an ERROR"
fx="$tmp_root/b"; build_fixture "$fx" gated "Execution" "$IMPERATIVE"
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "B1 STATUS=ERROR"
assert_eq "$rc" "1" "B2 exit 1"
assert_contains "$out" "TYPE=unreachable_delegation" "B3 finding type"
assert_contains "$out" "REF=/demo:feedback" "B4 names the reference"
assert_contains "$out" "SECTION=Execution" "B5 names the section"
assert_contains "$out" "ISSUE_COUNT=1" "B6 exactly one finding"

echo "TEST C: the SAME line, hedged toward the user, is clean"
# Without this the guard could satisfy TEST B by flagging every mention.
fx="$tmp_root/c"; build_fixture "$fx" gated "Execution" "$HEDGED"
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=OK" "C1 hedged wording STATUS=OK"
assert_eq "$rc" "0" "C2 hedged wording exit 0"
assert_contains "$out" "FILES_SCANNED=1" "C3 hedged fixture actually scanned"

echo "TEST D: gated status is read from the sibling's frontmatter"
# Same imperative wording, sibling NOT gated -> reachable -> nothing to report.
fx="$tmp_root/d"; build_fixture "$fx" open "Execution" "$IMPERATIVE"
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=OK" "D1 open sibling STATUS=OK"
assert_eq "$rc" "0" "D2 open sibling exit 0"
# Flip ONLY the sibling's frontmatter: the verdict must follow the flag.
printf '%s\n' "$(sed 's/^name: demo-feedback$/name: demo-feedback\ndisable-model-invocation: true/' "$fx/demo-plugin/skills/demo-feedback/SKILL.md")" \
  > "$fx/demo-plugin/skills/demo-feedback/SKILL.md"
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "D3 flag flip alone turns it ERROR"
assert_eq "$rc" "1" "D4 flag flip exit 1"

echo "TEST E: navigational sections are exempt, and narrowly so"
for section in "Related Skills" "When to Use This Skill" "See Also"; do
  fx="$tmp_root/e-$(printf '%s' "$section" | tr ' ' '-')"
  build_fixture "$fx" gated "$section" '- `/demo:feedback` — the engine'
  out="$(run_checker "$fx")"; rc=$?
  assert_contains "$out" "STATUS=OK" "E1 '$section' pointer is clean"
  assert_eq "$rc" "0" "E2 '$section' exit 0"
done
# Guard integrity: the exemption is per-section, not a blanket mute of bare
# pointers — the identical line under an action heading still fires.
fx="$tmp_root/e-action"; build_fixture "$fx" gated "Execution" '- `/demo:feedback` — the engine'
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "E3 same bare pointer under Execution is ERROR"
assert_eq "$rc" "1" "E4 same bare pointer under Execution exit 1"

echo "TEST F: a scoped skill that does not exist is loud, not clean"
fx="$tmp_root/f"; mkdir -p "$fx"
out="$(CHECK_DELEGATION_SCOPE="demo-plugin/skills/nope/SKILL.md" bash "$checker" --project-dir "$fx" 2>&1)"; rc=$?
assert_contains "$out" "TYPE=scoped_skill_missing" "F1 missing scoped skill reported"
assert_contains "$out" "FILES_SCANNED=0" "F2 zero files scanned"
assert_contains "$out" "SCANNED_EMPTY=true" "F3 empty scan is marked"
assert_eq "$rc" "1" "F4 exit 1"

echo "TEST G: an unknown argument exits 2 rather than being swallowed"
out="$(bash "$checker" --stricct 2>&1)"; rc=$?
assert_eq "$rc" "2" "G1 exit 2"
assert_contains "$out" "unknown argument" "G2 names the problem"
assert_lacks "$out" "=== DELEGATION REACHABILITY ===" "G3 scans nothing"

echo "TEST H: a worktree-shaped scan root still scans (issue #2219)"
fx="$tmp_root/h/.claude/worktrees/agent-deadbeef"
build_fixture "$fx" gated "Execution" "$IMPERATIVE"
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "FILES_SCANNED=1" "H1 worktree-shaped root scanned its file"
assert_contains "$out" "STATUS=ERROR" "H2 defect under a worktree-shaped root is still caught"
assert_eq "$rc" "1" "H3 exit 1"

echo "TEST I: a WEAKLY-hedged imperative is still an ERROR (#2442 review)"
# The first regex accepted a bare `suggest|recommend|user-invocable|manual`
# ANYWHERE on the line, so an imperative that merely NAMED the gate passed the
# guard. Each row below is still an instruction aimed at the agent.
i=0
for weak in \
  '| Review comment | Address it via **`/demo:feedback`** (user-invocable) |' \
  '| Review comment | Address it via **`/demo:feedback`** — a manual pass |' \
  '| Review comment | Suggested next step: run `/demo:feedback` |' \
  '| Review comment | Recommended: `/demo:feedback` |' \
  '| Review comment | Fix it by hand with `/demo:feedback` |'; do
  i=$((i + 1))
  fx="$tmp_root/i-$i"; build_fixture "$fx" gated "Execution" "$weak"
  out="$(run_checker "$fx")"; rc=$?
  assert_contains "$out" "STATUS=ERROR" "I$i weak hedge #$i still ERROR"
  assert_eq "$rc" "1" "I${i}b weak hedge #$i exit 1"
done
# Guard integrity: the tightening must not reject every referral form, or TEST C
# would be the only thing standing between this guard and "flag every mention".
j=0
for strong in \
  '| Review comment | Summarise it and **recommend the user run `/demo:feedback`** |' \
  '| Review comment | Surface the thread for the user to run `/demo:feedback` |' \
  '| Review comment | Report the thread and ask the user to run `/demo:feedback` |' \
  '| Review comment | Hand the thread off to the user, who runs `/demo:feedback` |'; do
  j=$((j + 1))
  fx="$tmp_root/i-ok-$j"; build_fixture "$fx" gated "Execution" "$strong"
  out="$(run_checker "$fx")"; rc=$?
  assert_contains "$out" "STATUS=OK" "I-ok$j referral form #$j stays clean"
  assert_eq "$rc" "0" "I-ok${j}b referral form #$j exit 0"
  assert_contains "$out" "FILES_SCANNED=1" "I-ok${j}c referral fixture actually scanned"
done

echo "TEST J: the referral marker is matched over the reference's LOGICAL UNIT"
# This repo wraps prose at ~80 columns, so a hedge and the token it hedges
# routinely land on different lines. A line-scoped match false-positives the
# moment a correct paragraph is reflowed (#2442 review).
fx="$tmp_root/j-wrapped"
# The hedge ends one line ABOVE the token it hedges — the exact split an
# 80-column reflow produces, and the case raw-line matching gets wrong.
build_fixture "$fx" gated "Execution" 'When a review lands, summarise the thread and recommend the user'
{
  printf 'run `/demo:feedback` for the reply pass, rather than replying here.\n'
} >> "$fx/demo-plugin/skills/demo-watch/SKILL.md"
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=OK" "J1 hedge one line above the ref stays clean"
assert_eq "$rc" "0" "J1b exit 0"
assert_contains "$out" "FILES_SCANNED=1" "J1c wrapped fixture actually scanned"

# Guard integrity #1: the paragraph window must STOP at a blank line, or a
# hedge belonging to an unrelated paragraph would exempt a live imperative.
fx="$tmp_root/j-blank"
build_fixture "$fx" gated "Execution" 'Earlier we recommend the user run something else entirely.'
{
  printf '\n'
  printf 'Address it via **`/demo:feedback`** (the canonical engine).\n'
} >> "$fx/demo-plugin/skills/demo-watch/SKILL.md"
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "J2 hedge across a blank line does NOT exempt"
assert_eq "$rc" "1" "J2b exit 1"

# Guard integrity #2: a table row is its own unit. Merging adjacent rows would
# let one row's hedge exempt a different row's imperative.
fx="$tmp_root/j-rows"
build_fixture "$fx" gated "Execution" '| Review comment | Summarise it and recommend the user run `/demo:feedback` |'
printf '| CI failure | Address it via **`/demo:feedback`** and re-push |\n' \
  >> "$fx/demo-plugin/skills/demo-watch/SKILL.md"
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "J3 a sibling row's hedge does NOT exempt the next row"
assert_contains "$out" "ISSUE_COUNT=1" "J3b exactly the unhedged row fires"
assert_eq "$rc" "1" "J3c exit 1"

echo
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
exit 0
