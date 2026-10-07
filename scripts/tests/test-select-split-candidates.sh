#!/usr/bin/env bash
# shellcheck disable=SC2016  # regex patterns match literal `$SELECT`/`$PLUGIN` text in the workflow, never expansions
# Regression test for scripts/select-split-candidates.sh and the
# skill-splitter workflow that uses it.
#
# The bug: `.github/workflows/skill-splitter.yml` picked split candidates by
# `wc -l` (PR mode: changed SKILL.md sorted by lines; `all` mode: >300 lines and
# no REFERENCE.md), while the size gate, check_skill_size() in
# scripts/plugin-compliance-check.sh, measures decoded UTF-8 characters and
# warns above 10000 (.claude/rules/skill-quality.md "Size Limits", #2135). So
# the splitter processed a different set from the one the gate warns about, and
# 37 skills with a REFERENCE.md that were still over the gate were never
# selected. Separately, a dispatch run committed on the dispatched ref (main)
# and the model ran `git push origin HEAD`, landing splits directly on main.
#
# A third incident (#2935): the workflow's `pull_request` trigger re-split
# every changed SKILL.md over the gate on each branch update and pushed the
# `refactor(split):` commits to the PR's own head ref. Five PRs received
# unreviewed splits of skills deliberately left over the threshold; six were
# merged unverified and one broke scripts/tests/test-lint-mcp-tool-references.sh
# on main (reverted in #2936). The workflow is now dispatch-only.
#
# THE SEMANTIC INVARIANT: the splitter selects exactly the skills the gate
# warns about, by the gate's own metric and threshold; it runs only on
# dispatch; and it publishes to its own review branch, never to the dispatched
# ref or to another PR's branch.
#
# Guards:
#   A. a dense 40-line skill over 10000 chars IS selected (a >300-line rule misses it)
#   B. a sparse 400-line skill under 10000 chars is NOT selected (a >300-line rule picks it)
#   C. a skill over 10000 chars that already has a REFERENCE.md IS selected
#   D. multibyte text: >10000 BYTES but <=10000 CHARACTERS is NOT selected
#   E. the boundary matches the gate's `-gt`: 10000 chars no, 10001 yes
#   F. a lowercase skill.md is counted (the gate uses -iname)
#   G. --all covers only `*-plugin/skills/**`, as the gate does (.claude/skills excluded)
#   H. output is largest first; --limit truncates after sorting
#   I. --plugin scopes to one plugin
#   J. --stdin skips deleted (nonexistent) paths and empty input, exit 0
#   K. the threshold is read from the gate: --print-threshold equals the real
#      gate's SKILL_SIZE_WARN_CHARS, check_skill_size() compares against that
#      variable, and a gate with the assignment removed makes the selector exit 2
#   L. the workflow selects via the script in every scope and no longer by lines
#   M. the prompt no longer skips skills that have a REFERENCE.md and asks for
#      a references/ split
#   N. Claude cannot push or switch branches; a deterministic step pushes to
#      refactor/skill-split-<run_id> and a separate job opens a PR, never bare HEAD
#   O. dispatch-only (#2935): workflow_dispatch is the sole trigger, no
#      pull_request/pull_request_target trigger, no PR head ref is read, and
#      every `git push` targets the split branch
#
# SKILL_SPLITTER_WORKFLOW overrides the workflow under test, so L-O can be
# shown red against a pre-fix file.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
selector="$repo_root/scripts/select-split-candidates.sh"
gate="$repo_root/scripts/plugin-compliance-check.sh"
workflow="${SKILL_SPLITTER_WORKFLOW:-$repo_root/.github/workflows/skill-splitter.yml}"

tmp="$(mktemp -d)"
[ -n "$tmp" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
assert_eq() {
  # assert_eq <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "  PASS: $1"; pass=$((pass + 1))
  else
    echo "  FAIL: $1"; echo "    expected: $3"; echo "    actual:   $2"; fail=$((fail + 1))
  fi
}
assert_grep() {
  # assert_grep <description> <file> <ERE>
  if grep -qE -- "$3" "$2"; then
    echo "  PASS: $1"; pass=$((pass + 1))
  else
    echo "  FAIL: $1"; echo "    expected to match: $3"; fail=$((fail + 1))
  fi
}
assert_no_grep() {
  # assert_no_grep <description> <file> <ERE>
  if grep -qE -- "$3" "$2"; then
    echo "  FAIL: $1"; echo "    expected NOT to match: $3"
    grep -nE -- "$3" "$2" | head -3 | sed 's/^/      /'
    fail=$((fail + 1))
  else
    echo "  PASS: $1"; pass=$((pass + 1))
  fi
}

# write_skill <path> <chars> <lines> [<fill-char>]
# Writes exactly <chars> decoded characters over <lines> lines.
write_skill() {
  mkdir -p "$(dirname "$1")"
  python3 - "$1" "$2" "$3" "${4:-x}" <<'PY'
import sys
path, chars, lines, ch = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
body_chars = chars - lines            # one newline per line
per, extra = divmod(body_chars, lines)
text = "".join(ch * (per + (1 if i < extra else 0)) + "\n" for i in range(lines))
assert len(text) == chars, (len(text), chars)
open(path, "w", encoding="utf-8").write(text)
PY
}

# ---------------------------------------------------------------- sandbox root
root="$tmp/root"
mkdir -p "$root/scripts"
cp "$selector" "$root/scripts/"
cp "$gate" "$root/scripts/"

write_skill "$root/a-plugin/skills/dense/SKILL.md" 12000 40
write_skill "$root/a-plugin/skills/sparse/SKILL.md" 4000 400
write_skill "$root/a-plugin/skills/has-ref/SKILL.md" 15000 30
echo "# ref" > "$root/a-plugin/skills/has-ref/REFERENCE.md"
write_skill "$root/a-plugin/skills/exact/SKILL.md" 10000 50
write_skill "$root/b-plugin/skills/over-by-one/SKILL.md" 10001 50
write_skill "$root/b-plugin/skills/multibyte/SKILL.md" 4000 20 "—"
write_skill "$root/b-plugin/skills/lowercase/skill.md" 11000 20
write_skill "$root/.claude/skills/local/SKILL.md" 20000 20

run_sel() { (cd "$root" && bash scripts/select-split-candidates.sh "$@" 2>/dev/null); }

echo "=== select-split-candidates.sh ==="

# D precondition: the multibyte fixture really is over 10000 bytes.
bytes=$(wc -c < "$root/b-plugin/skills/multibyte/SKILL.md" | tr -d ' ')
if [ "$bytes" -gt 10000 ]; then
  echo "  PASS: D precondition — multibyte fixture is $bytes bytes"; pass=$((pass + 1))
else
  echo "  FAIL: D precondition — multibyte fixture only $bytes bytes"; fail=$((fail + 1))
fi

all_out=$(run_sel --all)
expected_all=$(printf '%s\n' \
  a-plugin/skills/has-ref/SKILL.md \
  a-plugin/skills/dense/SKILL.md \
  b-plugin/skills/lowercase/skill.md \
  b-plugin/skills/over-by-one/SKILL.md)
assert_eq "A-H. --all selects exactly the over-gate plugin skills, largest first" "$all_out" "$expected_all"

assert_eq "H. --limit 2 keeps the two largest" "$(run_sel --all --limit 2)" \
  "$(printf '%s\n' a-plugin/skills/has-ref/SKILL.md a-plugin/skills/dense/SKILL.md)"

assert_eq "I. --plugin b-plugin scopes to that plugin" "$(run_sel --plugin b-plugin)" \
  "$(printf '%s\n' b-plugin/skills/lowercase/skill.md b-plugin/skills/over-by-one/SKILL.md)"

stdin_out=$(printf '%s\n' a-plugin/skills/sparse/SKILL.md a-plugin/skills/dense/SKILL.md \
  a-plugin/skills/deleted/SKILL.md "" | (cd "$root" && bash scripts/select-split-candidates.sh --stdin 2>/dev/null))
assert_eq "J. --stdin keeps over-gate paths and skips a deleted one" "$stdin_out" "a-plugin/skills/dense/SKILL.md"

empty_out=$(cd "$root" && bash scripts/select-split-candidates.sh --stdin </dev/null 2>/dev/null); rc=$?
assert_eq "J. empty --stdin exits 0" "$rc" "0"
assert_eq "J. empty --stdin prints nothing" "$empty_out" ""

real_threshold=$(sed -n 's/^SKILL_SIZE_WARN_CHARS=\([0-9][0-9]*\)$/\1/p' "$gate")
assert_eq "K. --print-threshold equals the gate's SKILL_SIZE_WARN_CHARS" \
  "$(bash "$selector" --print-threshold 2>/dev/null)" "$real_threshold"
assert_eq "K. the gate's warn threshold is still 10000 (update the fixtures if it moves)" "$real_threshold" "10000"

size_fn="$tmp/check_skill_size.txt"
sed -n '/^check_skill_size() {/,/^}/p' "$gate" > "$size_fn"
assert_grep "K. check_skill_size() compares against SKILL_SIZE_WARN_CHARS" "$size_fn" '-gt "\$SKILL_SIZE_WARN_CHARS"'
assert_no_grep "K. check_skill_size() hard-codes no numeric threshold" "$size_fn" '-gt [0-9]'

grep -v '^SKILL_SIZE_WARN_CHARS=' "$gate" > "$root/scripts/plugin-compliance-check.sh"
missing_err=$(cd "$root" && bash scripts/select-split-candidates.sh --all 2>&1 >/dev/null); rc=$?
assert_eq "K. a gate without the assignment makes the selector exit 2" "$rc" "2"
assert_eq "K. ...and says why" "$(grep -c 'SKILL_SIZE_WARN_CHARS' <<<"$missing_err")" "1"
cp "$gate" "$root/scripts/"

echo "=== skill-splitter workflow ($(basename "$workflow")) ==="
allowed="$tmp/allowed.txt"
grep -E '^[[:space:]]*--allowedTools ' "$workflow" > "$allowed" || true
# Comment lines explain the old behaviour by name; assert on code and prompt only.
code="$tmp/workflow-no-comments.yml"
grep -vE '^[[:space:]]*#' "$workflow" > "$code" || true

assert_grep "L. plugin mode selects via the script" "$workflow" '"\$SELECT" --plugin "\$PLUGIN"'
assert_grep "L. all mode selects via the script" "$workflow" '"\$SELECT" --all'
assert_grep "L. SELECT names scripts/select-split-candidates.sh" "$workflow" '^[[:space:]]*SELECT=scripts/select-split-candidates\.sh$'
assert_no_grep "L. no line-count selection remains" "$code" 'wc -l|line_count'
assert_no_grep "M. the prompt no longer skips a skill with a REFERENCE.md" "$code" 'REFERENCE\.md already exists'
assert_grep "M. the prompt asks for a references/ split" "$workflow" 'references/<topic>\.md'
assert_grep "N. the Claude step declares an --allowedTools list" "$allowed" 'allowedTools'
assert_no_grep "N. Claude is not granted git push" "$allowed" 'Bash\(git push'
assert_no_grep "N. Claude is not granted git checkout" "$allowed" 'Bash\(git checkout'
assert_no_grep "N. nothing pushes bare HEAD (the dispatched ref)" "$code" 'git push origin HEAD([[:space:]]|`|$)'
assert_grep "N. dispatch runs commit on a refactor/skill-split-<run_id> branch" "$workflow" 'SPLIT_BRANCH: refactor/skill-split-\$\{\{ github\.run_id \}\}'
assert_grep "N. the publish step pushes the split branch by refspec" "$workflow" 'git push origin "HEAD:refs/heads/\$\{SPLIT_BRANCH\}"'
assert_grep "N. dispatch runs open a PR" "$workflow" 'gh pr create'
assert_grep "O. workflow_dispatch is a trigger" "$code" '^[[:space:]]*workflow_dispatch:'
assert_no_grep "O. no pull_request or pull_request_target trigger" "$code" '^[[:space:]]*pull_request(_target)?:'
assert_no_grep "O. no other trigger besides workflow_dispatch" "$code" \
  '^[[:space:]]{2}(push|schedule|workflow_run|workflow_call|issue_comment|pull_request_review(_comment)?|repository_dispatch):'
assert_no_grep "O. no step reads a PR head ref or head SHA" "$code" \
  'github\.head_ref|pull_request\.head\.|HEAD_REF'
assert_no_grep "O. no logic branches on a pull_request event" "$code" "event_name == 'pull_request'|= \"pull_request\""
push_lines=$(grep -E 'git push' "$code" || true)
push_count=$(grep -c . <<<"$push_lines" || true)
split_push_count=$(grep -cE 'git push origin "HEAD:refs/heads/\$\{SPLIT_BRANCH\}"' <<<"$push_lines" || true)
assert_eq "O. the workflow has exactly one git push" "$push_count" "1"
assert_eq "O. ...and it pushes the split branch" "$split_push_count" "1"

echo
echo "PASSED=$pass FAILED=$fail"
[ "$fail" -eq 0 ]
