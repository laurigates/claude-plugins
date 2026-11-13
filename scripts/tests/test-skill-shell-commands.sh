#!/usr/bin/env bash
# shellcheck disable=SC2016   # file-level: grant strings hold literal
#                             # ${CLAUDE_SKILL_DIR} and must NOT expand. Must
#                             # precede the first command.
# Regression test for scripts/skill-shell-commands.py (#3464).
#
# The helper is what the bare-Bash migration's editors derive grants from and
# what its verifier re-runs (--check) on every migrated skill, so this suite
# pins both halves against fixture skills under
# scripts/tests/fixtures/skill-shell-commands/. The fixtures are stored as
# `*.fixture.md` so no repo-wide SKILL.md scanner treats them as real skills;
# stage() copies a case into a sandbox under its real file names.
#
# Every "not listed" assertion is paired with a positive control on the same
# run, so a helper that extracted nothing fails here instead of passing.

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
HELPER="$repo_root/scripts/skill-shell-commands.py"
CONTRACT="$repo_root/scripts/check-structured-output-contract.sh"
FIXTURES="$script_dir/fixtures/skill-shell-commands"

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
has() { grep -qxF -- "$1" <<<"$OUT" && echo true || echo false; }      # exact line
hasre() { grep -qE -- "$1" <<<"$OUT" && echo true || echo false; }    # regex
lacks() { grep -qE -- "$1" <<<"$OUT" && echo false || echo true; }
field() { grep -m1 "^$1=" <<<"$OUT" | cut -d= -f2-; }
validates() { printf '%s\n' "$1" | bash "$CONTRACT" --validate - >/dev/null 2>&1 && echo true || echo false; }

sandbox=$(mktemp -d) || exit 1
[ -n "$sandbox" ] || exit 1
trap 'rm -rf "$sandbox"' EXIT

# stage <case> -> prints the staged skill dir
stage() {
  local dest="$sandbox/$1"
  rm -rf "$dest"
  cp -R "$FIXTURES/$1" "$dest"
  while IFS= read -r -d '' f; do
    mv "$f" "${f%.fixture.md}.md"
  done < <(find "$dest" -name '*.fixture.md' -print0)
  printf '%s\n' "$dest"
}
# set_grants <skill-dir> <allowed-tools value>
set_grants() {
  python3 - "$1/SKILL.md" "$2" <<'PY'
import re, sys
p, value = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r"^allowed-tools:.*$", lambda m: "allowed-tools: " + value, s, count=1, flags=re.M)
open(p, "w").write(s)
PY
}

OUT=""; RC=0
run() { OUT="$(python3 "$HELPER" "$@" 2>/dev/null)"; RC=$?; }

##########
# A. Usage errors exit 2 and print nothing on stdout
##########
echo "=== A: usage ==="
run;                               assert "A1 no arguments exits 2" "$(is "$RC" 2)"
run "$sandbox/does-not-exist";     assert "A2 a missing dir exits 2" "$(is "$RC" 2)"
mkdir -p "$sandbox/no-skill-md";   run "$sandbox/no-skill-md"
assert "A3 a dir without SKILL.md exits 2" "$(is "$RC" 2)"
cli="$(stage cli-ref)"
run "$cli" --bogus
assert "A4 an unknown flag exits 2" "$(is "$RC" 2)"
assert "A5 an unknown flag prints nothing on stdout" "$(is "$OUT" "")"

##########
# B. Default listing: a CLI-reference skill
##########
echo "=== B: cli-ref listing ==="
run "$cli"
assert "B0 listing exits 0" "$(is "$RC" 0)"
assert "B1 jq is listed with every occurrence counted (3 fence lines, 1 pipe, 1 inline)" \
  "$(has 'HEAD=jq SUB= SUB2= COUNT=5 SOURCES=SKILL.md')"
assert "B2 a pipeline's later command is listed" "$(hasre '^HEAD=head SUB= SUB2= COUNT=1 ')"
assert "B3 a pipeline's first command is listed" "$(hasre '^HEAD=cat SUB= SUB2= COUNT=1 ')"
assert "B4 a pipe inside quotes does not split out a command" "$(lacks '^HEAD=(sort|unique)')"
assert "B5 a python fence, an ASCII diagram and an inline path add nothing" "$(is "$(field COMMANDS)" 3)"
assert "B5b an inline path in prose is not a candidate" "$(lacks '^(HEAD|CANDIDATE)=.*\.claude/settings')"
assert "B6 candidates are one Bash(<cmd> *) per command" \
  "$( [ "$(has 'CANDIDATE=Bash(jq *)')" = true ] && [ "$(has 'CANDIDATE=Bash(head *)')" = true ] && [ "$(has 'CANDIDATE=Bash(cat *)')" = true ] && echo true || echo false)"
assert "B7 exactly three candidates" "$(is "$(grep -c '^CANDIDATE=' <<<"$OUT")" 3)"
assert "B8 listing output satisfies the contract" "$(validates "$OUT")"

##########
# C. Bundled scripts and sidecars
##########
echo "=== C: scripts-skill listing ==="
scr="$(stage scripts-skill)"
run "$scr"
assert "C1 an interpreter-run bundled script is a SCRIPT row" \
  "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/check.sh INTERP=bash QUOTED=0 COUNT=1 SOURCES=SKILL.md')"
assert "C2 a quoted invocation is flagged QUOTED=1" \
  "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/report.py INTERP=python3 QUOTED=1 COUNT=1 SOURCES=SKILL.md')"
assert "C3 a directly executed bundled script has no INTERP" \
  "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/direct.sh INTERP= QUOTED=0 COUNT=1 SOURCES=SKILL.md')"
assert "C3b a quoted, directly executed bundled script is recognised" \
  "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/quoted-direct.sh INTERP= QUOTED=1 COUNT=1 SOURCES=SKILL.md')"
assert "C4 a command only in REFERENCE.md is listed with that source" \
  "$(has 'HEAD=git SUB=status SUB2= COUNT=1 SOURCES=REFERENCE.md')"
assert "C5 an inline command in references/** is listed with that source" \
  "$(has 'HEAD=git SUB=log SUB2= COUNT=1 SOURCES=references/deep.md')"
assert "C6 anchored candidates spell the script path" \
  "$( [ "$(has 'CANDIDATE=Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check.sh *)')" = true ] && [ "$(has 'CANDIDATE=Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/report.py *)')" = true ] && [ "$(has 'CANDIDATE=Bash(${CLAUDE_SKILL_DIR}/scripts/direct.sh *)')" = true ] && echo true || echo false)"
assert "C7 never an interpreter wildcard candidate" "$(lacks '^CANDIDATE=Bash\((bash|sh|python3?|node) \*\)$')"
assert "C8 a git subcommand candidate is narrowed to the subcommand" \
  "$( [ "$(has 'CANDIDATE=Bash(git status *)')" = true ] && [ "$(has 'CANDIDATE=Bash(git log *)')" = true ] && echo true || echo false)"

##########
# D. A git/gh workflow: context commands, $(...), drops
##########
echo "=== D: git-workflow listing ==="
gw="$(stage git-workflow)"
run "$gw"
assert "D1 a !\`...\` Context command is listed" "$(hasre '^HEAD=git SUB=branch SUB2= COUNT=1 ')"
# `claude` is not on the known-command list, so only the bang rule lists it: an
# inline span of the same text would not count (mutation-checked).
assert "D1b a Context command counts even when its head is not a known command" "$(has 'CANDIDATE=Bash(claude *)')"
assert "D2 a \$(...) body is listed" "$(hasre '^HEAD=git SUB=rev-parse ')"
assert "D3 the command after an assignment-only segment is listed" "$(hasre '^HEAD=echo ')"
assert "D4 a ; or && inside quotes splits nothing out" "$(lacks '^HEAD=ls ')"
assert "D5 gh is narrowed two levels" "$(has 'CANDIDATE=Bash(gh pr create *)')"
assert "D6 git push is dropped, not offered" \
  "$( [ "$(has 'DROPPED=Bash(git push *) WHY=outward: pushes to a remote')" = true ] && [ "$(lacks '^CANDIDATE=Bash\(git push')" = true ] && echo true || echo false)"
assert "D7 git reset is dropped" "$(hasre '^DROPPED=Bash\(git reset \*\) WHY=destructive')"
assert "D8 rm is dropped" "$(hasre '^DROPPED=Bash\(rm \*\) WHY=destructive')"
assert "D9 a sudo command is dropped with sudo spelled" "$(hasre '^DROPPED=Bash\(sudo apt-get install \*\) WHY=sudo')"
assert "D10 inline interpreter code is dropped" "$(hasre '^DROPPED=Bash\(python3 -c \*\) WHY=inline code')"
assert "D11 a global option before the subcommand is dropped" "$(hasre '^DROPPED=Bash\(git -C \*\) WHY=global option')"
assert "D10b a command runner (xargs) is dropped" "$(hasre '^DROPPED=Bash\(xargs \*\) WHY=runs another command')"
assert "D11a a leading flag that takes no argument is itself a narrow candidate" "$(has 'CANDIDATE=Bash(bun --inspect-brk *)')"
assert "D11b a bare multi-level CLI is dropped, never Bash(gh *)" \
  "$( [ "$(hasre '^DROPPED=Bash\(gh \*\) WHY=no subcommand')" = true ] && [ "$(lacks '^CANDIDATE=Bash\(gh \*\)')" = true ] && echo true || echo false)"
assert "D11c a placeholder path is dropped, not offered" \
  "$( [ "$(hasre '^DROPPED=Bash\(bash <plugin>/scripts/sync\.sh \*\) WHY=placeholder')" = true ] && [ "$(lacks '^CANDIDATE=.*<plugin>')" = true ] && echo true || echo false)"
assert "D12 kept candidates still present (positive control)" \
  "$( [ "$(has 'CANDIDATE=Bash(git status *)')" = true ] && [ "$(has 'CANDIDATE=Bash(git commit *)')" = true ] && [ "$(has 'CANDIDATE=Bash(git branch *)')" = true ] && echo true || echo false)"

##########
# E. --check
##########
echo "=== E: --check ==="
run "$cli" --check
assert "E1 a bare Bash fails --check (exit 1)" "$(is "$RC" 1)"
assert "E2 ... as TYPE=bare_bash" "$(hasre 'SEVERITY=ERROR TYPE=bare_bash ')"
assert "E3 failing --check output satisfies the contract" "$(validates "$OUT")"
set_grants "$cli" 'Bash(jq *), Bash(head *), Bash(cat *), Read'
run "$cli" --check
assert "E4 grants matching the body pass --check (exit 0)" "$(is "$RC" 0)"
assert "E5 ... with STATUS=OK" "$(is "$(field STATUS)" OK)"
assert "E6 passing --check output satisfies the contract" "$(validates "$OUT")"
# Negative control on the same skill: one grant the body never runs.
set_grants "$cli" 'Bash(jq *), Bash(head *), Bash(cat *), Bash(git status *), Read'
run "$cli" --check
assert "E7 a grant for a command the body never shows fails (exit 1)" "$(is "$RC" 1)"
assert "E8 ... as TYPE=grant_not_in_body" "$(hasre 'SEVERITY=ERROR TYPE=grant_not_in_body MSG=Bash\(git status \*\)')"
run "$scr" --check
assert "E9 Bash(bash *) fails as TYPE=broad_shell_grant" "$( [ "$RC" = 1 ] && [ "$(hasre 'TYPE=broad_shell_grant')" = true ] && echo true || echo false)"
set_grants "$scr" 'Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check.sh *), Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/report.py *), Bash(${CLAUDE_SKILL_DIR}/scripts/direct.sh *), Bash(git status *), Bash(git log *), Read'
run "$scr" --check
assert "E10 anchored and sidecar grants pass --check" "$(is "$RC" 0)"
set_grants "$scr" 'Bash(bash ${CLAUDE_SKILL_DIR}/scripts/gone.sh *), Read'
run "$scr" --check
assert "E11 an anchored grant naming a script the body never runs fails" "$( [ "$RC" = 1 ] && [ "$(hasre 'TYPE=grant_not_in_body MSG=Bash\(bash \$\{CLAUDE_SKILL_DIR\}/scripts/gone\.sh')" = true ] && echo true || echo false)"
set_grants "$scr" 'Bash(git push *), Read'
run "$scr" --check
assert "E12 a subcommand the body never runs fails even when the head appears" "$( [ "$RC" = 1 ] && [ "$(hasre 'TYPE=grant_not_in_body MSG=Bash\(git push \*\)')" = true ] && echo true || echo false)"
set_grants "$scr" 'Bash(git status:*), Read'
run "$scr" --check
assert "E13 the colon form Bash(git status:*) is matched like the space form" "$(is "$RC" 0)"
set_grants "$scr" 'Read, Grep'
run "$scr" --check
assert "E14 a skill with no Bash grant passes --check" "$( [ "$RC" = 0 ] && [ "$(field GRANTS)" = 0 ] && echo true || echo false)"

##########
# F. A missing shared library is exit 2, never a clean or a findings result
##########
echo "=== F: missing library ==="
lone="$(mktemp -d)"; [ -n "$lone" ] || exit 1
cp "$HELPER" "$lone/skill-shell-commands.py"
OUT="$(python3 "$lone/skill-shell-commands.py" "$cli" --check 2>/dev/null)"; RC=$?
rm -rf "$lone"
assert "F1 a missing scripts/lib exits 2" "$(is "$RC" 2)"
assert "F2 ... and says why on STATUS=ERROR" "$( [ "$(field STATUS)" = ERROR ] && [ "$(hasre '^REASON=missing_helper: ')" = true ] && echo true || echo false)"

echo ""
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
