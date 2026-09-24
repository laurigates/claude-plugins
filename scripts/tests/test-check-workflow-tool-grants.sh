#!/usr/bin/env bash
# shellcheck disable=SC2016
# SC2016 is the point, not a slip: the fixtures below are single-quoted so
# `$(...)`, `$?` and `$id` reach the guard as LITERAL text. Cases D and C assert
# exactly that a leading `RUN_DIR=$(...)` and a trailing `; echo "EXIT=$?"` are
# flagged, which double quotes would expand away. File-level and ahead of the
# first command per .claude/rules/shell-scripting.md -- placed lower it degrades
# to a next-statement directive.
#
# Regression test for scripts/check-workflow-tool-grants.sh.
#
# The bug this guards (#2493): `claude-code-action`'s `Bash(<pattern>)` grants
# are PREFIX matches on the whole command string. Two revived audits lost ten
# tool calls to that on their first post-fix scheduled runs --
# workflow-model-audit run 34234073610 (4 denials, then RED on
# "successful result after 42 turns, exceeding the configured maximum of 40")
# and golden-set-evaluation run 34981573686 (6 denials, 59 of 60 turns). SEVEN
# of the ten were commands that WERE granted and were denied anyway because the
# call did not begin with the granted prefix.
#
# Every fixture below replays one of those ten observed shapes verbatim:
#
#   B  for id in ...; do gh run view $id ...; done     (run 34234073610, #2)
#   C  gh issue list ... ; echo "EXIT=$?"              (run 34234073610, #4)
#   D  RUN_DIR=$(bash prepare_run.sh ...)              (leading-assignment form)
#   E  mkdir -p .../gc-001-opus-run-1                  (run 34981573686, #2/#3)
#   G  for e in ...; do for m in ...; done             (run 34981573686, #1)
#   H  mkdir -p /tmp/g && cp SKILL.md ... && wc -c ... (run 34981573686, #4)
#   L  gh issue list --label golden-set-eval ...       (run 34981573686, #6)
#
# The load-bearing counter-cases are F, I, M and P: without them every "is
# flagged" assertion here would also hold for a guard that flags EVERYTHING.
# I is the sharpest -- it replays the real `gh issue create --body "$(cat
# <<'EOF' ... EOF )"` call site, whose heredoc body is markdown. A guard that
# did not skip heredoc bodies would report `## Heading` and `| Skill | Model |`
# as ungranted commands and make the working call site in three shipped
# workflows unlintable.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="${CHECK_WORKFLOW_TOOL_GRANTS:-$repo_root/scripts/check-workflow-tool-grants.sh}"

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

is_true() { [ "$1" = "true" ] && echo true || echo false; }
contains() { printf '%s' "$1" | grep -qF -- "$2" && echo true || echo false; }
lacks() { [ "$(contains "$1" "$2")" = false ] && echo true || echo false; }
# The runtime half of the structured-output contract (#2691): one canonical
# STATUS=, REASON= present iff non-OK, ISSUE_COUNT= equal to the ISSUES: rows.
validates() {
  printf '%s\n' "$1" | bash "$repo_root/scripts/check-structured-output-contract.sh" --validate >/dev/null 2>&1 \
    && echo true || echo false
}

fx="$(mktemp -d)"
[ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

DEFAULT_TOOLS='Read,Grep,Glob,Bash(gh run view *),Bash(gh issue create *),Bash(bash *),Bash(date *),Bash(cat *)'

# mkwf <name> <allowedTools-or-NONE> <fence-body> -- build a throwaway repo
# holding one workflow whose claude-code-action prompt carries <fence-body>
# inside a ```bash fence.
mkwf() {
  local dir="$fx/$1" tools="$2" body="$3"
  mkdir -p "$dir/.github/workflows"
  {
    printf 'on: push\n'
    printf 'jobs:\n'
    printf '  audit:\n'
    printf '    runs-on: ubuntu-latest\n'
    printf '    steps:\n'
    printf '      - uses: anthropics/claude-code-action@v1\n'
    printf '        with:\n'
    if [ "$tools" = "NONE" ]; then
      printf '          claude_args: >-\n'
      printf '            --model opus\n'
      printf '            --effort medium\n'
    else
      printf '          claude_args: >-\n'
      printf '            --model opus\n'
      printf '            --effort medium\n'
      printf '            --allowedTools "%s"\n' "$tools"
    fi
    printf '          prompt: |\n'
    printf '            Do the audit.\n\n'
    printf '            ```bash\n'
    printf '%s\n' "$body" | sed 's/^/            /'
    printf '            ```\n'
  } > "$dir/.github/workflows/w.yml"
  printf '%s' "$dir"
}

run_fixture() { bash "$checker" --project-dir "$1" 2>&1; }

# --- TEST A: the real repo ----------------------------------------------------
echo "=== TEST A: real repo is clean and was actually inspected ==="
out="$(bash "$checker" 2>&1)"; rc=$?
assert "A real repo exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "A real repo STATUS=OK" "$(contains "$out" 'STATUS=OK')"
assert "A real repo carries no REASON on OK" "$(lacks "$out" 'REASON=')"
assert "A real repo output satisfies the contract" "$(validates "$out")"
# Guard integrity: a checker that parsed nothing would also print STATUS=OK.
assert "A real repo scanned workflows" "$(lacks "$out" 'WORKFLOWS_SCANNED=0')"
assert "A real repo found claude steps" "$(lacks "$out" 'CLAUDE_STEPS=0')"
assert "A real repo found allowlisted steps" "$(lacks "$out" 'STEPS_WITH_ALLOWLIST=0')"
assert "A real repo checked real bash calls" "$(lacks "$out" 'BASH_CALLS_CHECKED=0')"

# --- TEST B: a granted command inside a for loop (run 34234073610, denial 2) --
echo "=== TEST B: for-loop over a GRANTED command is flagged ==="
d="$(mkwf b "$DEFAULT_TOOLS" 'for id in 34221403143 34027709049; do gh run view $id --json jobs; done')"
out="$(run_fixture "$d")"; rc=$?
assert "B exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "B STATUS=ERROR" "$(contains "$out" 'STATUS=ERROR')"
assert "B REASON names the loop" "$(contains "$out" 'REASON=unprefixable_shape: SHAPE=loop ')"
assert "B output satisfies the contract" "$(validates "$out")"
assert "B TYPE=unprefixable_shape" "$(contains "$out" 'TYPE=unprefixable_shape')"
assert "B SHAPE=loop" "$(contains "$out" 'SHAPE=loop')"
assert "B does not misreport it as merely ungranted" "$(lacks "$out" 'TYPE=ungranted_command')"
assert "B explains the prefix rule" "$(contains "$out" 'PREFIX match')"

# --- TEST C: a granted command with a trailing `; echo` (denial 4) ------------
echo "=== TEST C: trailing '; echo EXIT=\$?' on a granted command is flagged ==="
d="$(mkwf c "$DEFAULT_TOOLS,Bash(gh issue list *)" 'gh issue list --label golden-set-eval --state all --limit 5 --json number ; echo "EXIT=$?"')"
out="$(run_fixture "$d")"; rc=$?
assert "C exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "C SHAPE=chain" "$(contains "$out" 'SHAPE=chain')"

# --- TEST D: a leading VAR=$(...) assignment ---------------------------------
echo "=== TEST D: leading VAR=\$(...) assignment is flagged ==="
d="$(mkwf d "$DEFAULT_TOOLS" 'RUN_DIR=$(bash evaluate-plugin/scripts/prepare_run.sh gc-001 opus)')"
out="$(run_fixture "$d")"; rc=$?
assert "D exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "D SHAPE=assignment" "$(contains "$out" 'SHAPE=assignment')"

# --- TEST E: a plain command with no grant at all (denials 2-3 of the sweep) --
echo "=== TEST E: an ungranted bare command is flagged with its token ==="
d="$(mkwf e "$DEFAULT_TOOLS" 'mkdir -p evaluate-plugin/eval-results/runs/gc-001-opus-run-1')"
out="$(run_fixture "$d")"; rc=$?
assert "E exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "E TYPE=ungranted_command" "$(contains "$out" 'TYPE=ungranted_command')"
assert "E names the leading token" "$(contains "$out" 'TOKEN=mkdir')"
assert "E is not misreported as a shape problem" "$(lacks "$out" 'TYPE=unprefixable_shape')"

# --- TEST F: the clean single granted command MUST pass -----------------------
echo "=== TEST F: one granted command per call passes (counter-case) ==="
d="$(mkwf f "$DEFAULT_TOOLS" 'gh run view 34234073610 --json jobs')"
out="$(run_fixture "$d")"; rc=$?
assert "F exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "F STATUS=OK" "$(contains "$out" 'STATUS=OK')"
assert "F still inspected the call" "$(contains "$out" 'BASH_CALLS_CHECKED=1')"

# --- TEST G: nested for loops (run 34981573686, denial 1) --------------------
echo "=== TEST G: nested for loops around a granted command are flagged ==="
d="$(mkwf g "$DEFAULT_TOOLS" 'for e in gc-001 gc-002; do for m in opus haiku; do bash prepare_run.sh $e $m; done; done')"
out="$(run_fixture "$d")"; rc=$?
assert "G exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "G SHAPE=loop" "$(contains "$out" 'SHAPE=loop')"

# --- TEST H: an && chain (run 34981573686, denial 4) -------------------------
echo "=== TEST H: an '&&' chain is flagged as a shape problem ==="
d="$(mkwf h "$DEFAULT_TOOLS" 'mkdir -p /tmp/gsweep && cp git-plugin/skills/git-commit/SKILL.md /tmp/gsweep/guidance.md && wc -c /tmp/gsweep/guidance.md')"
out="$(run_fixture "$d")"; rc=$?
assert "H exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "H SHAPE=chain" "$(contains "$out" 'SHAPE=chain')"

# --- TEST I: the real heredoc call site must NOT be shredded ------------------
# Load-bearing counter-case. `gh issue create --body "$(cat <<'EOF' … EOF )"`
# ships in three workflows; a guard that did not skip heredoc bodies would
# report the markdown inside as ungranted commands.
echo "=== TEST I: gh issue create with a markdown heredoc body passes ==="
d="$(mkwf i "$DEFAULT_TOOLS" 'gh issue create \
  --title "Golden-set cross-model sweep: 2026-09" \
  --label "golden-set-eval,maintenance" \
  --body "$(cat <<'"'"'EOF'"'"'
## Golden-set cross-model sweep: 2026-09

### Results
| Skill | Model | With skill | Baseline | Delta | Verdict |
|-------|-------|-----------|----------|-------|---------|

mkdir -p this-line-is-prose-not-a-command
EOF
)"')"
out="$(run_fixture "$d")"; rc=$?
assert "I exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "I STATUS=OK" "$(contains "$out" 'STATUS=OK')"
assert "I read it as exactly one command" "$(contains "$out" 'BASH_CALLS_CHECKED=1')"
assert "I did not flag the heredoc prose" "$(lacks "$out" 'TOKEN=mkdir')"

# --- TEST J: a step with no --allowedTools is SKIPPED, not failed -------------
echo "=== TEST J: a step declaring no boundary is skipped, not flagged ==="
d="$(mkwf j NONE 'mkdir -p whatever')"
out="$(run_fixture "$d")"; rc=$?
assert "J exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "J counts the skip" "$(contains "$out" 'SKIPPED_NO_ALLOWLIST=1')"
assert "J checked no calls" "$(contains "$out" 'BASH_CALLS_CHECKED=0')"

# --- TEST K: a bare `Bash` grant permits any command, but not any SHAPE -------
echo "=== TEST K: bare Bash grants every command; shapes are still flagged ==="
d="$(mkwf k1 'Read,Bash' 'mkdir -p evaluate-plugin/eval-results/runs/gc-001')"
out="$(run_fixture "$d")"; rc=$?
assert "K1 exits 0 under a bare Bash grant" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "K1 still inspected the call" "$(contains "$out" 'BASH_CALLS_CHECKED=1')"
d="$(mkwf k2 'Read,Bash' 'for id in 1 2; do gh run view $id --json jobs; done')"
out="$(run_fixture "$d")"; rc=$?
assert "K2 flags the loop even under a bare Bash grant" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "K2 SHAPE=loop" "$(contains "$out" 'SHAPE=loop')"

# --- TEST L: prefix precision -- a sibling subcommand is NOT covered ----------
# `gh issue list` was denied on run 34981573686 precisely because only
# `Bash(gh issue create *)` was granted. A guard that matched on the first WORD
# would call this granted and reproduce the bug.
echo "=== TEST L: Bash(gh issue create *) does not cover 'gh issue list' ==="
d="$(mkwf l "$DEFAULT_TOOLS" 'gh issue list --repo laurigates/claude-plugins --label golden-set-eval --state open --limit 20')"
out="$(run_fixture "$d")"; rc=$?
assert "L exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "L TYPE=ungranted_command" "$(contains "$out" 'TYPE=ungranted_command')"
# …and granting it clears the finding, so L is not passing by accident.
d="$(mkwf l2 "$DEFAULT_TOOLS,Bash(gh issue list *)" 'gh issue list --repo laurigates/claude-plugins --label golden-set-eval --state open --limit 20')"
out="$(run_fixture "$d")"; rc=$?
assert "L2 exits 0 once the grant is added" "$(is_true "$([ $rc -eq 0 ] && echo true)")"

# --- TEST M: comments do not break a granted command --------------------------
echo "=== TEST M: a trailing '# comment' and comment lines are ignored ==="
d="$(mkwf m "$DEFAULT_TOOLS" '# compute the month first
date -u +%Y-%m    # note the value, e.g. 2026-08')"
out="$(run_fixture "$d")"; rc=$?
assert "M exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "M counted only the real command" "$(contains "$out" 'BASH_CALLS_CHECKED=1')"

# --- TEST N: a non-shell fence is not parsed as commands ----------------------
echo '=== TEST N: a ```json fence is not treated as bash ==='
dir="$fx/n"
mkdir -p "$dir/.github/workflows"
{
  printf 'on: push\njobs:\n  audit:\n    runs-on: ubuntu-latest\n    steps:\n'
  printf '      - uses: anthropics/claude-code-action@v1\n        with:\n'
  printf '          claude_args: >-\n            --model opus\n            --effort medium\n'
  printf '            --allowedTools "Read,Bash(date *)"\n'
  printf '          prompt: |\n            Emit this shape:\n\n'
  printf '            ```json\n            {"mkdir": "not a command"}\n            ```\n'
} > "$dir/.github/workflows/w.yml"
out="$(run_fixture "$dir")"; rc=$?
assert "N exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "N parsed no bash calls" "$(contains "$out" 'BASH_CALLS_CHECKED=0')"

# --- TEST O: argument handling (never a vacuous pass, #2057) ------------------
echo "=== TEST O: bad arguments exit 2, not 0 ==="
bash "$checker" --bogus >/dev/null 2>&1; rc=$?
assert "O unknown flag exits 2" "$(is_true "$([ $rc -eq 2 ] && echo true)")"
bash "$checker" --project-dir >/dev/null 2>&1; rc=$?
assert "O --project-dir without a dir exits 2" "$(is_true "$([ $rc -eq 2 ] && echo true)")"
bash "$checker" --help >/dev/null 2>&1; rc=$?
assert "O --help exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"

# --- TEST P: explicit-file mode checks the file it was handed -----------------
echo "=== TEST P: explicit-file (pre-commit) mode flags the same defect ==="
d="$(mkwf p "$DEFAULT_TOOLS" 'for id in 1 2; do gh run view $id --json jobs; done')"
out="$(bash "$checker" "$d/.github/workflows/w.yml" 2>&1)"; rc=$?
assert "P exits 1 on an explicit file" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "P scanned exactly that file" "$(contains "$out" 'WORKFLOWS_SCANNED=1')"
assert "P SHAPE=loop" "$(contains "$out" 'SHAPE=loop')"

echo ""
echo "=== RESULTS ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
