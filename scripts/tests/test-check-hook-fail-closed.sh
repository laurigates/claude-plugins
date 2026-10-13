#!/usr/bin/env bash
# Regression test for scripts/check-hook-fail-closed.sh.
#
# Claude Code 2.1.295's `"onFailure": "block"` turns a crashing hook into a
# block, so the guard asserts two things: the key sits on exactly the four
# hooks-plugin safety hooks, and those hooks exit 0 on their not-applicable
# paths. Every assertion EXECUTES the guard against a planted fixture tree and
# reads its verdict. Paired cases: each flagged shape sits beside the accepted
# one, so the suite fails an over-reporting guard and a permanently-silent one.
#
# Run: bash scripts/tests/test-check-hook-fail-closed.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-hook-fail-closed.sh"
CONTRACT="$REPO_ROOT/scripts/check-structured-output-contract.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP_ROOT="$(mktemp -d)"
if [ -z "$TMP_ROOT" ] || [ ! -d "$TMP_ROOT" ]; then echo "FAIL: mktemp -d failed"; exit 1; fi
trap 'rm -rf "$TMP_ROOT"' EXIT

field() { printf '%s\n' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# expect <label> <tree> <want-status> [<issue-type-in-output>]
expect() {
  local label="$1" tree="$2" want_status="$3" needle="${4:-}"
  local out rc want_rc=0
  out="$(bash "$GUARD" --project-dir "$tree" 2>&1)"; rc=$?
  [ "$want_status" = "OK" ] || want_rc=1
  if [ "$rc" -eq "$want_rc" ] && [ "$(field "$out" STATUS)" = "$want_status" ]; then
    pass "$label (STATUS=$want_status rc=$rc)"
  else
    fail "$label: want STATUS=$want_status rc=$want_rc, got rc=$rc:"
    printf '%s\n' "$out" | sed 's/^/    | /'
  fi
  if [ -n "$needle" ]; then
    if grep -qF -- "TYPE=$needle " <<<"$out"; then
      pass "$label: output names TYPE=$needle"
    else
      fail "$label: output lacks TYPE=$needle"
    fi
  fi
  if printf '%s\n' "$out" | bash "$CONTRACT" --validate - >/dev/null 2>&1; then
    pass "$label: output satisfies the structured-output contract"
  else
    fail "$label: output violates the structured-output contract"
  fi
}

# make_tree <dir> <python-mutation> [<stub-body>]
# Writes a hooks-plugin manifest with the five real-shaped registrations (the
# merge guard twice) plus one nudge, then applies <python-mutation> to `d`.
# Every hook script is a stub whose body is <stub-body> (default: exit 0).
make_tree() {
  local dir="$1" mutation="$2" body="${3:-exit 0}" s
  mkdir -p "$dir/hooks-plugin/.claude-plugin" "$dir/hooks-plugin/hooks"
  for s in branch-protection repo-deletion-safety external-pr-merge-guard secret-protection bash-antipatterns; do
    printf '#!/usr/bin/env bash\ncat >/dev/null\n%s\n' "$body" > "$dir/hooks-plugin/hooks/$s.sh"
  done
  MUTATION="$mutation" OUT="$dir/hooks-plugin/.claude-plugin/plugin.json" python3 - <<'PY'
import json, os
def h(name, fc=True):
    e = {"type": "command", "command": f'bash "${{CLAUDE_PLUGIN_ROOT}}/hooks/{name}.sh"', "timeout": 5}
    if fc:
        e["onFailure"] = "block"
    return e
d = {"name": "hooks-plugin", "hooks": {"PreToolUse": [
    {"matcher": "Bash", "hooks": [h("bash-antipatterns", False), h("branch-protection"),
                                  h("repo-deletion-safety"), h("external-pr-merge-guard")]},
    {"matcher": "mcp__github__merge_pull_request", "hooks": [h("external-pr-merge-guard")]},
    {"matcher": "Read|Edit|Write|Bash", "hooks": [h("secret-protection")]},
]}}
exec(os.environ["MUTATION"])
json.dump(d, open(os.environ["OUT"], "w"), indent=2)
PY
}

echo "== manifest =="
make_tree "$TMP_ROOT/good" "pass"
expect "four safety hooks fail closed, the nudge does not" "$TMP_ROOT/good" OK

make_tree "$TMP_ROOT/missing" "d['hooks']['PreToolUse'][2]['hooks'][0].pop('onFailure')"
expect "secret-protection without onFailure" "$TMP_ROOT/missing" ERROR missing_fail_closed

make_tree "$TMP_ROOT/second-reg" "d['hooks']['PreToolUse'][1]['hooks'][0].pop('onFailure')"
expect "merge guard's MCP registration without onFailure" "$TMP_ROOT/second-reg" ERROR missing_fail_closed

make_tree "$TMP_ROOT/continue" "d['hooks']['PreToolUse'][0]['hooks'][1]['onFailure'] = 'continue'"
expect "branch-protection set to continue" "$TMP_ROOT/continue" ERROR missing_fail_closed

make_tree "$TMP_ROOT/nudge" "d['hooks']['PreToolUse'][0]['hooks'][0]['onFailure'] = 'block'"
expect "a nudge set to fail closed" "$TMP_ROOT/nudge" ERROR unexpected_fail_closed

make_tree "$TMP_ROOT/nudge-continue" "d['hooks']['PreToolUse'][0]['hooks'][0]['onFailure'] = 'continue'"
expect "a nudge set to continue is accepted" "$TMP_ROOT/nudge-continue" OK

make_tree "$TMP_ROOT/badval" "d['hooks']['PreToolUse'][0]['hooks'][1]['onFailure'] = 'deny'"
expect "an onFailure value outside continue|block" "$TMP_ROOT/badval" ERROR invalid_onfailure_value

make_tree "$TMP_ROOT/unreg" "d['hooks']['PreToolUse'][0]['hooks'].pop(2)"
expect "repo-deletion-safety not registered" "$TMP_ROOT/unreg" ERROR safety_hook_not_registered

mkdir -p "$TMP_ROOT/other/x-plugin/hooks"
make_tree "$TMP_ROOT/other" "pass"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash x/hooks/branch-protection.sh","onFailure":"block"}]}]}}\n' \
  > "$TMP_ROOT/other/x-plugin/hooks/hooks.json"
expect "same script name in another plugin is not a safety hook" "$TMP_ROOT/other" ERROR unexpected_fail_closed

mkdir -p "$TMP_ROOT/empty"
expect "nothing scanned is an error, not OK" "$TMP_ROOT/empty" ERROR nothing_scanned

echo "== runtime =="
make_tree "$TMP_ROOT/crash" "pass" "exit 1"
expect "a hook exiting 1 on a not-applicable path" "$TMP_ROOT/crash" ERROR not_applicable_crash

make_tree "$TMP_ROOT/badjson" "pass" "echo '{not json'"
expect "a hook printing broken JSON" "$TMP_ROOT/badjson" ERROR invalid_json_output

make_tree "$TMP_ROOT/mapfile" "pass" 'mapfile -t X < /dev/null'
expect "a hook calling mapfile (bash 3.2)" "$TMP_ROOT/mapfile" ERROR not_applicable_crash

make_tree "$TMP_ROOT/needsjq" "pass" 'jq -n . >/dev/null'
expect "a hook calling jq without command -v" "$TMP_ROOT/needsjq" ERROR not_applicable_crash

make_tree "$TMP_ROOT/guarded" "pass" 'command -v jq >/dev/null 2>&1 || exit 0; jq -n . >/dev/null'
expect "a hook guarding jq with command -v" "$TMP_ROOT/guarded" OK

echo "== the real tree =="
expect "the repo's own hooks-plugin" "$REPO_ROOT" OK

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
