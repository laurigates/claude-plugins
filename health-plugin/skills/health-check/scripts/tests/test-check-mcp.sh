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

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-mcp tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-mcp.sh not found at $check_script"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

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
echo "$out_a" | grep -q "^MCP_CONFIGURED=true$" \
  || fail "parent-only layout must report MCP_CONFIGURED=true, got:\n$out_a"
echo "$out_a" | grep -q "^SERVER_COUNT=2$" \
  || fail "parent-only layout must report SERVER_COUNT=2, got:\n$out_a"
echo "$out_a" | grep -q "^STATUS=N_A$" \
  && fail "parent-only layout must not report STATUS=N_A:\n$out_a"
echo "$out_a" | grep -q "SERVER: name=podio-mcp file=${home_a}/ws/.mcp.json" \
  || fail "expected podio-mcp attributed to ${home_a}/ws/.mcp.json, got:\n$out_a"
echo "$out_a" | grep -q "SERVER: name=github file=${home_a}/ws/.mcp.json" \
  || fail "expected github attributed to ${home_a}/ws/.mcp.json, got:\n$out_a"
echo "$out_a" | grep -q "^MCP_SOURCE_COUNT=[1-9]" \
  || fail "expected a non-zero MCP_SOURCE_COUNT denominator, got:\n$out_a"
pass "ancestor .mcp.json is discovered and each server reports its source file"

# -----------------------------------------------------------------------------
# Case B: no .mcp.json anywhere under the fake home → still N_A (denominator)
# -----------------------------------------------------------------------------
home_b="$(new_home home_b)"
mkdir -p "${home_b}/ws/child"

out_b="$(bash "$check_script" --home-dir "$home_b" --project-dir "${home_b}/ws/child")"
echo "$out_b" | grep -q "^SERVER_COUNT=0$" \
  || fail "no config anywhere must report SERVER_COUNT=0, got:\n$out_b"
echo "$out_b" | grep -q "^STATUS=N_A$" \
  || fail "no config anywhere must report STATUS=N_A, got:\n$out_b"
echo "$out_b" | grep -q "^MCP_CONFIGURED=false$" \
  || fail "no config anywhere must report MCP_CONFIGURED=false, got:\n$out_b"
pass "walk does not invent servers when no .mcp.json exists"

# -----------------------------------------------------------------------------
# Case C: project-level .mcp.json only → unchanged behaviour, project source
# -----------------------------------------------------------------------------
home_c="$(new_home home_c)"
mkdir -p "${home_c}/ws/child"
write_two_servers "${home_c}/ws/child/.mcp.json"

out_c="$(bash "$check_script" --home-dir "$home_c" --project-dir "${home_c}/ws/child")"
echo "$out_c" | grep -q "^SERVER_COUNT=2$" \
  || fail "project-level config must still report SERVER_COUNT=2, got:\n$out_c"
echo "$out_c" | grep -q "SERVER: name=github file=${home_c}/ws/child/.mcp.json" \
  || fail "expected github attributed to the project file, got:\n$out_c"
pass "project-level .mcp.json keeps working and reports the project file"

# -----------------------------------------------------------------------------
# Case D: home-level .mcp.json only, project deeper under home → no regression
# -----------------------------------------------------------------------------
home_d="$(new_home home_d)"
mkdir -p "${home_d}/ws/child"
write_two_servers "${home_d}/.mcp.json"

out_d="$(bash "$check_script" --home-dir "$home_d" --project-dir "${home_d}/ws/child")"
echo "$out_d" | grep -q "^SERVER_COUNT=2$" \
  || fail "home-level config must still report SERVER_COUNT=2, got:\n$out_d"
echo "$out_d" | grep -q "SERVER: name=github file=${home_d}/.mcp.json" \
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
echo "$out_e" | grep -q "^SERVER_COUNT=2$" \
  || fail "duplicate server name must be counted once (expected 2), got:\n$out_e"
echo "$out_e" | grep -q "SERVER: name=github file=${home_e}/ws/child/.mcp.json" \
  || fail "nearest file must own the duplicated server name, got:\n$out_e"
echo "$out_e" | grep -q "SERVER_SHADOWED: name=github file=${home_e}/ws/.mcp.json shadowed_by=${home_e}/ws/child/.mcp.json" \
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
echo "$out_f" | grep -q "FILE=${above_f}/.mcp.json" \
  && fail "walk must stop at --home-dir and not read ${above_f}/.mcp.json:\n$out_f"
echo "$out_f" | grep -q "^SERVER_COUNT=0$" \
  || fail "config above --home-dir must not be counted, got:\n$out_f"
pass "walk stops at --home-dir"

# -----------------------------------------------------------------------------
# Case G: invalid JSON in an ancestor goes through the same validation path as a
# project/home file — it is read, reported VALID=false, and raises an
# invalid_json issue naming the ancestor path.
# (STATUS is deliberately not asserted here: check-mcp.sh has a pre-existing,
# out-of-scope quirk where the server_count==0 branch overwrites check_status
# with N_A, which predates and is independent of the ancestor walk.)
# -----------------------------------------------------------------------------
home_g="$(new_home home_g)"
mkdir -p "${home_g}/ws/child"
printf '{ "mcpServers": ' > "${home_g}/ws/.mcp.json"

out_g="$(bash "$check_script" --home-dir "$home_g" --project-dir "${home_g}/ws/child")"
echo "$out_g" | grep -q "FILE=${home_g}/ws/.mcp.json EXISTS=true" \
  || fail "ancestor file must be read by the walk, got:\n$out_g"
echo "$out_g" | grep -q "SEVERITY=ERROR TYPE=invalid_json FILE=${home_g}/ws/.mcp.json" \
  || fail "expected invalid_json issue naming the ancestor file, got:\n$out_g"
echo "$out_g" | grep -q "^ISSUE_COUNT=1$" \
  || fail "expected ISSUE_COUNT=1 for the malformed ancestor file, got:\n$out_g"
pass "ancestor files are validated like project and home files"

echo "ALL TESTS PASSED"
