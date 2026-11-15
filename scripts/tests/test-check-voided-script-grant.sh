#!/usr/bin/env bash
# shellcheck disable=SC2016   # file-level: fixture bodies are deliberate literals
#                             # (${CLAUDE_SKILL_DIR}, $(pwd), backticks) and must
#                             # NOT expand. Must precede the first command.
# Regression test for scripts/check-voided-script-grant.sh (#3640).
#
# SEMANTIC: it EXECUTES the checker against planted fixture trees. Every
# "not flagged" case is paired with a flagged case in the same tree, so a
# checker that silently found nothing fails the suite as well as one that
# over-reports.

set -uo pipefail

# Neutralise inherited git context so no sandbox op can reach the shared
# checkout (#1745). The checker calls `git rev-parse --show-toplevel`.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
CHECK="$repo_root/scripts/check-voided-script-grant.sh"
contract="$repo_root/scripts/check-structured-output-contract.sh"

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

# write_md <root> <relative path> <body>
write_md() {
  local file_path="$1/$2"
  mkdir -p "$(dirname "$file_path")"
  printf -- '%s\n' "$3" > "$file_path"
}

OUT=""; RC=0
run_check() {
  local root="$1"; shift
  OUT="$(bash "$CHECK" --project-dir "$root" "$@" 2>/dev/null)"
  RC=$?
}

field() { grep -m1 "^$1=" <<<"$OUT" | cut -d= -f2-; }
# flagged <file suffix> <line>: a finding row names that file and line
flagged() { grep -qE "FILE=[^ ]*$1 LINE=$2 " <<<"$OUT" && echo true || echo false; }
is() { [ "$1" = "$2" ] && echo true || echo false; }

sandbox=$(mktemp -d) || exit 1
[ -n "$sandbox" ] || exit 1
trap 'rm -rf "$sandbox"' EXIT

##########
# A. Empty corpus -> STATUS=OK, SCANNED_EMPTY=true, exit 0
##########
echo "=== A: empty corpus ==="
empty="$sandbox/empty"; mkdir -p "$empty"
run_check "$empty"
assert "A1 empty corpus STATUS=OK" "$(is "$(field STATUS)" OK)"
assert "A2 empty corpus SCANNED_EMPTY=true" "$(is "$(field SCANNED_EMPTY)" true)"
assert "A3 empty corpus exits 0" "$(is "$RC" 0)"

##########
# B. Unknown argument -> exit 2, usage on stderr, nothing on stdout
##########
echo "=== B: unknown argument ==="
b_out="$(bash "$CHECK" --project-dir "$empty" --bogus-flag 2>/dev/null)"; b_rc=$?
b_err="$(bash "$CHECK" --project-dir "$empty" --bogus-flag 2>&1 >/dev/null)"
assert "B1 unknown arg exits 2" "$(is "$b_rc" 2)"
assert "B2 unknown arg prints nothing to stdout" "$([ -z "$b_out" ] && echo true || echo false)"
assert "B3 unknown arg names the flag on stderr" "$(grep -q 'bogus-flag' <<<"$b_err" && echo true || echo false)"
assert "B4 unknown arg prints usage on stderr" "$(grep -q 'Usage:' <<<"$b_err" && echo true || echo false)"
b2_err="$(bash "$CHECK" --project-dir 2>&1 >/dev/null)"; b2_rc=$?
assert "B5 --project-dir with no value exits 2" "$(is "$b2_rc" 2)"
assert "B6 --project-dir with no value says so" "$(grep -q 'requires a path' <<<"$b2_err" && echo true || echo false)"

##########
# C. Detection matrix
##########
echo "=== C: detection matrix ==="
c="$sandbox/c"
# Line numbers below are the 1-based lines of each body.
write_md "$c" "x-plugin/skills/fenced/SKILL.md" '# Fenced
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --project-dir "$(pwd)"
bash ${CLAUDE_SKILL_DIR}/scripts/a.sh --project-dir `pwd`
bash "${CLAUDE_PLUGIN_ROOT}/scripts/b.sh" --project-dir "$(pwd)"
bash ${CLAUDE_PLUGIN_ROOT}/skills/s/scripts/c.py $(git rev-parse --show-toplevel)
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --home-dir "$HOME"
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --ok; bash "${CLAUDE_SKILL_DIR}/scripts/d.sh" --x "$(pwd)"
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" \
  --project-dir "$(pwd)"
echo "$(pwd)"
uv run --script "${CLAUDE_SKILL_DIR}/../../scripts/e.py" --project-dir "$(pwd)"
bash "${CLAUDE_SKILL_DIR}/../<name>/scripts/<name>.sh" --project-dir "$(pwd)"
```'
write_md "$c" "x-plugin/skills/inline/SKILL.md" '# Inline

| Use | Command |
|-----|---------|
| bad | `bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --project-dir "$(pwd)"` |
| clean | `bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --home-dir "$HOME"` (append `--dry-run`) |
| second span | `bash ${CLAUDE_SKILL_DIR}/scripts/a.sh --ok` and `bash ${CLAUDE_SKILL_DIR}/scripts/d.sh --x "$(pwd)"` |
| double-delimited | `` bash ${CLAUDE_SKILL_DIR}/scripts/a.sh --project-dir `pwd` `` |
| prose | Run `pwd` first, then `bash ${CLAUDE_SKILL_DIR}/scripts/a.sh`. |'
write_md "$c" "x-plugin/skills/inline/references/sidecar.md" '# Sidecar
```
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --project-dir "$(pwd)"
```'
write_md "$c" "x-plugin/skills/inline/REFERENCE.md" '# Reference
`bash ${CLAUDE_SKILL_DIR}/scripts/a.sh --project-dir "$(pwd)"`'
write_md "$c" "x-plugin/agents/an-agent.md" '# Agent
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/b.sh" --project-dir "$(pwd)"
```'
# Prose outside any code element is not an invocation.
write_md "$c" "x-plugin/skills/prose/SKILL.md" '# Prose
The old form was bash ${CLAUDE_SKILL_DIR}/scripts/a.sh --project-dir "$(pwd)" in plain text.'
# Test fixtures are excluded: they hold the broken text on purpose.
write_md "$c" "x-plugin/skills/inline/scripts/tests/fixture.md" '```
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --project-dir "$(pwd)"
```'
run_check "$c"
assert "C1 fenced \$(…), quoted \${CLAUDE_SKILL_DIR}" "$(flagged fenced/SKILL.md 3)"
assert "C2 fenced backtick, unquoted \${CLAUDE_SKILL_DIR}" "$(flagged fenced/SKILL.md 4)"
assert "C3 fenced \$(…), quoted \${CLAUDE_PLUGIN_ROOT}" "$(flagged fenced/SKILL.md 5)"
assert "C4 fenced \$(…), unquoted \${CLAUDE_PLUGIN_ROOT} .py" "$(flagged fenced/SKILL.md 6)"
assert "C5 fenced clean \"\$HOME\" line is not flagged" "$(is "$(flagged fenced/SKILL.md 7)" false)"
assert "C6 second invocation on a fenced line" "$(flagged fenced/SKILL.md 8)"
assert "C7 backslash continuation carries the substitution" "$(flagged fenced/SKILL.md 9)"
assert "C8 substitution with no script invocation is not flagged" "$(is "$(flagged fenced/SKILL.md 11)" false)"
assert "C9 uv run --script invocation" "$(flagged fenced/SKILL.md 12)"
assert "C10 placeholder <name> script path" "$(flagged fenced/SKILL.md 13)"
assert "C11 inline span with \$(…)" "$(flagged inline/SKILL.md 5)"
assert "C12 clean inline span: its closing backtick is not a substitution" "$(is "$(flagged inline/SKILL.md 6)" false)"
assert "C13 second inline span on a line" "$(flagged inline/SKILL.md 7)"
assert "C14 backtick inside a double-backtick span" "$(flagged inline/SKILL.md 8)"
assert "C15 \`pwd\` in a separate span on the line is not flagged" "$(is "$(flagged inline/SKILL.md 9)" false)"
assert "C16 references/ sidecar" "$(flagged references/sidecar.md 3)"
assert "C17 REFERENCE.md sidecar" "$(flagged inline/REFERENCE.md 2)"
assert "C18 agents/*.md" "$(flagged agents/an-agent.md 3)"
assert "C19 plain prose is not an invocation" "$(is "$(flagged prose/SKILL.md 2)" false)"
assert "C20 tests/ fixtures are excluded" "$(grep -q 'tests/fixture.md' <<<"$OUT" && echo false || echo true)"
assert "C21 STATUS=ERROR" "$(is "$(field STATUS)" ERROR)"
assert "C22 exits 1 on findings" "$(is "$RC" 1)"
assert "C23 ISSUE_COUNT is the 14 flagged elements" "$(is "$(field ISSUE_COUNT)" 14)"
assert "C24 REASON names the type and (+13 more)" "$(grep -qE '^REASON=substitution_on_script_line: .*\(\+13 more\)$' <<<"$OUT" && echo true || echo false)"
assert "C25 failing output passes the structured-output contract" \
  "$(printf '%s\n' "$OUT" | bash "$contract" --validate - >/dev/null 2>&1 && echo true || echo false)"

##########
# D. Clean corpus -> STATUS=OK with a positive scan count
##########
echo "=== D: clean corpus ==="
d="$sandbox/d"
write_md "$d" "y-plugin/skills/clean/SKILL.md" '# Clean
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --home-dir "$HOME"
```'
run_check "$d"
assert "D1 clean corpus STATUS=OK" "$(is "$(field STATUS)" OK)"
assert "D2 clean corpus exits 0" "$(is "$RC" 0)"
assert "D3 clean corpus scanned one file" "$(is "$(field FILES_SCANNED)" 1)"
assert "D4 clean corpus counted one invocation" "$(is "$(field INVOCATIONS)" 1)"
assert "D5 passing output passes the structured-output contract" \
  "$(printf '%s\n' "$OUT" | bash "$contract" --validate - >/dev/null 2>&1 && echo true || echo false)"

##########
# E. Explicit file arguments (pre-commit style) skip discovery
##########
echo "=== E: explicit files ==="
OUT="$(cd "$c" && bash "$CHECK" --project-dir "$c" x-plugin/skills/inline/SKILL.md 2>/dev/null)"; RC=$?
assert "E1 explicit file is scanned alone" "$(is "$(field FILES_SCANNED)" 1)"
assert "E2 explicit file findings" "$(is "$(field ISSUE_COUNT)" 3)"

##########
# F. Discovery from inside an agent worktree path (#2219)
##########
echo "=== F: worktree-rooted discovery ==="
f="$sandbox/repo/.claude/worktrees/wf_x"
write_md "$f" "z-plugin/skills/s/SKILL.md" '```
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --project-dir "$(pwd)"
```'
write_md "$f" "z-plugin/.claude/worktrees/copy/z-plugin/skills/s/SKILL.md" '```
bash "${CLAUDE_SKILL_DIR}/scripts/a.sh" --project-dir "$(pwd)"
```'
run_check "$f"
assert "F1 a root inside .claude/worktrees still scans" "$(is "$(field FILES_SCANNED)" 1)"
assert "F2 nested worktree copies are pruned" "$(is "$(field ISSUE_COUNT)" 1)"

##########
# G. Plugin dirs with no skill markdown -> nothing_scanned ERROR
##########
echo "=== G: nothing scanned ==="
g="$sandbox/g"; mkdir -p "$g/w-plugin/.claude-plugin"
run_check "$g"
assert "G1 plugin dirs but zero files is ERROR" "$(is "$(field STATUS)" ERROR)"
assert "G2 REASON is nothing_scanned" "$(grep -q '^REASON=nothing_scanned' <<<"$OUT" && echo true || echo false)"
assert "G3 exits 1" "$(is "$RC" 1)"
assert "G4 output passes the structured-output contract" \
  "$(printf '%s\n' "$OUT" | bash "$contract" --validate - >/dev/null 2>&1 && echo true || echo false)"

echo "PASSED=${pass_count} FAILED=${fail_count}"
[ "$fail_count" -eq 0 ]
