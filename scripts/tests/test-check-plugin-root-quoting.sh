#!/usr/bin/env bash
# Regression test for scripts/check-plugin-root-quoting.sh.
#
# Claude Code 2.1.281's `claude plugin validate` warns on shell-form hook
# commands that leave ${CLAUDE_PLUGIN_ROOT} unquoted (word-split on a path with
# a space). Every assertion EXECUTES the guard against a planted fixture tree
# and reads its verdict — a grep for the quoted literal would pass on a
# half-quoted command too (the syntactic-gate lesson in docs/regression-ledger.md).
# Paired cases: each flagged shape sits beside an accepted one, so the suite
# fails both an over-reporting guard and a permanently-silent one.
#
# Run: bash scripts/tests/test-check-plugin-root-quoting.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-plugin-root-quoting.sh"
CONTRACT="$REPO_ROOT/scripts/check-structured-output-contract.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP_ROOT="$(mktemp -d)"
[ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ] || { echo "FAIL: mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP_ROOT"' EXIT

run_guard() { bash "$GUARD" --project-dir "$1" 2>&1; }
field() { printf '%s\n' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# expect <label> <tree> <want-status> <want-issue-count> [<grep-in-output>]
expect() {
  local label="$1" tree="$2" want_status="$3" want_count="$4" needle="${5:-}"
  local out rc want_rc=0
  out="$(run_guard "$tree")"; rc=$?
  [ "$want_status" = "OK" ] || want_rc=1
  if [ "$rc" -eq "$want_rc" ] && [ "$(field "$out" STATUS)" = "$want_status" ] \
     && [ "$(field "$out" ISSUE_COUNT)" = "$want_count" ]; then
    pass "$label (STATUS=$want_status ISSUE_COUNT=$want_count rc=$rc)"
  else
    fail "$label: want STATUS=$want_status ISSUE_COUNT=$want_count rc=$want_rc, got rc=$rc:"
    printf '%s\n' "$out" | sed 's/^/    | /'
  fi
  if [ -n "$needle" ]; then
    if grep -qF -- "$needle" <<<"$out"; then
      pass "$label: output names '$needle'"
    else
      fail "$label: output lacks '$needle'"
    fi
  fi
  # Every output block must satisfy the STATUS=/ISSUE_COUNT=/REASON= contract.
  if printf '%s\n' "$out" | bash "$CONTRACT" --validate - >/dev/null 2>&1; then
    pass "$label: output satisfies the structured-output contract"
  else
    fail "$label: output violates the structured-output contract"
  fi
}

# write_hooks <tree> <relpath> <command-json-string> [extra handler fields]
write_hooks() {
  local tree="$1" rel="$2" cmd="$3" extra="${4:-}"
  mkdir -p "$(dirname "$tree/$rel")"
  printf '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": %s%s}]}]}}\n' \
    "$cmd" "$extra" > "$tree/$rel"
}

# --- (a) the verbatim pre-fix shape is an ERROR; its quoted repair is OK ------
T="$TMP_ROOT/a-unquoted"
write_hooks "$T" "x-plugin/hooks.json" '"bash ${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh"'
expect "(a) unquoted \${CLAUDE_PLUGIN_ROOT} in hooks.json" "$T" ERROR 1 "TYPE=unquoted_plugin_root"

T="$TMP_ROOT/a-quoted"
write_hooks "$T" "x-plugin/hooks.json" '"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh\""'
expect "(a) quoted form passes" "$T" OK 0 "QUOTED_COMMANDS=1"

# --- (b) bare $CLAUDE_PLUGIN_ROOT is caught too; a longer name is not --------
T="$TMP_ROOT/b-bare"
write_hooks "$T" "x-plugin/hooks/hooks.json" '"bash $CLAUDE_PLUGIN_ROOT/hooks/foo.sh"'
expect "(b) bare \$CLAUDE_PLUGIN_ROOT in hooks/hooks.json" "$T" ERROR 1 "x-plugin/hooks/hooks.json"

T="$TMP_ROOT/b-other-var"
write_hooks "$T" "x-plugin/hooks.json" '"bash $CLAUDE_PLUGIN_ROOT_EXTRA/hooks/foo.sh"'
expect "(b) a different variable sharing the prefix is not flagged" "$T" OK 0 "ROOT_COMMANDS=0"

# --- (c) inline plugin.json hooks are scanned; quoting mid-argument counts ----
T="$TMP_ROOT/c-inline"
write_hooks "$T" "x-plugin/.claude-plugin/plugin.json" '"bash ${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh --flag"'
expect "(c) unquoted root in inline plugin.json hooks" "$T" ERROR 1 "x-plugin/.claude-plugin/plugin.json"

T="$TMP_ROOT/c-inline-ok"
write_hooks "$T" "x-plugin/.claude-plugin/plugin.json" '"python3 --x=\"${CLAUDE_PLUGIN_ROOT}\"/hooks/foo.py"'
expect "(c) root quoted mid-argument passes" "$T" OK 0

# --- (d) single quotes never expand: flagged as a different bug -------------
T="$TMP_ROOT/d-single"
write_hooks "$T" "x-plugin/hooks.json" "\"bash '\${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh'\""
expect "(d) single-quoted root is flagged" "$T" ERROR 1 "TYPE=single_quoted_plugin_root"

# --- (e) a backslash-escaped \$ is literal, not an expansion -----------------
T="$TMP_ROOT/e-escaped"
write_hooks "$T" "x-plugin/hooks.json" '"echo \\${CLAUDE_PLUGIN_ROOT} is set"'
expect "(e) escaped \\\$ is not flagged" "$T" OK 0

# --- (f) exec-form (args array) and prompt hooks are not shell-parsed --------
T="$TMP_ROOT/f-exec"
write_hooks "$T" "x-plugin/hooks.json" '"${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh"' ', "args": []'
expect "(f) exec-form handler is skipped" "$T" OK 0 "ROOT_COMMANDS=0"

T="$TMP_ROOT/f-prompt"
mkdir -p "$T/x-plugin"
printf '%s\n' '{"hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "prompt", "prompt": "read ${CLAUDE_PLUGIN_ROOT}/x"}]}]}}' \
  > "$T/x-plugin/hooks.json"
expect "(f) prompt hook text is not a command" "$T" OK 0 "ROOT_COMMANDS=0"

# --- (g) several findings: count, REASON suffix -------------------------------
T="$TMP_ROOT/g-many"
write_hooks "$T" "x-plugin/hooks.json" '"bash ${CLAUDE_PLUGIN_ROOT}/hooks/a.sh"'
write_hooks "$T" "y-plugin/.claude-plugin/plugin.json" '"bash ${CLAUDE_PLUGIN_ROOT}/hooks/b.sh"'
expect "(g) two files, two findings" "$T" ERROR 2 "(+1 more)"

# --- (h) zero-scan is an ERROR, not a silent OK ------------------------------
T="$TMP_ROOT/h-empty"
mkdir -p "$T/not-a-plugin-dir"
expect "(h) nothing scanned" "$T" ERROR 1 "TYPE=nothing_scanned"

# --- (i) the real tree is clean ----------------------------------------------
expect "(i) repo tree" "$REPO_ROOT" OK 0

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "OK: check-plugin-root-quoting regression tests passed"
