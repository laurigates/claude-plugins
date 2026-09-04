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

# File-level, and it must precede the first command (`.claude/rules/
# shell-scripting.md` § "Suppressing shellcheck findings"). SC2016 fires on
# every fixture string carrying a literal `/demo:feedback` in backticks inside
# single quotes — which is the point: the fixture text must reach the checker
# unexpanded. Pre-existing on `main`; suppressed here rather than churning
# ~20 deliberate assertions into escaped double quotes.
# shellcheck disable=SC2016
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

# ---------------------------------------------------------------------------
# Free-form builders for the #2483 exemption classes, where the SHAPE of the
# scanned file (preamble vs section, self-reference vs sibling) is the variable
# under test rather than one substituted table row.
#
#   mk_sibling  <root> <skill-dir-name> <gated|open>
#   mk_watch    <root> <gated|open>   # body on stdin, appended after the ---
# ---------------------------------------------------------------------------
mk_sibling() {
  local root="$1" nm="$2" gated="$3"
  local d="$root/demo-plugin/skills/$nm"
  mkdir -p "$d"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$nm"
    if [ "$gated" = "gated" ]; then
      printf 'disable-model-invocation: true\n'
    fi
    printf 'description: "Do a thing. Use when doing the thing."\n'
    printf -- '---\n\n'
    printf '# /demo:%s\n\n## Execution\n\nBody.\n' "${nm#demo-}"
  } > "$d/SKILL.md"
}

mk_watch() {
  local root="$1" gated="$2"
  local d="$root/demo-plugin/skills/demo-watch"
  mkdir -p "$d"
  {
    printf -- '---\n'
    printf 'name: demo-watch\n'
    if [ "$gated" = "gated" ]; then
      printf 'disable-model-invocation: true\n'
    fi
    printf 'description: "Watch a PR. Use when monitoring a PR."\n'
    printf -- '---\n\n'
    cat
  } > "$d/SKILL.md"
}

# Whole-line KEY=VALUE read: an unanchored substring match on `SCANNED=1` is
# satisfied by any sibling `*_SCANNED=1` key (#2219 follow-up).
key_of() {
  printf '%s\n' "$1" | grep -m1 "^$2=" || true
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
# Since #2483 the default scope is the WHOLE marketplace, discovered at run
# time. A one-file default once reported STATUS=OK over a tree holding three
# live instances (#2442 review), so coverage is asserted against an independent
# count of the corpus rather than against the checker's own claim.
scanned_line="$(key_of "$out" FILES_SCANNED)"
scope_line="$(key_of "$out" SCOPE)"
corpus_count="$(find "$repo_root" \
  -path "$repo_root/.claude/worktrees/*" -prune -o \
  -path "$repo_root/dist/*" -prune -o \
  -path '*-plugin/skills/*/SKILL.md' -print | grep -c . || true)"
if [ "${corpus_count:-0}" -ge 100 ] 2>/dev/null; then
  ok "A3 the marketplace corpus is non-trivial (got $corpus_count skills)"
else
  bad "A3 the marketplace corpus is non-trivial (got '$corpus_count')"
fi
assert_eq "$scanned_line" "FILES_SCANNED=$corpus_count" "A3b every marketplace skill was scanned"
assert_eq "$scope_line" "SCOPE=$corpus_count" "A3c every scoped path resolved to a file"
# STATUS=OK now DOES mean the marketplace is clean — of anything not declared.
assert_contains "$out" "SCOPE_IS_REPO_WIDE=true" "A5 audit set declared as repo-wide"
# A suppressed finding must never be indistinguishable from no finding, so the
# counter is emitted even at 0 and the declared set is itemised (#2219/#2255).
allow_line="$(key_of "$out" ALLOWLISTED)"
assert_eq "$allow_line" "ALLOWLISTED=${allow_line#ALLOWLISTED=}" "A6 real repo reports an allowlist count"
if [ "${allow_line#ALLOWLISTED=}" -gt 0 ] 2>/dev/null; then
  assert_contains "$out" "ALLOWLISTED_DELEGATIONS:" "A6b declared residuals are itemised"
  assert_contains "$out" "OWNER=#2483" "A6c each residual names its owning issue"
fi

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

echo "TEST K: a skill's reference to ITSELF is never a delegation (issue #2483)"
# Class A, 30 of the 47 full-corpus findings. `git-api-pr` is gated AND writes
# `/git:api-pr` in its own Quick Reference table, so the guard reported the
# skill for documenting its own invocation.
fx="$tmp_root/k-self"; mk_sibling "$fx" demo-feedback gated
# No H1 title line here: the H1 is itself a self-reference sitting in the
# preamble, and keeping K1d/K2d free of it makes those counter assertions
# guard integrity for Class A alone rather than for Class B as well.
mk_watch "$fx" gated <<'EOF'
## Agentic Optimizations

| Task | Command |
|------|---------|
| Single file fix | `/demo:watch file.ts --title "fix: typo"` |
| Multi-file fix  | `/demo:watch a.ts b.ts --title "fix: update configs"` |
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=OK" "K1 self-reference is clean"
assert_eq "$rc" "0" "K1b exit 0"
assert_eq "$(key_of "$out" FILES_SCANNED)" "FILES_SCANNED=1" "K1c self-reference fixture actually scanned"
assert_eq "$(key_of "$out" SELF_REFS_SKIPPED)" "SELF_REFS_SKIPPED=2" "K1d both self-references counted"

# Guard integrity: the exemption is SELF-reference, not "any reference in a
# Quick Reference table". The identical shape aimed at a DIFFERENT gated
# sibling must still fire, or K1 could pass against a checker that stopped
# judging Agentic Optimizations sections.
fx="$tmp_root/k-sibling"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" gated <<'EOF'
## Agentic Optimizations

| Task | Command |
|------|---------|
| Single file fix | `/demo:feedback file.ts --title "fix: typo"` |
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "K2 the same row aimed at a sibling still ERRORs"
assert_eq "$rc" "1" "K2b exit 1"
assert_contains "$out" "REF=/demo:feedback" "K2c names the sibling reference"
assert_eq "$(key_of "$out" SELF_REFS_SKIPPED)" "SELF_REFS_SKIPPED=0" "K2d counter is attributable, not always-on"

echo "TEST L: the preamble before the first '## ' heading is not an action section"
# Class B. `section` is only set on H2, so frontmatter, the `# /ns:command` H1
# this repo puts at the top, and any lead paragraph were all judged with
# `section=""` — which `is_navigational_section` does not exempt.
fx="$tmp_root/l-preamble"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

Submit a PR. The simpler `/demo:feedback` covers the aligned case; this skill
handles the diverged one.

## Execution

Run the plan.
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=OK" "L1 preamble reference is clean"
assert_eq "$rc" "0" "L1b exit 0"
assert_eq "$(key_of "$out" FILES_SCANNED)" "FILES_SCANNED=1" "L1c preamble fixture actually scanned"

# Guard integrity: the exemption ENDS at the first H2. The identical sentence
# moved under `## Execution` must still fire, or L1 would be satisfied by a
# checker that had stopped reading files at all.
fx="$tmp_root/l-execution"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

Submit a PR. The simpler `/demo:feedback` covers the aligned case; this skill
handles the diverged one.
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "L2 the same text under '## Execution' still ERRORs"
assert_eq "$rc" "1" "L2b exit 1"
assert_contains "$out" "SECTION=Execution" "L2c names the section"

echo "TEST M: teaching the invariant is not delegating (issue #2483)"
# Class C — the most important exemption. The unit below states the guard's OWN
# rule correctly AND forbids the invocation; flagging it makes the guard red on
# correct content, which is how a guard gets disabled. Text is the verbatim
# `blueprint-autopilot` shape, wrapped exactly as it ships.
fx="$tmp_root/m-teach"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

Skip this step entirely unless the Context config shows `WO_AUTO_DRAFT=true`.
Work-order **creation stays human-only** (`/demo:feedback` keeps
`disable-model-invocation: true` — never invoke it from autopilot). Autopilot
may only file *proposals*.
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=OK" "M1 teaching the invariant is clean"
assert_eq "$rc" "0" "M1b exit 0"
assert_eq "$(key_of "$out" GATED_STATEMENT_EXEMPTIONS)" "GATED_STATEMENT_EXEMPTIONS=1" "M1c exemption is reported, not silent"
assert_eq "$(key_of "$out" FILES_SCANNED)" "FILES_SCANNED=1" "M1d teaching fixture actually scanned"

# One marker per form — no sentence below carries two — so dropping a single
# alternative from GATED_STATEMENT_RE turns exactly one row red instead of
# being masked by a neighbouring marker in the same sentence.
m=0
for teach in \
  'Never invoke `/demo:feedback` from this skill.' \
  'Work-order creation stays human-only, so route around `/demo:feedback`.' \
  '`/demo:feedback` keeps `disable-model-invocation: true`, so route around it.' \
  'The model cannot reach `/demo:feedback` from here.'; do
  m=$((m + 1))
  fx="$tmp_root/m-form-$m"; mk_sibling "$fx" demo-feedback gated
  mk_watch "$fx" open <<EOF
# /demo:watch

## Execution

$teach
EOF
  out="$(run_checker "$fx")"; rc=$?
  assert_contains "$out" "STATUS=OK" "M2-$m gated-statement form #$m stays clean"
  assert_eq "$rc" "0" "M2-${m}b gated-statement form #$m exit 0"
done

# Guard integrity: a bare imperative on a comparable line must still ERROR, and
# the exemption counter must stay 0 — without this, a regex that matched
# everything would satisfy every assertion above.
fx="$tmp_root/m-imperative"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

Address it via `/demo:feedback` (the canonical engine).
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "M3 a bare imperative still ERRORs"
assert_eq "$rc" "1" "M3b exit 1"
assert_eq "$(key_of "$out" GATED_STATEMENT_EXEMPTIONS)" "GATED_STATEMENT_EXEMPTIONS=0" "M3c counter is attributable, not always-on"

# The weak hedges of TEST I must not have become gated statements by accident.
fx="$tmp_root/m-weak"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

Address it via `/demo:feedback` (user-invocable) — a manual pass.
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "M4 'user-invocable'/'manual' is not a gated statement"
assert_eq "$rc" "1" "M4b exit 1"

echo "TEST N: memoized sibling resolution matches both spellings"
# The index registers each sibling under its own `name` AND under the name with
# the plugin prefix stripped, reproducing the pre-memoization match rule. A
# broken index would silently resolve nothing, which reads as STATUS=OK.
fx="$tmp_root/n-plain"; mkdir -p "$fx/demo-plugin/skills/plain-feedback"
{
  printf -- '---\nname: plain-feedback\ndisable-model-invocation: true\n'
  printf 'description: "A thing. Use when doing it."\n---\n\n# /demo:plain-feedback\n'
} > "$fx/demo-plugin/skills/plain-feedback/SKILL.md"
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

Address it via `/demo:plain-feedback` (the canonical engine).
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "N1 unprefixed sibling name still resolves"
assert_contains "$out" "TARGET=demo-plugin/skills/plain-feedback/SKILL.md" "N1b resolves to the right file"
assert_eq "$rc" "1" "N1c exit 1"

echo "TEST O: Class D — a heading is a label, not an instruction (#2483)"
# `document-linking` line 402 is the literal H3 `### /blueprint:work-order`,
# flagged for titling the section that documents that command.
fx="$tmp_root/o-heading"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

### `/demo:feedback`

After the review lands, the thread is resolved.
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=OK" "O1 an H3 naming a gated sibling is clean"
assert_eq "$rc" "0" "O1b exit 0"
assert_eq "$(key_of "$out" FILES_SCANNED)" "FILES_SCANNED=1" "O1c the file was actually read"

# Guard integrity, and the half that matters: a heading exemption must not leak
# into the body underneath it. Without this, skipping the whole file would pass.
fx="$tmp_root/o-body"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

### Handling review threads

Address it via `/demo:feedback` (the canonical engine).
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "O2 body under a heading is still judged"
assert_eq "$rc" "1" "O2b exit 1"

# `#` also opens a shell comment. A heading exemption blind to fenced blocks
# would let a real delegation escape a guard that judged it before Class D
# existed — verified against origin/main, which reports ERROR on this fixture.
fx="$tmp_root/o-fence"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

```bash
# Address it via `/demo:feedback` (the canonical engine)
run_thing
```
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" 'O3 a shell comment inside a fence is still judged'
assert_eq "$rc" "1" "O3b exit 1"

# ...and the fence must CLOSE, or every heading after a code block would be
# judged as a comment and Class D would be dead below the first fence.
fx="$tmp_root/o-postfence"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

```bash
run_thing
```

### `/demo:feedback`

Documented above.
EOF
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=OK" "O4 a heading AFTER a closed fence is still exempt"
assert_eq "$rc" "0" "O4b exit 0"

echo "TEST P: the #2483 residual allowlist suppresses, counts, and expires"
# A declared residual is exempt, itemised, and counted — never silent.
fx="$tmp_root/p-allow"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

Address it via `/demo:feedback` (the canonical engine).
EOF
allow_key='demo-plugin/skills/demo-watch/SKILL.md|/demo:feedback'
out="$(CHECK_DELEGATION_SCOPE="demo-plugin/skills/demo-watch/SKILL.md" \
  CHECK_DELEGATION_ALLOWLIST="$allow_key" bash "$checker" --project-dir "$fx" 2>&1)"; rc=$?
assert_contains "$out" "STATUS=OK" "P1 a declared residual is suppressed"
assert_eq "$rc" "0" "P1b exit 0"
assert_eq "$(key_of "$out" ALLOWLISTED)" "ALLOWLISTED=1" "P1c the suppression is counted"
assert_contains "$out" "TYPE=allowlisted_delegation" "P1d the suppression is itemised"
assert_lacks "$out" "TYPE=unreachable_delegation" "P1e no finding is double-reported"

# Guard integrity: the SAME file with the allowlist withheld must ERROR, or P1
# proves only that the checker stopped judging.
out="$(run_checker "$fx")"; rc=$?
assert_contains "$out" "STATUS=ERROR" "P2 the same reference ERRORs undeclared"
assert_eq "$rc" "1" "P2b exit 1"
assert_eq "$(key_of "$out" ALLOWLISTED)" "ALLOWLISTED=0" "P2c counter is attributable, not always-on"

# The key is `<file>|<ref>`, so a DIFFERENT gated sibling in an already-declared
# file is still caught — the coarseness is bounded to the declared reference.
fx="$tmp_root/p-other"; mk_sibling "$fx" demo-feedback gated
mk_sibling "$fx" demo-issue gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

Address it via `/demo:issue` (the canonical engine).
EOF
out="$(CHECK_DELEGATION_SCOPE="demo-plugin/skills/demo-watch/SKILL.md" \
  CHECK_DELEGATION_ALLOWLIST="$allow_key" bash "$checker" --project-dir "$fx" 2>&1)"; rc=$?
assert_contains "$out" "STATUS=ERROR" "P3 an undeclared ref in a declared file still ERRORs"
assert_contains "$out" "REF=/demo:issue" "P3b names the undeclared reference"
assert_eq "$rc" "1" "P3c exit 1"

# The ratchet: a key matching nothing in scope is itself an ERROR, so the list
# can only shrink. Without this an entry would silently outlive its finding and
# suppress a future one.
fx="$tmp_root/p-stale"; mk_sibling "$fx" demo-feedback gated
mk_watch "$fx" open <<'EOF'
# /demo:watch

## Execution

Nothing to see here.
EOF
out="$(CHECK_DELEGATION_SCOPE="demo-plugin/skills/demo-watch/SKILL.md" \
  CHECK_DELEGATION_ALLOWLIST="$allow_key" bash "$checker" --project-dir "$fx" 2>&1)"; rc=$?
assert_contains "$out" "STATUS=ERROR" "P4 a stale allowlist entry is an ERROR"
assert_contains "$out" "TYPE=stale_allowlist_entry" "P4b names the finding type"
assert_contains "$out" "KEY=$allow_key" "P4c names the stale key"
assert_eq "$rc" "1" "P4d exit 1"

# ...but only for files IN scope. A narrowing seam puts the rest out of view,
# not out of date; without this every fixture run above would drown in stale
# findings for the real repo's declared residuals.
out="$(CHECK_DELEGATION_SCOPE="demo-plugin/skills/demo-watch/SKILL.md" \
  CHECK_DELEGATION_ALLOWLIST="other-plugin/skills/x/SKILL.md|/demo:feedback" \
  bash "$checker" --project-dir "$fx" 2>&1)"; rc=$?
assert_contains "$out" "STATUS=OK" "P5 an out-of-scope key is not judged stale"
assert_eq "$rc" "0" "P5b exit 0"

# The allowlist seam uses `${VAR-default}`, not `${VAR:-default}`, so an
# explicitly EMPTY value means "no declared residuals" and is distinct from an
# unset one (the #2521 lesson). That is the documented way to see the raw
# residual set, so both halves are pinned on ONE fixture — a fixture at a path
# the SHIPPED default declares, since anywhere else the two operators agree and
# the case would pin nothing.
fx="$tmp_root/p-seam"
declared_file="blueprint-plugin/skills/confidence-scoring/SKILL.md"
mkdir -p "$fx/blueprint-plugin/skills/confidence-scoring" \
         "$fx/blueprint-plugin/skills/blueprint-work-order"
{
  printf -- '---\nname: blueprint-work-order\ndisable-model-invocation: true\n'
  printf 'description: "Create a work-order. Use when delegating a task."\n---\n\n'
  printf '# /blueprint:work-order\n'
} > "$fx/blueprint-plugin/skills/blueprint-work-order/SKILL.md"
{
  printf -- '---\nname: confidence-scoring\n'
  printf 'description: "Score a PRP. Use when assessing readiness."\n---\n\n'
  printf '# /blueprint:confidence-scoring\n\n## Execution\n\n'
  printf 'Address it via `/blueprint:work-order` (the canonical engine).\n'
} > "$fx/$declared_file"

# Unset seam: the shipped default is in force, so the declared residual is
# suppressed. This half also proves DELEGATION_ALLOWLIST_DEFAULT is loaded at
# all — without it the empty-seam half below would hold for a default that was
# never read.
out="$(CHECK_DELEGATION_SCOPE="$declared_file" bash "$checker" --project-dir "$fx" 2>&1)"; rc=$?
assert_contains "$out" "STATUS=OK" "P6 the shipped default suppresses its declared residual"
assert_eq "$(key_of "$out" ALLOWLISTED)" "ALLOWLISTED=1" "P6b the shipped default is loaded"
assert_eq "$rc" "0" "P6c exit 0"

# Empty seam: set-but-empty means "declare nothing", so the SAME reference
# ERRORs. Under `${VAR:-default}` this case would be indistinguishable from the
# unset one and would silently pin nothing.
out="$(CHECK_DELEGATION_SCOPE="$declared_file" \
  CHECK_DELEGATION_ALLOWLIST='' bash "$checker" --project-dir "$fx" 2>&1)"; rc=$?
assert_contains "$out" "STATUS=ERROR" "P7 an empty seam declares nothing"
assert_eq "$(key_of "$out" ALLOWLISTED)" "ALLOWLISTED=0" "P7b nothing is suppressed"
assert_lacks "$out" "TYPE=stale_allowlist_entry" "P7c an empty list has no stale keys"
assert_eq "$rc" "1" "P7d exit 1"

echo
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
exit 0
