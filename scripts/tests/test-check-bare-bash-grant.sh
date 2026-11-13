#!/usr/bin/env bash
# shellcheck disable=SC2016   # file-level: fixture frontmatter holds literal
#                             # ${CLAUDE_SKILL_DIR} and must NOT expand. Must
#                             # precede the first command.
# Regression test for scripts/check-bare-bash-grant.sh (#3464).
#
# SEMANTIC, not syntactic: every case EXECUTES the lint against a planted
# fixture tree and reads its structured output; nothing greps the script for its
# own rules. Each "not a hit" case is paired with a positive control that proves
# the lint parsed the same fixture, so a lint that silently parsed nothing fails
# here rather than passing every negative.

set -uo pipefail

# Neutralise inherited git context (#1745); the lint never needs git, but a
# leaked GIT_DIR must not reach anything this suite runs.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
CHECK="$repo_root/scripts/check-bare-bash-grant.sh"
CONTRACT="$repo_root/scripts/check-structured-output-contract.sh"

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
is() { [ "$1" = "$2" ] && echo true || echo false; }

# make_skill <root> <plugin/skills/name> <frontmatter allowed-tools block>
# The third argument is written verbatim after `description:`, so a case can
# plant either the one-line or the YAML-list form.
make_skill() {
  local root="$1" rel="$2" at_block="$3"
  mkdir -p "$root/$rel"
  {
    printf -- '---\n'
    printf -- 'name: %s\n' "$(basename "$rel")"
    printf -- 'description: Fixture skill. Use when testing.\n'
    printf -- '%s\n' "$at_block"
    printf -- '---\n\n# Fixture\n\nThe body mentions Bash and `git status`.\n'
  } > "$root/$rel/SKILL.md"
}

OUT=""; RC=0
run_check() {
  local root="$1"; shift
  OUT="$(bash "$CHECK" --project-dir "$root" "$@" 2>/dev/null)"
  RC=$?
}
field() { grep -m1 "^$1=" <<<"$OUT" | cut -d= -f2-; }
listed() {  # listed <skill-substring> <type> -> true when --list has that row
  grep -qE "^[^[:space:]]*$1/SKILL\.md	$2\$" <<<"$OUT" && echo true || echo false
}
validates() { printf '%s\n' "$1" | bash "$CONTRACT" --validate - >/dev/null 2>&1 && echo true || echo false; }

sandbox=$(mktemp -d) || exit 1
[ -n "$sandbox" ] || exit 1
trap 'rm -rf "$sandbox"' EXIT

##########
# A. Empty corpus -> OK, exit 0
##########
echo "=== A: empty corpus ==="
empty="$sandbox/empty"; mkdir -p "$empty"
run_check "$empty" --baseline "$sandbox/none.txt"
assert "A1 empty corpus STATUS=OK" "$(is "$(field STATUS)" OK)"
assert "A2 empty corpus SCANNED_EMPTY=true" "$(is "$(field SCANNED_EMPTY)" true)"
assert "A3 empty corpus exits 0" "$(is "$RC" 0)"
assert "A4 OK output satisfies the contract" "$(validates "$OUT")"

##########
# B. Unknown argument -> exit 2, usage on stderr, nothing on stdout (#2057)
##########
echo "=== B: unknown argument ==="
b_out="$(bash "$CHECK" --project-dir "$empty" --bogus-flag 2>/dev/null)"; b_rc=$?
b_err="$(bash "$CHECK" --project-dir "$empty" --bogus-flag 2>&1 >/dev/null)"
assert "B1 unknown arg exits 2" "$(is "$b_rc" 2)"
assert "B2 unknown arg prints nothing to stdout" "$(is "$b_out" "")"
assert "B3 unknown arg names the flag on stderr" "$(grep -q 'bogus-flag' <<<"$b_err" && echo true || echo false)"
bash "$CHECK" --project-dir "$empty" --plugin "$sandbox/no-such-plugin" >/dev/null 2>&1; b4=$?
assert "B4 --plugin naming a missing directory exits 2" "$(is "$b4" 2)"

##########
# C. Parse matrix, read through --list
##########
c="$sandbox/c"
make_skill "$c" "x-plugin/skills/one-line-bare"   'allowed-tools: Bash, Read, Grep'
make_skill "$c" "x-plugin/skills/yaml-list-bare"  'allowed-tools:
  - Read
  - Bash
  - Grep'
make_skill "$c" "x-plugin/skills/quoted-bare"     'allowed-tools: "Read, Bash"'
make_skill "$c" "x-plugin/skills/flow-list-bare"  'allowed-tools: [Read, Bash]'
make_skill "$c" "x-plugin/skills/narrow"          'allowed-tools: Bash(git status *), Bash(gh pr view *), Read'
# A naive comma split turns this one grant into the tokens `Bash(jq -r .a`,
# `Bash` and `.b *)`, so it would read as a bare grant (mutation-checked).
make_skill "$c" "x-plugin/skills/comma-in-parens" 'allowed-tools: Bash(jq -r .a,Bash,.b *), Read'
make_skill "$c" "x-plugin/skills/anchored"        'allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/x.sh *), Read'
make_skill "$c" "x-plugin/skills/broad-bash"      'allowed-tools: Bash(bash *), Read'
make_skill "$c" "x-plugin/skills/broad-python3"   'allowed-tools: Bash(python3 *), Bash(jq *)'
make_skill "$c" "x-plugin/skills/broad-star"      'allowed-tools: Bash(*)'
make_skill "$c" "x-plugin/skills/broad-colon"     'allowed-tools: Bash(node:*)'
make_skill "$c" "x-plugin/skills/broad-list"      'allowed-tools:
  - Bash(sh *)'
make_skill "$c" "x-plugin/skills/bashoutput"      'allowed-tools: BashOutput, Read'
make_skill "$c" "x-plugin/skills/no-grant"        'allowed-tools: Read, Grep'
make_skill "$c" "x-plugin/skills/both"            'allowed-tools: Bash, Bash(zsh *)'
# A second plugin, used by the --plugin cases below.
make_skill "$c" "y-plugin/skills/clean"           'allowed-tools: Bash(jq *), Read'
make_skill "$c" "y-plugin/skills/dirty"           'allowed-tools: Read, Bash'

echo "=== C: parse matrix ==="
run_check "$c" --list
assert "C0 --list prints no structured section" "$(grep -q '^===' <<<"$OUT" && echo false || echo true)"
assert "C0b --list rows are exactly path<TAB>type" \
  "$(grep -vqE '^[^[:space:]]+	(bare_bash|broad_shell_grant)$' <<<"$OUT" && echo false || echo true)"
assert "C1 one-line bare Bash is a hit"      "$(listed one-line-bare bare_bash)"
assert "C2 YAML-list bare Bash is a hit"     "$(listed yaml-list-bare bare_bash)"
assert "C3 quoted one-line bare Bash is a hit" "$(listed quoted-bare bare_bash)"
assert "C4 flow-list bare Bash is a hit"     "$(listed flow-list-bare bare_bash)"
assert "C5 narrow Bash(...) grants are not hits" "$(grep -q 'skills/narrow/' <<<"$OUT" && echo false || echo true)"
assert "C6 a comma inside Bash(...) does not split out a bare Bash" "$(grep -q 'comma-in-parens' <<<"$OUT" && echo false || echo true)"
assert "C7 an anchored bundled-script grant is not broad" "$(grep -q 'skills/anchored/' <<<"$OUT" && echo false || echo true)"
assert "C8 Bash(bash *) is broad"            "$(listed broad-bash broad_shell_grant)"
assert "C9 Bash(python3 *) is broad"         "$(listed broad-python3 broad_shell_grant)"
assert "C10 Bash(*) is broad"                "$(listed broad-star broad_shell_grant)"
assert "C11 the colon form Bash(node:*) is broad" "$(listed broad-colon broad_shell_grant)"
assert "C12 a YAML-list broad grant is a hit" "$(listed broad-list broad_shell_grant)"
assert "C13 BashOutput is not a bare Bash"   "$(grep -q 'bashoutput' <<<"$OUT" && echo false || echo true)"
assert "C14 a skill with no Bash grant is not listed" "$(grep -q 'no-grant' <<<"$OUT" && echo false || echo true)"
assert "C15 one skill can carry both types"  "$( [ "$(listed both bare_bash)" = true ] && [ "$(listed both broad_shell_grant)" = true ] && echo true || echo false)"
assert "C16 exactly 12 rows (positive control on the whole matrix)" "$(is "$(grep -c . <<<"$OUT")" 12)"

##########
# D. Baseline ratchet
##########
echo "=== D: baseline ratchet ==="
bl="$sandbox/baseline.txt"
run_check "$c" --baseline "$bl" --update-baseline
assert "D1 --update-baseline seeds a missing baseline" "$( [ -f "$bl" ] && echo true || echo false)"
assert "D2 the seeded baseline holds every hit" "$(is "$(grep -vc '^#' "$bl")" 12)"
run_check "$c" --baseline "$bl"
assert "D3 baseline-held hits are STATUS=WARN" "$(is "$(field STATUS)" WARN)"
assert "D4 baseline-held hits exit 0" "$(is "$RC" 0)"
assert "D5 held hits are reported as WARN rows of their own type" \
  "$(grep -q 'SEVERITY=WARN TYPE=bare_bash SKILL=x-plugin/skills/one-line-bare/SKILL.md' <<<"$OUT" && echo true || echo false)"
assert "D6 WARN output satisfies the contract" "$(validates "$OUT")"

# A new bare grant is ERROR new_hit, exit 1, while the held ones stay WARN.
make_skill "$c" "x-plugin/skills/brand-new" 'allowed-tools: Read, Bash'
run_check "$c" --baseline "$bl"
assert "D7 a hit outside the baseline is STATUS=ERROR" "$(is "$(field STATUS)" ERROR)"
assert "D8 a hit outside the baseline exits 1" "$(is "$RC" 1)"
assert "D9 the new hit is TYPE=new_hit naming the skill" \
  "$(grep -q 'SEVERITY=ERROR TYPE=new_hit SKILL=x-plugin/skills/brand-new/SKILL.md HIT_TYPE=bare_bash' <<<"$OUT" && echo true || echo false)"
assert "D10 REASON names new_hit" "$(grep -q '^REASON=new_hit: ' <<<"$OUT" && echo true || echo false)"
assert "D11 mixed ERROR+WARN output satisfies the contract" "$(validates "$OUT")"
# --update-baseline never raises an entry: the new hit is still new afterwards.
run_check "$c" --baseline "$bl" --update-baseline
run_check "$c" --baseline "$bl"
assert "D12 --update-baseline does not absorb a new hit" "$(is "$(field STATUS)" ERROR)"
rm -rf "$c/x-plugin/skills/brand-new"

# A fixed skill leaves a stale entry: ERROR stale_baseline until lowered.
make_skill "$c" "x-plugin/skills/one-line-bare" 'allowed-tools: Bash(git status *), Read'
run_check "$c" --baseline "$bl"
assert "D13 a baseline entry with no hit is STATUS=ERROR" "$(is "$(field STATUS)" ERROR)"
assert "D14 ... of TYPE=stale_baseline" \
  "$(grep -q 'SEVERITY=ERROR TYPE=stale_baseline SKILL=x-plugin/skills/one-line-bare/SKILL.md' <<<"$OUT" && echo true || echo false)"
assert "D15 ... and exits 1" "$(is "$RC" 1)"
run_check "$c" --baseline "$bl" --update-baseline
assert "D16 --update-baseline lowers the stale entry away" "$(is "$(grep -vc '^#' "$bl")" 11)"
run_check "$c" --baseline "$bl"
assert "D17 after lowering, the run is back to WARN" "$(is "$(field STATUS)" WARN)"
assert "D18 ... and exits 0" "$(is "$RC" 0)"

##########
# E. --plugin: scoped, baseline ignored, every hit fails
##########
echo "=== E: --plugin ==="
run_check "$c" --baseline "$bl" --plugin y-plugin
assert "E1 --plugin reports a baseline-held hit anyway (ERROR)" "$(is "$(field STATUS)" ERROR)"
assert "E2 --plugin with a hit exits 1" "$(is "$RC" 1)"
assert "E3 --plugin scans only that plugin" "$(is "$(field SKILLS_SCANNED)" 2)"
assert "E4 --plugin names the dirty skill" \
  "$(grep -q 'SEVERITY=ERROR TYPE=bare_bash SKILL=y-plugin/skills/dirty/SKILL.md' <<<"$OUT" && echo true || echo false)"
assert "E5 --plugin never reports another plugin" "$(grep -q 'x-plugin' <<<"$OUT" && echo false || echo true)"
assert "E6 --plugin ERROR output satisfies the contract" "$(validates "$OUT")"
make_skill "$c" "y-plugin/skills/dirty" 'allowed-tools: Read, Bash(jq *)'
run_check "$c" --baseline "$bl" --plugin y-plugin
assert "E7 --plugin on a clean plugin is STATUS=OK" "$(is "$(field STATUS)" OK)"
assert "E8 --plugin on a clean plugin exits 0" "$(is "$RC" 0)"
assert "E9 --plugin does not touch the baseline file" "$(is "$(grep -vc '^#' "$bl")" 11)"
run_check "$c" --plugin y-plugin --plugin x-plugin --list
assert "E10 --plugin is repeatable" "$(grep -q 'x-plugin/skills/broad-star' <<<"$OUT" && echo true || echo false)"
run_check "$c" --plugin ./x-plugin/ --list
assert "E11 --plugin accepts ./dir/ spellings" "$(grep -q 'x-plugin/skills/broad-star' <<<"$OUT" && echo true || echo false)"

##########
# F. Zero-scan is not a clean bill (#2219)
##########
echo "=== F: zero scan ==="
z="$sandbox/z"; mkdir -p "$z/q-plugin/agents"
run_check "$z" --baseline "$sandbox/none.txt"
assert "F1 plugin dirs with no skills is STATUS=ERROR" "$(is "$(field STATUS)" ERROR)"
assert "F2 ... TYPE=nothing_scanned" "$(grep -q 'TYPE=nothing_scanned' <<<"$OUT" && echo true || echo false)"
assert "F3 ... exits 1" "$(is "$RC" 1)"
assert "F4 nothing_scanned output satisfies the contract" "$(validates "$OUT")"
# The project root is itself an agent worktree: discovery must still see it.
wt="$sandbox/repo/.claude/worktrees/agent-x"
make_skill "$wt" "x-plugin/skills/inside-worktree" 'allowed-tools: Bash'
run_check "$wt" --list
assert "F5 a project root under .claude/worktrees/ is still scanned" "$(listed inside-worktree bare_bash)"

##########
# G. A trailing YAML comment does not hide a grant (#3464 F2)
##########
# Without the comment strip, the tokens read `Bash # note` and `Bash  # full
# shell`, which classify() does not flag, so a new bare Bash passes the ratchet.
echo "=== G: trailing comments ==="
g="$sandbox/g"
make_skill "$g" "x-plugin/skills/comment-one-line" 'allowed-tools: Read, Bash # note'
make_skill "$g" "x-plugin/skills/comment-yaml-list" 'allowed-tools:
  - Read
  # a comment line between items
  - Bash  # full shell'
make_skill "$g" "x-plugin/skills/comment-broad" 'allowed-tools: Read, Bash(python3 *)  # for scripts'
# A `#` inside quotes, or with no space before it, is part of the grant.
make_skill "$g" "x-plugin/skills/hash-in-grant" 'allowed-tools: "Bash(git log --format=%h#x *)", Bash(jq -r '"'"'.a # b'"'"' *), Read'
run_check "$g" --list
assert "G1 one-line bare Bash with a trailing comment is a hit" "$(listed comment-one-line bare_bash)"
assert "G2 YAML-list bare Bash with a trailing comment is a hit" "$(listed comment-yaml-list bare_bash)"
assert "G3 a broad grant with a trailing comment is a hit" "$(listed comment-broad broad_shell_grant)"
assert "G4 a # inside a grant is not a comment (negative control)" "$(grep -q 'hash-in-grant' <<<"$OUT" && echo false || echo true)"
assert "G5 exactly 3 rows" "$(is "$(grep -c . <<<"$OUT")" 3)"

##########
# G. Worktree and dist copies inside a plugin are pruned (#1492, #2214)
##########
echo "=== G: prune ==="
run_check "$c" --list
g_before="$(grep -c . <<<"$OUT")"
mkdir -p "$c/x-plugin/.claude/worktrees/a/skills/dup" "$c/x-plugin/dist/opencode/skills/dup"
cp "$c/x-plugin/skills/broad-star/SKILL.md" "$c/x-plugin/.claude/worktrees/a/skills/dup/SKILL.md"
cp "$c/x-plugin/skills/broad-star/SKILL.md" "$c/x-plugin/dist/opencode/skills/dup/SKILL.md"
run_check "$c" --list
assert "G1 worktree/dist copies add no rows" "$(is "$(grep -c . <<<"$OUT")" "$g_before")"

echo ""
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
