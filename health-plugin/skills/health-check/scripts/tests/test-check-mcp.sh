#!/usr/bin/env bash
# Regression test for check-mcp.sh ancestor .mcp.json discovery (issue #2666).
# Claude Code also loads .mcp.json from directories above the project, so the
# check must walk from --project-dir up through its ancestors, stopping after
# --home-dir or the filesystem root, and must report the source file of every
# server it finds. Before the fix a parent-only layout reported SERVER_COUNT=0
# and STATUS=N_A while servers were in fact configured.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-mcp.sh"
contract_script="${script_dir}/../../../../../scripts/check-structured-output-contract.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

# assert_contract <label> <output>: the block satisfies the structured-output
# contract (canonical STATUS, ISSUE_COUNT = ISSUES rows, REASON iff non-OK).
assert_contract() {
  [ -f "$contract_script" ] || fail "contract checker not found at $contract_script"
  bash "$contract_script" --validate - <<<"$2" >/dev/null \
    || fail "$1: structured-output contract violated:\n$2"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-mcp tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-mcp.sh not found at $check_script"

tmp_root="$(mktemp -d)" || fail "mktemp -d failed"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  fail "mktemp -d returned no directory"
fi
trap 'rm -rf "$tmp_root"' EXIT
# Canonicalise: check-mcp.sh resolves --home-dir/--project-dir with `pwd -P`
# and reports physical paths, so on macOS (mktemp returns /var/folders/…, a
# symlink to /private/var/folders/…) every file= assertion built from the
# unresolved path fails, and Case F's negative grep passes vacuously.
tmp_root="$(cd -P -- "$tmp_root" && pwd -P)" || fail "cannot resolve $tmp_root"

# Every fixture lives INSIDE its own fake home so the walk's stop-at-home
# condition terminates the climb; the test never depends on whether a stray
# /tmp/.mcp.json or /.mcp.json exists on the runner.
new_home() {
  local fixture_home="${tmp_root}/$1"
  mkdir -p "$fixture_home"
  printf '%s' "$fixture_home"
}

# Two servers, both with a command that is guaranteed present, so STATUS is not
# perturbed by missing_command warnings.
write_two_servers() {
  cat > "$1" <<'JSON'
{
  "mcpServers": {
    "podio-mcp": { "command": "bash", "args": ["-c", "true"] },
    "github": { "command": "bash" }
  }
}
JSON
}

# -----------------------------------------------------------------------------
# Case A: the issue's repro — parent-only .mcp.json, project is the child dir
# -----------------------------------------------------------------------------
home_a="$(new_home home_a)"
mkdir -p "${home_a}/ws/child"
write_two_servers "${home_a}/ws/.mcp.json"

out_a="$(bash "$check_script" --home-dir "$home_a" --project-dir "${home_a}/ws/child")"
grep -q "^MCP_CONFIGURED=true$" <<<"$out_a" \
  || fail "parent-only layout must report MCP_CONFIGURED=true, got:\n$out_a"
grep -q "^SERVER_COUNT=2$" <<<"$out_a" \
  || fail "parent-only layout must report SERVER_COUNT=2, got:\n$out_a"
grep -q "^STATUS=OK$" <<<"$out_a" \
  || fail "parent-only layout must report STATUS=OK:\n$out_a"
grep -q "^CONFIGURED=true$" <<<"$out_a" \
  || fail "parent-only layout must report CONFIGURED=true:\n$out_a"
assert_contract "case A" "$out_a"
grep -q "SERVER: name=podio-mcp file=${home_a}/ws/.mcp.json" <<<"$out_a" \
  || fail "expected podio-mcp attributed to ${home_a}/ws/.mcp.json, got:\n$out_a"
grep -q "SERVER: name=github file=${home_a}/ws/.mcp.json" <<<"$out_a" \
  || fail "expected github attributed to ${home_a}/ws/.mcp.json, got:\n$out_a"
grep -q "^MCP_SOURCE_COUNT=[1-9]" <<<"$out_a" \
  || fail "expected a non-zero MCP_SOURCE_COUNT denominator, got:\n$out_a"
pass "ancestor .mcp.json is discovered and each server reports its source file"

# -----------------------------------------------------------------------------
# Case B: no .mcp.json anywhere under the fake home → STATUS=OK with
# CONFIGURED=false (formerly the non-canonical STATUS=N_A, #3580)
# -----------------------------------------------------------------------------
home_b="$(new_home home_b)"
mkdir -p "${home_b}/ws/child"

out_b="$(bash "$check_script" --home-dir "$home_b" --project-dir "${home_b}/ws/child")"
grep -q "^SERVER_COUNT=0$" <<<"$out_b" \
  || fail "no config anywhere must report SERVER_COUNT=0, got:\n$out_b"
grep -q "^STATUS=OK$" <<<"$out_b" \
  || fail "no config anywhere must report STATUS=OK, got:\n$out_b"
grep -q "^CONFIGURED=false$" <<<"$out_b" \
  || fail "no config anywhere must report CONFIGURED=false, got:\n$out_b"
grep -q "^MCP_CONFIGURED=false$" <<<"$out_b" \
  || fail "no config anywhere must report MCP_CONFIGURED=false, got:\n$out_b"
assert_contract "case B" "$out_b"
pass "walk does not invent servers when no .mcp.json exists"

# -----------------------------------------------------------------------------
# Case C: project-level .mcp.json only → unchanged behaviour, project source
# -----------------------------------------------------------------------------
home_c="$(new_home home_c)"
mkdir -p "${home_c}/ws/child"
write_two_servers "${home_c}/ws/child/.mcp.json"

out_c="$(bash "$check_script" --home-dir "$home_c" --project-dir "${home_c}/ws/child")"
grep -q "^SERVER_COUNT=2$" <<<"$out_c" \
  || fail "project-level config must still report SERVER_COUNT=2, got:\n$out_c"
grep -q "SERVER: name=github file=${home_c}/ws/child/.mcp.json" <<<"$out_c" \
  || fail "expected github attributed to the project file, got:\n$out_c"
pass "project-level .mcp.json keeps working and reports the project file"

# -----------------------------------------------------------------------------
# Case D: home-level .mcp.json only, project deeper under home → no regression
# -----------------------------------------------------------------------------
home_d="$(new_home home_d)"
mkdir -p "${home_d}/ws/child"
write_two_servers "${home_d}/.mcp.json"

out_d="$(bash "$check_script" --home-dir "$home_d" --project-dir "${home_d}/ws/child")"
grep -q "^SERVER_COUNT=2$" <<<"$out_d" \
  || fail "home-level config must still report SERVER_COUNT=2, got:\n$out_d"
grep -q "SERVER: name=github file=${home_d}/.mcp.json" <<<"$out_d" \
  || fail "expected github attributed to the home file, got:\n$out_d"
pass "home-level .mcp.json remains covered by the walk"

# -----------------------------------------------------------------------------
# Case E: same server name in parent and child → counted once, nearest wins,
#         outer copy reported as shadowed
# -----------------------------------------------------------------------------
home_e="$(new_home home_e)"
mkdir -p "${home_e}/ws/child"
write_two_servers "${home_e}/ws/.mcp.json"
cat > "${home_e}/ws/child/.mcp.json" <<'JSON'
{ "mcpServers": { "github": { "command": "bash", "args": ["nearer"] } } }
JSON

out_e="$(bash "$check_script" --home-dir "$home_e" --project-dir "${home_e}/ws/child")"
grep -q "^SERVER_COUNT=2$" <<<"$out_e" \
  || fail "duplicate server name must be counted once (expected 2), got:\n$out_e"
grep -q "SERVER: name=github file=${home_e}/ws/child/.mcp.json" <<<"$out_e" \
  || fail "nearest file must own the duplicated server name, got:\n$out_e"
grep -q "SERVER_SHADOWED: name=github file=${home_e}/ws/.mcp.json shadowed_by=${home_e}/ws/child/.mcp.json" <<<"$out_e" \
  || fail "expected a SERVER_SHADOWED line naming the outer file, got:\n$out_e"
pass "duplicate server names are counted once and the shadowed copy is reported"

# -----------------------------------------------------------------------------
# Case F: a .mcp.json ABOVE --home-dir is not picked up (pins the stop condition)
# -----------------------------------------------------------------------------
above_f="${tmp_root}/above_f"
home_f="$(new_home above_f/home_f)"
mkdir -p "${home_f}/ws/child"
write_two_servers "${above_f}/.mcp.json"

out_f="$(bash "$check_script" --home-dir "$home_f" --project-dir "${home_f}/ws/child")"
grep -q "FILE=${above_f}/.mcp.json" <<<"$out_f" \
  && fail "walk must stop at --home-dir and not read ${above_f}/.mcp.json:\n$out_f"
grep -q "^SERVER_COUNT=0$" <<<"$out_f" \
  || fail "config above --home-dir must not be counted, got:\n$out_f"
pass "walk stops at --home-dir"

# -----------------------------------------------------------------------------
# Case G: invalid JSON in an ancestor goes through the same validation path as a
# project/home file — it is read, reported VALID=false, and raises an
# invalid_json issue naming the ancestor path.
# The server_count==0 branch used to overwrite the ERROR with N_A; it now
# keeps the ERROR and only adds CONFIGURED=false (#3580).
# -----------------------------------------------------------------------------
home_g="$(new_home home_g)"
mkdir -p "${home_g}/ws/child"
printf '{ "mcpServers": ' > "${home_g}/ws/.mcp.json"

out_g="$(bash "$check_script" --home-dir "$home_g" --project-dir "${home_g}/ws/child")"
grep -q "FILE=${home_g}/ws/.mcp.json EXISTS=true" <<<"$out_g" \
  || fail "ancestor file must be read by the walk, got:\n$out_g"
grep -q "SEVERITY=ERROR TYPE=invalid_json FILE=${home_g}/ws/.mcp.json" <<<"$out_g" \
  || fail "expected invalid_json issue naming the ancestor file, got:\n$out_g"
grep -q "^ISSUE_COUNT=1$" <<<"$out_g" \
  || fail "expected ISSUE_COUNT=1 for the malformed ancestor file, got:\n$out_g"
grep -q "^STATUS=ERROR$" <<<"$out_g" \
  || fail "an invalid .mcp.json with no servers must stay STATUS=ERROR, got:\n$out_g"
grep -q "^REASON=invalid_json: " <<<"$out_g" \
  || fail "expected REASON=invalid_json: ..., got:\n$out_g"
assert_contract "case G" "$out_g"
pass "ancestor files are validated like project and home files"

# -----------------------------------------------------------------------------
# Case H (issue #3320): enabledMcpjsonServers is an array of server names.
# --verbose must list each name, not array indices (`ENABLED: 0=pal`).
# -----------------------------------------------------------------------------
home_h="$(new_home home_h)"
mkdir -p "${home_h}/.claude" "${home_h}/ws/child"
cat > "${home_h}/.claude/settings.json" <<'JSON'
{ "enabledMcpjsonServers": ["pal", "context7"] }
JSON

out_h="$(bash "$check_script" --home-dir "$home_h" --project-dir "${home_h}/ws/child" --verbose)"
grep -q "^ENABLED_MCP_SERVERS_IN=.claude/settings.json COUNT=2$" <<<"$out_h" \
  || fail "two enabled servers must report COUNT=2, got:\n$out_h"
grep -q "^  ENABLED: pal$" <<<"$out_h" \
  || fail "expected '  ENABLED: pal' in verbose output, got:\n$out_h"
grep -q "^  ENABLED: context7$" <<<"$out_h" \
  || fail "expected '  ENABLED: context7' in verbose output, got:\n$out_h"
grep -q "ENABLED: 0=" <<<"$out_h" \
  && fail "verbose output must not print array indices (ENABLED: 0=…):\n$out_h"
pass "enabledMcpjsonServers is read as an array of server names"

# -----------------------------------------------------------------------------
# Case I (#3580): WARN findings carry REASON= naming the first one, with the
# (+N more) tail, and the block passes the contract validator.
# -----------------------------------------------------------------------------
home_i="$(new_home home_i)"
mkdir -p "${home_i}/ws"
cat > "${home_i}/ws/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "ghost": { "command": "definitely-not-a-real-command-3580" },
    "needs-env": { "command": "bash", "env": { "MCP_TEST_UNSET_VAR_3580": "" } }
  }
}
JSON
out_i="$(MCP_TEST_UNSET_VAR_3580='' bash "$check_script" --home-dir "$home_i" --project-dir "${home_i}/ws")"
grep -q "^STATUS=WARN$" <<<"$out_i" || fail "expected STATUS=WARN, got:\n$out_i"
grep -q "^REASON=missing_command: .* (+1 more)$" <<<"$out_i" \
  || fail "expected REASON=missing_command: ... (+1 more), got:\n$out_i"
assert_contract "case I" "$out_i"
pass "WARN findings carry REASON= and satisfy the output contract"

echo "ALL TESTS PASSED"
