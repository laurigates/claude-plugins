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
assert "C2 a quoted invocation is flagged QUOTED=1, its path unquoted" \
  "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/report.py INTERP=python3 QUOTED=1 COUNT=1 SOURCES=SKILL.md')"
assert "C3 a directly executed bundled script has no INTERP" \
  "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/direct.sh INTERP= QUOTED=0 COUNT=1 SOURCES=SKILL.md')"
assert "C3b a quoted, directly executed bundled script is recognised" \
  "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/quoted-direct.sh INTERP= QUOTED=1 COUNT=1 SOURCES=SKILL.md')"
assert "C4 a command only in REFERENCE.md is listed with that source" \
  "$(has 'HEAD=git SUB=status SUB2= COUNT=1 SOURCES=REFERENCE.md')"
assert "C5 an inline command in references/** is listed with that source" \
  "$(has 'HEAD=git SUB=log SUB2= COUNT=1 SOURCES=references/deep.md')"
assert "C6 anchored candidates are unquoted, whatever the body's quoting (#3464 F4)" \
  "$( [ "$(has 'CANDIDATE=Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check.sh *)')" = true ] && [ "$(has 'CANDIDATE=Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/report.py *)')" = true ] && [ "$(has 'CANDIDATE=Bash(${CLAUDE_SKILL_DIR}/scripts/quoted-direct.sh *)')" = true ] && [ "$(has 'CANDIDATE=Bash(${CLAUDE_SKILL_DIR}/scripts/direct.sh *)')" = true ] && echo true || echo false)"
assert "C6b no candidate carries a quote" "$(lacks "^CANDIDATE=.*[\"']")"
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
# Hazardous commands are review prompts, not drops (#3464 F3): a skill may
# grant one when running it is what the skill is for.
assert "D6 git push is a REVIEW row, not a candidate" \
  "$( [ "$(hasre '^REVIEW=Bash\(git push \*\) WHY=outward: pushes to a remote; grant it only if')" = true ] && [ "$(lacks '^(CANDIDATE|DROPPED)=Bash\(git push')" = true ] && echo true || echo false)"
assert "D7 git reset is a REVIEW row" "$(hasre '^REVIEW=Bash\(git reset \*\) WHY=destructive')"
assert "D8 rm is a REVIEW row" "$(hasre '^REVIEW=Bash\(rm \*\) WHY=destructive')"
assert "D9 a sudo command is a REVIEW row with sudo spelled" "$(hasre '^REVIEW=Bash\(sudo apt-get install \*\) WHY=sudo')"
assert "D10 inline interpreter code is dropped" "$(hasre '^DROPPED=Bash\(python3 -c \*\) WHY=inline code')"
assert "D11 a global option before the subcommand is dropped" "$(hasre '^DROPPED=Bash\(git -C \*\) WHY=global option')"
assert "D9b a linter with subcommands is narrowed to the subcommand" "$( [ "$(has 'CANDIDATE=Bash(ruff check *)')" = true ] && [ "$(lacks '^CANDIDATE=Bash\(ruff \*\)')" = true ] && echo true || echo false)"
assert "D9c docker run is a REVIEW row (any image, any mount)" "$(hasre '^REVIEW=Bash\(docker run \*\) WHY=runs arbitrary code in a container')"
assert "D10b a command runner (xargs) is dropped" "$(hasre '^DROPPED=Bash\(xargs \*\) WHY=runs another command')"
assert "D10c a runner shown with a fixed command is still dropped as Bash(timeout *)" "$(hasre '^DROPPED=Bash\(timeout \*\) WHY=runs another command')"
assert "D11a a leading flag that takes no argument is itself a narrow candidate" "$(has 'CANDIDATE=Bash(bun --inspect-brk *)')"
assert "D11b a bare multi-level CLI is dropped, never Bash(gh *)" \
  "$( [ "$(hasre '^DROPPED=Bash\(gh \*\) WHY=no subcommand')" = true ] && [ "$(lacks '^CANDIDATE=Bash\(gh \*\)')" = true ] && echo true || echo false)"
assert "D11c a placeholder path is dropped, not offered" \
  "$( [ "$(hasre '^DROPPED=Bash\(bash <plugin>/scripts/sync\.sh \*\) WHY=placeholder')" = true ] && [ "$(lacks '^CANDIDATE=.*<plugin>')" = true ] && echo true || echo false)"
assert "D11d a lone word in a prose span is listed but not offered as a grant" \
  "$( [ "$(hasre '^HEAD=type SUB= SUB2= COUNT=1 ')" = true ] && [ "$(hasre '^DROPPED=Bash\(type \*\) WHY=named alone')" = true ] && echo true || echo false)"
assert "D12 kept candidates still present (positive control)" \
  "$( [ "$(has 'CANDIDATE=Bash(git status *)')" = true ] && [ "$(has 'CANDIDATE=Bash(git commit *)')" = true ] && [ "$(has 'CANDIDATE=Bash(git branch *)')" = true ] && echo true || echo false)"
dup="$(sed -n 's/^CANDIDATE=//p; s/^\(REVIEW\|DROPPED\)=\(.*\) WHY=.*/\2/p' <<<"$OUT" | sort | uniq -d)"
assert "D13 no pattern is printed in two of CANDIDATE, REVIEW, DROPPED" "$(is "$dup" "")"

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
# A quoted script grant is an ERROR; the unquoted rule is the canonical
# spelling and matches a quoted invocation (#3464 F4).
set_grants "$scr" 'Bash(python3 "${CLAUDE_SKILL_DIR}/scripts/report.py" *), Read'
run "$scr" --check
assert "E15 a quoted script grant fails as TYPE=quoted_script_grant" \
  "$( [ "$RC" = 1 ] && [ "$(hasre 'SEVERITY=ERROR TYPE=quoted_script_grant MSG=')" = true ] && echo true || echo false)"
assert "E15b ... and its words still match the body (no grant_not_in_body)" "$(lacks 'TYPE=grant_not_in_body')"
set_grants "$scr" 'Bash(${CLAUDE_SKILL_DIR}/scripts/quoted-direct.sh *), Read'
run "$scr" --check
assert "E15c an unquoted grant passes against a quoted body invocation" "$(is "$RC" 0)"

# A hazardous grant the body runs is a WARN, exit 0 (#3464 F3).
for g in 'Bash(git push *)' 'Bash(git push --force-with-lease *)' 'Bash(git reset:*)' 'Bash(rm *)' \
         'Bash(docker run *)' 'Bash(sudo apt-get install *)'; do
  set_grants "$gw" "$g, Read"
  run "$gw" --check
  assert "E16 $g is a WARN hazardous_grant, exit 0" \
    "$( [ "$RC" = 0 ] && [ "$(field STATUS)" = WARN ] && [ "$(hasre '^REASON=hazardous_grant: ')" = true ] && [ "$(hasre 'SEVERITY=WARN TYPE=hazardous_grant MSG=')" = true ] && echo true || echo false)"
done
assert "E17 a hazardous grant the body runs is not also grant_not_in_body" "$(lacks 'TYPE=grant_not_in_body')"
assert "E18 WARN output satisfies the contract" "$(validates "$OUT")"
# A grant that pre-approves arbitrary code is an ERROR, exit 1.
for g in 'Bash(xargs *)' 'Bash(sudo *)' 'Bash(perl -e *)' 'Bash(timeout 30 *)'; do
  set_grants "$gw" "$g, Read"
  run "$gw" --check
  assert "E16b $g is TYPE=arbitrary_code_grant, exit 1" \
    "$( [ "$RC" = 1 ] && [ "$(hasre 'SEVERITY=ERROR TYPE=arbitrary_code_grant MSG=')" = true ] && echo true || echo false)"
done
set_grants "$gw" 'Bash(timeout 30 git fetch *), Read'
run "$gw" --check
assert "E16c a runner followed by a fixed command passes" "$(is "$RC" 0)"
set_grants "$gw" 'Bash(git push *), Bash(xargs *), Read'
run "$gw" --check
assert "E16d a mixed ERROR+WARN result is exit 1 with REASON from the ERROR row" \
  "$( [ "$RC" = 1 ] && [ "$(hasre '^REASON=arbitrary_code_grant: .*\(\+1 more\)$')" = true ] && echo true || echo false)"
assert "E16e mixed output satisfies the contract" "$(validates "$OUT")"
# Positive control on the same skill: narrow grants for commands it runs pass.
set_grants "$gw" 'Bash(git status *), Bash(git commit *), Bash(git branch *), Bash(gh pr create *), Read'
run "$gw" --check
assert "E19 narrow grants on the same skill still pass (control)" "$( [ "$RC" = 0 ] && [ "$(field STATUS)" = OK ] && echo true || echo false)"

# A multi-level CLI granted with no subcommand is an ERROR (#3464 F2).
for g in 'Bash(git *)' 'Bash(git:*)' 'Bash(gh *)' 'Bash(docker *)' 'Bash(git -C *)'; do
  set_grants "$gw" "$g, Read"
  run "$gw" --check
  assert "E20 $g is TYPE=no_subcommand, exit 1" \
    "$( [ "$RC" = 1 ] && [ "$(hasre 'SEVERITY=ERROR TYPE=no_subcommand MSG=')" = true ] && echo true || echo false)"
done
set_grants "$gw" 'Bash(git status *), Read'
run "$gw" --check
assert "E21 Bash(git status *) on the same skill passes (pair of E20)" "$(is "$RC" 0)"

##########
# G. A lone prose mention never contradicts a candidate (#3464 F1)
##########
echo "=== G: lone words ==="
ec="$(stage edge-cases)"
run "$ec"
assert "G1 mention before arguments: the command is a candidate" "$(has 'CANDIDATE=Bash(magick *)')"
assert "G2 ... and not also DROPPED" "$(lacks '^DROPPED=Bash\(magick \*\)')"
assert "G3 arguments before mention: the command is a candidate" "$(has 'CANDIDATE=Bash(identify *)')"
assert "G4 ... and not also DROPPED" "$(lacks '^DROPPED=Bash\(identify \*\)')"
assert "G5 a command only ever named alone is still DROPPED (control)" \
  "$( [ "$(hasre '^DROPPED=Bash\(convert \*\) WHY=named alone')" = true ] && [ "$(lacks '^CANDIDATE=Bash\(convert')" = true ] && echo true || echo false)"
dup="$(sed -n 's/^CANDIDATE=//p; s/^\(REVIEW\|DROPPED\)=\(.*\) WHY=.*/\2/p' <<<"$OUT" | sort | uniq -d)"
assert "G6 no pattern is printed in two of CANDIDATE, REVIEW, DROPPED" "$(is "$dup" "")"

##########
# H. A script candidate is unquoted whatever the body's quoting (#3464 F4)
##########
echo "=== H: quoted scripts ==="
assert "H1 quoted and unquoted invocations share one unquoted candidate" \
  "$( [ "$(has 'CANDIDATE=Bash(bash ${CLAUDE_SKILL_DIR}/scripts/run.sh *)')" = true ] && [ "$(grep -c '^CANDIDATE=.*scripts/run\.sh' <<<"$OUT")" = 1 ] && echo true || echo false)"
assert "H2 QUOTED= records each spelling on its own SCRIPT row" \
  "$( [ "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/run.sh INTERP=bash QUOTED=1 COUNT=1 SOURCES=SKILL.md')" = true ] && [ "$(has 'SCRIPT=${CLAUDE_SKILL_DIR}/scripts/run.sh INTERP=bash QUOTED=0 COUNT=1 SOURCES=SKILL.md')" = true ] && echo true || echo false)"
assert "H3 a single-quoted invocation gets an unquoted candidate" \
  "$(has 'CANDIDATE=Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/single.py *)')"
assert "H4 no candidate or SCRIPT row carries a quote" "$(lacks "^(CANDIDATE|SCRIPT)=.*[\"']")"
assert "H5 edge-case listing satisfies the contract" "$(validates "$OUT")"

##########
# I. Heads not on the known-command list, in shell-labelled fences (#3464 F1)
##########
echo "=== I: unknown heads ==="
gc="$(stage gcloud-skill)"
run "$gc"
assert "I1 a gcloud command is listed, narrowed two levels" "$(has 'HEAD=gcloud SUB=run SUB2=services COUNT=1 SOURCES=SKILL.md')"
assert "I2 ... with a candidate" "$(has 'CANDIDATE=Bash(gcloud run services *)')"
assert "I3 a command after a shell keyword is listed; the keyword is not" \
  "$( [ "$(hasre '^HEAD=gcloud SUB=auth SUB2=print-access-token ')" = true ] && [ "$(lacks '^HEAD=(if|then|fi) ')" = true ] && echo true || echo false)"
assert "I4 a backslash continuation is one command, a deploy verb a REVIEW row" \
  "$(hasre '^REVIEW=Bash\(gcloud run deploy \*\) WHY=outward: deploys')"
assert "I5 a quoted string continued on the next line is not a command" \
  "$( [ "$(lacks '^HEAD=body ')" = true ] && [ "$(hasre '^HEAD=git SUB=commit ')" = true ] && echo true || echo false)"
assert "I6 a heredoc body is not a command" \
  "$( [ "$(lacks '^HEAD=release ')" = true ] && [ "$(hasre '^HEAD=cat ')" = true ] && echo true || echo false)"
assert "I7 a console prompt line is listed, an output line is not" \
  "$( [ "$(hasre '^HEAD=mycli ')" = true ] && [ "$(lacks '^HEAD=ready ')" = true ] && echo true || echo false)"
assert "I8 an unknown head in a prose span stays out of the listing" "$(lacks 'frobnicate')"
assert "I8b a command after a leading [ test ] is listed" "$(hasre '^HEAD=gcloud SUB=config SUB2=list ')"
assert "I8c the alternatives of a regex line are not commands" "$(lacks '^HEAD=(fix|chore) ')"
assert "I8d a key = value line and an array assignment are not commands" "$(lacks '^HEAD=(requires-python|europe-north1-c) ')"
assert "I9 listing satisfies the contract" "$(validates "$OUT")"
set_grants "$gc" 'Bash(gcloud run services *), Bash(gcloud auth print-access-token *), Bash(mycli status *), Bash(frobnicate the *), Read'
run "$gc" --check
assert "I10 correct grants for unknown heads pass --check, prose span included" "$( [ "$RC" = 0 ] && [ "$(field STATUS)" = OK ] && echo true || echo false)"
set_grants "$gc" 'Bash(gcloud storage ls *), Read'
run "$gc" --check
assert "I11 a gcloud grant the body never shows still fails (control)" \
  "$( [ "$RC" = 1 ] && [ "$(hasre 'TYPE=grant_not_in_body MSG=Bash\(gcloud storage ls')" = true ] && echo true || echo false)"
set_grants "$gc" 'Bash(gcloud *), Read'
run "$gc" --check
assert "I12 Bash(gcloud *) is TYPE=no_subcommand" "$( [ "$RC" = 1 ] && [ "$(hasre 'TYPE=no_subcommand')" = true ] && echo true || echo false)"
set_grants "$gc" 'Bash(gcloud run deploy *), Read'
run "$gc" --check
assert "I13 a deploy grant the body runs is WARN, exit 0" "$( [ "$RC" = 0 ] && [ "$(field STATUS)" = WARN ] && [ "$(validates "$OUT")" = true ] && echo true || echo false)"

##########
# J. An unknown head, and commands only in sidecars (#3464 F1)
##########
echo "=== J: playwright-cli and sidecars ==="
pw="$(stage playwright-skill)"
run "$pw"
assert "J1 playwright-cli is listed with both lines counted" "$(has 'HEAD=playwright-cli SUB= SUB2= COUNT=2 SOURCES=SKILL.md')"
assert "J2 ... with a candidate" "$(has 'CANDIDATE=Bash(playwright-cli *)')"
assert "J3 a command only in a sidecar's bash fence is listed with that source" "$(has 'HEAD=pwsnap SUB= SUB2= COUNT=1 SOURCES=REFERENCE.md')"
assert "J4 an unknown head in an unlabeled fence stays out of the listing" "$(lacks 'pwreport')"
set_grants "$pw" 'Bash(playwright-cli open *), Bash(playwright-cli screenshot *), Bash(pwsnap capture *), Bash(pwreport build *), Read'
run "$pw" --check
assert "J5 grants for SKILL.md, sidecar-fence and sidecar-unlabeled commands pass" "$(is "$RC" 0)"
set_grants "$pw" 'Bash(playwright-cli install *), Read'
run "$pw" --check
assert "J6 a playwright-cli subcommand the body never shows fails (control)" \
  "$( [ "$RC" = 1 ] && [ "$(hasre 'TYPE=grant_not_in_body MSG=Bash\(playwright-cli install')" = true ] && echo true || echo false)"

##########
# K. Table pipes, run-time paths, sudo, runners (#3464 repair round 3)
##########
echo "=== K: run-time shapes ==="
rt="$(stage runtime-skill)"
run "$rt"
assert "K1 a command after a table-cell \\| pipe is listed" "$(hasre '^HEAD=wc SUB= SUB2= COUNT=1 ')"
assert "K2 a script path built by \$(...) is dropped, not a candidate" \
  "$( [ "$(hasre '^DROPPED=Bash\(bash \$\(git \*\) WHY=built at run time')" = true ] && [ "$(lacks '^CANDIDATE=.*\$\(')" = true ] && echo true || echo false)"
assert "K3 a script path built by \${{ }} is dropped" "$(hasre '^DROPPED=Bash\(sh \$\{\{ \*\) WHY=built at run time')"
assert "K4 kept candidates on the same run (control)" \
  "$( [ "$(has 'CANDIDATE=Bash(find *)')" = true ] && [ "$(hasre '^REVIEW=Bash\(sudo powermetrics \*\) WHY=sudo')" = true ] && echo true || echo false)"
assert "K5 listing satisfies the contract" "$(validates "$OUT")"
set_grants "$rt" 'Bash(find *), Bash(wc *), Read'
run "$rt" --check
assert "K6 a grant for the command after a table-cell \\| passes" "$(is "$RC" 0)"
set_grants "$rt" 'Bash(powermetrics *), Read'
run "$rt" --check
assert "K7 a grant leaving out the sudo the body shows fails" \
  "$( [ "$RC" = 1 ] && [ "$(hasre 'TYPE=grant_not_in_body MSG=Bash\(powermetrics')" = true ] && echo true || echo false)"
set_grants "$rt" 'Bash(sudo powermetrics *), Read'
run "$rt" --check
assert "K8 the anchored sudo grant is a WARN, exit 0 (pair of K7)" \
  "$( [ "$RC" = 0 ] && [ "$(field STATUS)" = WARN ] && [ "$(hasre 'TYPE=hazardous_grant MSG=Bash\(sudo powermetrics')" = true ] && echo true || echo false)"
set_grants "$rt" 'Bash(timeout 60 ${CLAUDE_SKILL_DIR}/scripts/probe.sh *), Read'
run "$rt" --check
assert "K9 a runner before a bundled script is a fixed command, exit 0" "$( [ "$RC" = 0 ] && [ "$(field STATUS)" = OK ] && echo true || echo false)"
for g in 'Bash(xargs bash *)' 'Bash(sudo sh *)'; do
  set_grants "$rt" "$g, Read"
  run "$rt" --check
  assert "K10 $g is TYPE=arbitrary_code_grant" "$( [ "$RC" = 1 ] && [ "$(hasre 'SEVERITY=ERROR TYPE=arbitrary_code_grant ')" = true ] && echo true || echo false)"
done
set_grants "$gc" 'Bash(ready to *), Read'
run "$gc" --check
assert "K11 a console fence's output line is not a command to grant" \
  "$( [ "$RC" = 1 ] && [ "$(hasre 'TYPE=grant_not_in_body MSG=Bash\(ready to')" = true ] && echo true || echo false)"
set_grants "$gc" 'Bash(mycli status *), Read'
run "$gc" --check
assert "K12 its prompt line is (pair of K11)" "$(is "$RC" 0)"

##########
# L. Inline code in an option cluster, stdin forms, option-only interpreter
#    words; one per-interpreter table for listing and --check (#3464 round 4)
##########
echo "=== L: interpreter flags ==="
ifl="$(stage interp-flags)"
run "$ifl"
assert "L0 listing exits 0" "$(is "$RC" 0)"
for p in 'zsh -fc' 'bash -lc' 'sh -ec' 'zsh -f -c' 'sh -s' 'bash -s' 'python3 -' 'perl -ne' 'node -pe'; do
  # Fixed-string matches: the patterns hold regex metacharacters (`-`, `*`).
  dropped=false; offered=false
  grep -qF -- "DROPPED=Bash($p *) WHY=inline code" <<<"$OUT" && dropped=true
  grep -qF -- "CANDIDATE=Bash($p " <<<"$OUT" && offered=true
  assert "L1 Bash($p *) is DROPPED as inline code, never a CANDIDATE" \
    "$( [ "$dropped" = true ] && [ "$offered" = false ] && echo true || echo false)"
done
assert "L2 bash -e script.sh (errexit) is a candidate pinned to its script" "$(has 'CANDIDATE=Bash(bash -e script.sh *)')"
assert "L3 bash -e is never DROPPED as inline code" "$(lacks '^DROPPED=Bash\(bash -e \*\) WHY=inline code')"
assert "L4 a lone bash -e is DROPPED for having no script, and says so" \
  "$(hasre '^DROPPED=Bash\(bash -e \*\) WHY=interpreter options with no script')"
assert "L5 near misses stay candidates (control)" \
  "$( [ "$(has 'CANDIDATE=Bash(bash ${CLAUDE_SKILL_DIR}/scripts/x.sh *)')" = true ] && [ "$(has 'CANDIDATE=Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/x.py *)')" = true ] && [ "$(has 'CANDIDATE=Bash(python3 -I ${CLAUDE_SKILL_DIR}/scripts/report.py *)')" = true ] && [ "$(has 'CANDIDATE=Bash(node --version *)')" = true ] && echo true || echo false)"
assert "L6 listing satisfies the contract" "$(validates "$OUT")"
dup="$(sed -n 's/^CANDIDATE=//p; s/^\(REVIEW\|DROPPED\)=\(.*\) WHY=.*/\2/p' <<<"$OUT" | sort | uniq -d)"
assert "L7 no pattern is printed in two of CANDIDATE, REVIEW, DROPPED" "$(is "$dup" "")"
# The listing drops exactly what --check rejects: every inline-code or
# option-only DROPPED row, granted, is an arbitrary_code_grant ERROR.
listing="$OUT"
drops="$(sed -n 's/^DROPPED=\(Bash(.*)\) WHY=\(inline code\|interpreter options\).*/\1/p' <<<"$listing")"
assert "L8 the sweep below has rows to check (positive control)" "$(is "$(grep -c . <<<"$drops")" 10)"
while IFS= read -r g; do
  set_grants "$ifl" "$g, Read"
  run "$ifl" --check
  assert "L9 listed drop $g is rejected by --check as arbitrary_code_grant" \
    "$( [ "$RC" = 1 ] && [ "$(hasre 'SEVERITY=ERROR TYPE=arbitrary_code_grant ')" = true ] && echo true || echo false)"
done <<<"$drops"
for g in 'Bash(bash -lc *)' 'Bash(/bin/zsh -fc *)' 'Bash(sh -ec *)' 'Bash(env bash -lc *)' 'Bash(perl -lne *)'; do
  set_grants "$ifl" "$g, Read"
  run "$ifl" --check
  assert "L10 $g is TYPE=arbitrary_code_grant, exit 1" \
    "$( [ "$RC" = 1 ] && [ "$(hasre 'SEVERITY=ERROR TYPE=arbitrary_code_grant ')" = true ] && echo true || echo false)"
done
cands="$(sed -n 's/^CANDIDATE=//p' <<<"$listing" | paste -sd, -)"
set_grants "$ifl" "$cands, Read"
run "$ifl" --check
assert "L11 every listed candidate, granted together, passes --check (pair of L9)" \
  "$( [ "$RC" = 0 ] && [ "$(field STATUS)" = OK ] && echo true || echo false)"
for g in 'Bash(bash -e script.sh *)' 'Bash(bash ${CLAUDE_SKILL_DIR}/scripts/x.sh *)' 'Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/x.py *)' 'Bash(node --version *)'; do
  set_grants "$ifl" "$g, Read"
  run "$ifl" --check
  assert "L12 near miss $g passes --check" "$( [ "$RC" = 0 ] && [ "$(field STATUS)" = OK ] && echo true || echo false)"
done

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
