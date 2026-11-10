#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in patterns are literal markdown, not expansions
# test-health-agentic-audit-skill.sh — semantic guard for the health-agentic-audit
# skill text (SKILL.md + REFERENCE.md).
#
# The skill used to enforce a standard that .claude/rules/context-engineering.md
# § Supersedes demoted: it flagged every skill with a bash block but no
# "Agentic Optimizations" table, and --fix inserted skeleton tables with TODO
# rows, adding tokens the house rule says to cut. It also listed one `find`
# twice in Context, and judged staleness from `modified` instead of `reviewed`.
#
# Invariants (each check FAILS on the pre-fix text):
#   C1 no_skeleton_insertion   neither file tells the agent to insert a skeleton
#                              table or TODO placeholder rows
#   C2 table_is_info_only      no "Missing Agentic Optimizations" finding or
#                              report section; the table check is an INFO note
#                              scoped to CLI-wrapper skills; --fix never inserts
#   C3 staleness_reads_reviewed the frontmatter extraction reads `reviewed:`,
#                              never `modified:`, and the stale table says so
#   C4 single_skill_find       Context lists the SKILL.md `find` exactly once
#   C5 bare_cli_still_a_finding the bare-CLI step and the pattern table survive
#   C6 fix_step_resolvable     the step health-check's --fix delegation cites
#                              exists and is the --fix step
#   C7 description_triggers    description keeps "Use when", is <= 200 chars,
#                              and no longer advertises optimization tables
#   C8 fix_preserves_reviewed  --fix leaves `reviewed` unchanged
#
# A mutation self-test then re-breaks each invariant on a sandbox copy and
# asserts the matching check fails, so a check that can never fire is caught.
#
# Usage:
#   bash test-health-agentic-audit-skill.sh [--skill-dir DIR] [--health-check FILE]
# --skill-dir points the checks (not the self-test) at another copy of the
# skill, e.g. one extracted with `git show HEAD:...`, to prove they fire on it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
skill_dir="${PLUGIN_DIR}/skills/health-agentic-audit"
health_check="${PLUGIN_DIR}/skills/health-check/SKILL.md"
skip_selftest=false

while [ $# -gt 0 ]; do
  case "$1" in
    --skill-dir) skill_dir="$2"; skip_selftest=true; shift 2 ;;
    --health-check) health_check="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

passed=0
failed=0
pass() { echo "PASS: $1"; passed=$((passed + 1)); }
fail() { printf 'FAIL: %b\n' "$1"; failed=$((failed + 1)); }

# ---------------------------------------------------------------------------
# Checks. Each takes a skill directory, prints a reason on failure, returns 1.
# ---------------------------------------------------------------------------

description_of() {
  # First `description:` line inside the frontmatter, surrounding quotes removed.
  awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {exit} fm && /^description:/ {print; exit}' "$1" \
    | sed -e 's/^description:[[:space:]]*//' -e 's/^"//' -e 's/"$//'
}

check_c1() {
  local d="$1" hits
  # Case-sensitive TODO, so the `TodoWrite` tool grant does not match.
  hits="$(grep -n -E '[Ss]keleton|TODO' "$d/SKILL.md" "$d/REFERENCE.md")"
  [ -z "$hits" ] || { echo "skeleton/TODO insertion text present:"; echo "$hits"; return 1; }
}

check_c2() {
  local d="$1" hits skill
  hits="$(grep -n -E 'Missing Agentic Optimizations|lack the Agentic Optimizations' "$d/SKILL.md" "$d/REFERENCE.md")"
  [ -z "$hits" ] || { echo "missing table is still reported as a finding:"; echo "$hits"; return 1; }
  skill="$(<"$d/SKILL.md")"
  grep -q -E '(INFO.*CLI-wrapper.*Agentic Optimizations|CLI-wrapper.*Agentic Optimizations.*INFO|Agentic Optimizations.*CLI-wrapper.*INFO)' <<<"$skill" \
    || { echo "no line scopes the table check to CLI-wrapper skills as INFO"; return 1; }
  grep -q -i 'never inserts' <<<"$skill" \
    || { echo "SKILL.md no longer states that --fix never inserts tables"; return 1; }
}

check_c3() {
  local d="$1" hits ref
  hits="$(grep -n -E '"\^modified:"|modified`? (date )?(is )?older than|Last Modified' "$d/SKILL.md" "$d/REFERENCE.md")"
  [ -z "$hits" ] || { echo "staleness still derived from modified:"; echo "$hits"; return 1; }
  ref="$(<"$d/REFERENCE.md")"
  grep -q -E 'grep -m1 "\^reviewed:"' <<<"$ref" \
    || { echo "REFERENCE.md frontmatter extraction does not read reviewed:"; return 1; }
  grep -q 'Last Reviewed' <<<"$ref" \
    || { echo "stale-review report table does not show the reviewed date"; return 1; }
}

check_c4() {
  local d="$1" count
  count="$(grep -c -E '^- .*!`find .*SKILL\.md' "$d/SKILL.md")"
  [ "$count" = "1" ] || { echo "Context lists the SKILL.md find $count times (want 1)"; return 1; }
}

check_c5() {
  local d="$1" rows skill ref
  skill="$(<"$d/SKILL.md")"
  grep -q -E '^### Step [0-9]+: .*[Bb]are CLI' <<<"$skill" \
    || { echo "SKILL.md has no bare-CLI scan step"; return 1; }
  ref="$(<"$d/REFERENCE.md")"
  grep -q '^## Bare CLI Command Patterns' <<<"$ref" \
    || { echo "REFERENCE.md lost the Bare CLI Command Patterns table"; return 1; }
  rows="$(awk '/^## Bare CLI Command Patterns/{t=1; next} t && /^## /{exit} t && /^\| `/{n++} END{print n+0}' "$d/REFERENCE.md")"
  [ "$rows" -ge 10 ] || { echo "Bare CLI Command Patterns has $rows pattern rows (want >= 10)"; return 1; }
}

check_c6() {
  local d="$1" hc step skill
  [ -f "$health_check" ] || { echo "health-check SKILL.md not found at $health_check"; return 1; }
  hc="$(<"$health_check")"
  # The delegation row invokes the skill with --fix and names the step it runs
  # (health-check loads it through the Skill tool, not by reading its SKILL.md).
  step="$(grep -E 'health-agentic-audit`?[^|]*--fix[^|]*Step [0-9]+' <<<"$hc" | grep -o -E 'Step [0-9]+' | head -n1)"
  [ -n "$step" ] || { echo "health-check no longer cites a health-agentic-audit step"; return 1; }
  skill="$(<"$d/SKILL.md")"
  grep -q -E "^### ${step}: .*--fix" <<<"$skill" \
    || { echo "health-check delegates --fix to '$step', but SKILL.md has no '### $step: ... --fix' heading"; return 1; }
  grep -q -E '^args: .*--fix' <<<"$skill" || { echo "args no longer declares --fix"; return 1; }
}

check_c7() {
  local d="$1" desc len
  desc="$(description_of "$d/SKILL.md")"
  [ -n "$desc" ] || { echo "no description in frontmatter"; return 1; }
  grep -q 'Use when' <<<"$desc" || { echo "description lacks 'Use when': $desc"; return 1; }
  len="${#desc}"
  [ "$len" -le 200 ] || { echo "description is $len chars (max 200)"; return 1; }
  if grep -q -i 'optimization tables' <<<"$desc"; then
    echo "description still advertises optimization tables: $desc"; return 1
  fi
}

check_c8() {
  local d="$1" skill
  skill="$(<"$d/SKILL.md")"
  grep -q -E 'Leave `reviewed` unchanged' <<<"$skill" \
    || { echo "--fix step does not keep reviewed unchanged"; return 1; }
}

checks=(c1 c2 c3 c4 c5 c6 c7 c8)
declare -A check_name=(
  [c1]=no_skeleton_insertion [c2]=table_is_info_only [c3]=staleness_reads_reviewed
  [c4]=single_skill_find [c5]=bare_cli_still_a_finding [c6]=fix_step_resolvable
  [c7]=description_triggers [c8]=fix_preserves_reviewed
)

for f in SKILL.md REFERENCE.md; do
  [ -f "$skill_dir/$f" ] || { echo "FAIL: $skill_dir/$f not found"; exit 1; }
done

echo "=== CHECKS: $skill_dir ==="
for c in "${checks[@]}"; do
  if out="$("check_$c" "$skill_dir")"; then
    pass "${check_name[$c]}"
  else
    fail "${check_name[$c]}: $out"
  fi
done

# ---------------------------------------------------------------------------
# Mutation self-test: re-break each invariant on a sandbox copy of the real
# skill and assert the matching check fails.
# ---------------------------------------------------------------------------

if [ "$skip_selftest" = false ]; then
  tmp_root="$(mktemp -d 2>/dev/null)"
  if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
    echo "FAIL: mktemp -d failed"; exit 1
  fi
  trap 'rm -rf "$tmp_root"' EXIT

  fresh_copy() {
    local m="$tmp_root/$1"
    rm -rf "$m"; mkdir -p "$m"
    cp "$skill_dir/SKILL.md" "$skill_dir/REFERENCE.md" "$m/"
    printf '%s' "$m"
  }
  # rewrite FILE with a sed program (no in-place edit, so BSD and GNU agree)
  rewrite() { sed -e "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }

  echo "=== MUTATION SELF-TEST ==="
  for c in "${checks[@]}"; do
    m="$(fresh_copy "$c")"
    case "$c" in
      c1) echo '1. Add skeleton Agentic Optimizations tables. Leave TODO entries.' >> "$m/SKILL.md" ;;
      c2) printf '\n### Missing Agentic Optimizations Tables\n' >> "$m/REFERENCE.md" ;;
      c3) rewrite "$m/REFERENCE.md" 's/"^reviewed:"/"^modified:"/' ;;
      c4) rewrite "$m/SKILL.md" '/^- Skill files: /p' ;;
      c5) rewrite "$m/REFERENCE.md" '/^## Bare CLI Command Patterns/d' ;;
      c6) rewrite "$m/SKILL.md" 's/^### Step 6: /### Step 7: /' ;;
      c7) rewrite "$m/SKILL.md" '/^description:/s/Use when/Use to/' ;;
      c8) rewrite "$m/SKILL.md" 's/Leave `reviewed` unchanged/Update `reviewed`/' ;;
    esac
    if "check_$c" "$m" >/dev/null; then
      fail "self-test: ${check_name[$c]} did not fire on its mutation"
    else
      pass "self-test: ${check_name[$c]} fires on its mutation"
    fi
  done
fi

echo "=== SUMMARY ==="
echo "PASSED=$passed"
echo "FAILED=$failed"
[ "$failed" -eq 0 ] || exit 1
echo "ALL PASS"
