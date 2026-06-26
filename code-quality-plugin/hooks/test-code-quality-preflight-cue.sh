#!/usr/bin/env bash
# shellcheck disable=SC2317   # file-level: cq_invoke/cq_invoke_sid helpers are defined for reuse but not all called
# Regression tests for code-quality-preflight-cue.sh
# Run: bash code-quality-plugin/hooks/test-code-quality-preflight-cue.sh
set -uo pipefail

CQ_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CQ_SCRIPT="${CQ_SCRIPT_DIR}/code-quality-preflight-cue.sh"
CQ_PASS=0
CQ_FAIL=0

# Use a temp dir as the cache to isolate tests
CQ_TEST_CACHE_DIR="$(mktemp -d)"
trap 'rm -rf "$CQ_TEST_CACHE_DIR"' EXIT

cq_pass() { echo "PASS: $1"; CQ_PASS=$((CQ_PASS + 1)); }
cq_fail() { echo "FAIL: $1"; CQ_FAIL=$((CQ_FAIL + 1)); }

cq_invoke() {
  # Invoke the hook with a fresh session id (or passed one) and given JSON
  local cq_json="$1"
  CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" \
    bash "$CQ_SCRIPT" <<< "$cq_json"
}

cq_invoke_sid() {
  local cq_json="$1"
  local cq_sid="$2"
  CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" \
    bash "$CQ_SCRIPT" <<< "$cq_json"
}

# Helper: build test payload JSON
cq_payload() {
  local cq_tool="$1"
  local cq_file="$2"
  local cq_new_string="${3:-}"
  local cq_content="${4:-}"
  local cq_sid="${5:-test-session-$(date +%s%N)}"
  jq -n \
    --arg tool_name "$cq_tool" \
    --arg file_path "$cq_file" \
    --arg new_string "$cq_new_string" \
    --arg content "$cq_content" \
    --arg session_id "$cq_sid" \
    '{tool_name: $tool_name, tool_input: {file_path: $file_path, new_string: $new_string, content: $content}, session_id: $session_id}'
}

# --- (a) Public-symbol edit fires once, output contains cue text AND decision:block ---
echo "--- Test (a): public-symbol edit fires ---"
CQ_SID_A="test-sid-a-$(date +%s%N)"
CQ_PAYLOAD_A="$(cq_payload Edit /some/src/app.ts 'export function doThing() { return 1; }' '' "$CQ_SID_A")"
CQ_OUT_A="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_A")"
if echo "$CQ_OUT_A" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(a) decision:block present"
else
  cq_fail "(a) decision:block missing; got: $CQ_OUT_A"
fi
if echo "$CQ_OUT_A" | jq -e '.reason' | grep -q "code-quality"; then
  cq_pass "(a) reason contains [code-quality]"
else
  cq_fail "(a) reason missing [code-quality]; got: $CQ_OUT_A"
fi

# --- (b) Manifest filename fires ---
echo "--- Test (b): manifest filename (plugin.json) fires ---"
CQ_SID_B="test-sid-b-$(date +%s%N)"
CQ_PAYLOAD_B="$(cq_payload Edit /repo/myplugin/.claude-plugin/plugin.json 'trivial change' '' "$CQ_SID_B")"
CQ_OUT_B="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_B")"
if echo "$CQ_OUT_B" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(b) plugin.json edit fires"
else
  cq_fail "(b) plugin.json edit did not fire; got: $CQ_OUT_B"
fi

# --- (c) >=50 lines fires, <50 lines trivial edit is silent ---
# Fixtures use a lintable source extension (.py) — Signal 3 only fires for file
# types /code-quality:code-lint can act on (issue #1825). The payload is plain
# "line" repeats with no public symbols, so Signal 2 stays quiet and this isolates
# the line-count threshold itself.
echo "--- Test (c): 50-line payload fires ---"
CQ_SID_C1="test-sid-c1-$(date +%s%N)"
# Generate 50 lines of content (no public symbols, not a manifest)
CQ_50LINES="$(printf 'line\n%.0s' {1..50})"
CQ_PAYLOAD_C1="$(cq_payload Edit /repo/src/helpers.py '' "$CQ_50LINES" "$CQ_SID_C1")"
CQ_OUT_C1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_C1")"
if echo "$CQ_OUT_C1" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(c) 50-line payload fires"
else
  cq_fail "(c) 50-line payload did not fire; got: $CQ_OUT_C1"
fi

echo "--- Test (c): <50 lines trivial edit is silent ---"
CQ_SID_C2="test-sid-c2-$(date +%s%N)"
CQ_SMALL="$(printf 'line\n%.0s' {1..10})"
CQ_PAYLOAD_C2="$(cq_payload Edit /repo/src/helpers.py '' "$CQ_SMALL" "$CQ_SID_C2")"
CQ_OUT_C2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_C2")"
if [ -z "$CQ_OUT_C2" ]; then
  cq_pass "(c) trivial small edit is silent"
else
  cq_fail "(c) trivial small edit should be silent; got: $CQ_OUT_C2"
fi

# --- (d) .md / test-file / lockfile edits are silent ---
echo "--- Test (d): .md file is silent ---"
CQ_SID_D1="test-sid-d1-$(date +%s%N)"
CQ_PAYLOAD_D1="$(cq_payload Edit /repo/README.md 'export function big() {}' '' "$CQ_SID_D1")"
CQ_OUT_D1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_D1")"
if [ -z "$CQ_OUT_D1" ]; then
  cq_pass "(d) .md edit is silent"
else
  cq_fail "(d) .md edit should be silent; got: $CQ_OUT_D1"
fi

echo "--- Test (d): test file is silent ---"
CQ_SID_D2="test-sid-d2-$(date +%s%N)"
CQ_PAYLOAD_D2="$(cq_payload Edit /repo/src/app.test.ts 'export function doThing() { return 1; }' '' "$CQ_SID_D2")"
CQ_OUT_D2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_D2")"
if [ -z "$CQ_OUT_D2" ]; then
  cq_pass "(d) test file edit is silent"
else
  cq_fail "(d) test file edit should be silent; got: $CQ_OUT_D2"
fi

echo "--- Test (d): lockfile is silent ---"
CQ_SID_D3="test-sid-d3-$(date +%s%N)"
CQ_PAYLOAD_D3="$(cq_payload Edit /repo/package-lock.json 'export function doThing() { return 1; }' '' "$CQ_SID_D3")"
CQ_OUT_D3="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_D3")"
if [ -z "$CQ_OUT_D3" ]; then
  cq_pass "(d) lockfile edit is silent"
else
  cq_fail "(d) lockfile edit should be silent; got: $CQ_OUT_D3"
fi

# --- (i) diagram/binary files are silent even for large payloads (issue #1730) ---
echo "--- Test (i): 60-line .d2 diagram edit is silent ---"
CQ_SID_I1="test-sid-i1-$(date +%s%N)"
CQ_60LINES="$(printf 'line\n%.0s' {1..60})"
CQ_PAYLOAD_I1="$(cq_payload Write /repo/docs/diagrams/flow.d2 '' "$CQ_60LINES" "$CQ_SID_I1")"
CQ_OUT_I1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_I1")"
if [ -z "$CQ_OUT_I1" ]; then
  cq_pass "(i) 60-line .d2 edit is silent"
else
  cq_fail "(i) 60-line .d2 edit should be silent; got: $CQ_OUT_I1"
fi

echo "--- Test (i): .svg artifact edit is silent ---"
CQ_SID_I2="test-sid-i2-$(date +%s%N)"
CQ_PAYLOAD_I2="$(cq_payload Edit /repo/docs/diagrams/flow.svg '' "$CQ_60LINES" "$CQ_SID_I2")"
CQ_OUT_I2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_I2")"
if [ -z "$CQ_OUT_I2" ]; then
  cq_pass "(i) .svg edit is silent"
else
  cq_fail "(i) .svg edit should be silent; got: $CQ_OUT_I2"
fi

# --- (e) fire-once dedup: second structural edit with marker present is silent ---
echo "--- Test (e): fire-once dedup ---"
CQ_SID_E="test-sid-e-fixed"
CQ_PAYLOAD_E="$(cq_payload Edit /repo/src/app.ts 'export function doThing() { return 1; }' '' "$CQ_SID_E")"
# First call should fire
CQ_OUT_E1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_E")"
# Second call with same session id should be silent
CQ_OUT_E2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_E")"
if echo "$CQ_OUT_E1" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(e) first call fires"
else
  cq_fail "(e) first call did not fire; got: $CQ_OUT_E1"
fi
if [ -z "$CQ_OUT_E2" ]; then
  cq_pass "(e) second call is silent (dedup)"
else
  cq_fail "(e) second call should be silent; got: $CQ_OUT_E2"
fi

# --- (f) empty session_id does not crash and still emits ---
echo "--- Test (f): empty session_id does not crash ---"
CQ_PAYLOAD_F="$(jq -n --arg tool_name Edit --arg file_path /repo/src/app.ts --arg new_string 'export function doThing() { return 1; }' \
  '{tool_name: $tool_name, tool_input: {file_path: $file_path, new_string: $new_string}}')"
CQ_EXIT_F=0
CQ_OUT_F="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_F")" || CQ_EXIT_F=$?
if [ "$CQ_EXIT_F" -eq 0 ]; then
  cq_pass "(f) empty session_id exits 0"
else
  cq_fail "(f) empty session_id crashed with exit $CQ_EXIT_F"
fi
if echo "$CQ_OUT_F" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(f) empty session_id still emits cue"
else
  cq_fail "(f) empty session_id should still emit; got: $CQ_OUT_F"
fi

# --- (g) JSON field name 'decision' is pinned ---
echo "--- Test (g): decision field name is pinned ---"
CQ_SID_G="test-sid-g-$(date +%s%N)"
CQ_PAYLOAD_G="$(cq_payload Edit /repo/src/app.ts 'export function doThing() { return 1; }' '' "$CQ_SID_G")"
CQ_OUT_G="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_G")"
if echo "$CQ_OUT_G" | jq -e 'has("decision")' > /dev/null 2>&1; then
  cq_pass "(g) 'decision' field is present"
else
  cq_fail "(g) 'decision' field missing; got: $CQ_OUT_G"
fi
if echo "$CQ_OUT_G" | jq -e 'has("reason")' > /dev/null 2>&1; then
  cq_pass "(g) 'reason' field is present"
else
  cq_fail "(g) 'reason' field missing; got: $CQ_OUT_G"
fi

# --- (h) CODE_QUALITY_SKIP_HOOKS=1 is a no-op ---
echo "--- Test (h): CODE_QUALITY_SKIP_HOOKS=1 silences all ---"
CQ_SID_H="test-sid-h-$(date +%s%N)"
CQ_PAYLOAD_H="$(cq_payload Edit /repo/src/app.ts 'export function doThing() { return 1; }' '' "$CQ_SID_H")"
CQ_OUT_H="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" CODE_QUALITY_SKIP_HOOKS=1 bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_H")"
if [ -z "$CQ_OUT_H" ]; then
  cq_pass "(h) CODE_QUALITY_SKIP_HOOKS=1 silences hook"
else
  cq_fail "(h) CODE_QUALITY_SKIP_HOOKS=1 should silence; got: $CQ_OUT_H"
fi

# --- (j) shell script with only an `export` line is silent (<50 lines) (issue #1766) ---
echo "--- Test (j): small shell wrapper with export is silent ---"
CQ_SID_J1="test-sid-j1-$(date +%s%N)"
CQ_PAYLOAD_J1="$(cq_payload Write /home/user/.routines/fvh-triage.sh 'export EDITOR=nvim
my-tool run --once' '' "$CQ_SID_J1")"
CQ_OUT_J1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_J1")"
if [ -z "$CQ_OUT_J1" ]; then
  cq_pass "(j) small shell wrapper with export is silent"
else
  cq_fail "(j) small shell wrapper should be silent; got: $CQ_OUT_J1"
fi

echo "--- Test (j): large (>=50 line) shell script still fires ---"
CQ_SID_J2="test-sid-j2-$(date +%s%N)"
CQ_SHELL_BIG="$(printf 'echo line\n%.0s' {1..55})"
CQ_PAYLOAD_J2="$(cq_payload Write /home/user/scripts/big.sh '' "$CQ_SHELL_BIG" "$CQ_SID_J2")"
CQ_OUT_J2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_J2")"
if echo "$CQ_OUT_J2" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(j) large shell script fires on Signal 3"
else
  cq_fail "(j) large shell script should fire; got: $CQ_OUT_J2"
fi

# --- (k) evaluate-skill clause is conditional on a skills/ path (issue #1766) ---
echo "--- Test (k): non-skill edit omits /evaluate:evaluate-skill ---"
CQ_SID_K1="test-sid-k1-$(date +%s%N)"
CQ_PAYLOAD_K1="$(cq_payload Edit /repo/src/app.ts 'export function doThing() { return 1; }' '' "$CQ_SID_K1")"
CQ_OUT_K1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_K1")"
if echo "$CQ_OUT_K1" | jq -r '.reason' | grep -q "evaluate-skill"; then
  cq_fail "(k) non-skill edit should NOT mention evaluate-skill; got: $CQ_OUT_K1"
else
  cq_pass "(k) non-skill edit omits evaluate-skill"
fi

echo "--- Test (k): skills/ path edit includes /evaluate:evaluate-skill ---"
CQ_SID_K2="test-sid-k2-$(date +%s%N)"
CQ_PAYLOAD_K2="$(cq_payload Write /repo/my-plugin/skills/foo/scripts/helper.py 'def run(): pass' '' "$CQ_SID_K2")"
CQ_OUT_K2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_K2")"
if echo "$CQ_OUT_K2" | jq -r '.reason' | grep -q "evaluate-skill"; then
  cq_pass "(k) skills/ path edit mentions evaluate-skill"
else
  cq_fail "(k) skills/ path edit should mention evaluate-skill; got: $CQ_OUT_K2"
fi

# --- (l) config/data/IaC files >=50 lines are silent (issue #1825) ---
# /code-quality:code-lint has no linter for YAML/JSON/TOML/HCL/Terraform, so a
# large config write must NOT trip Signal 3 (the large-payload signal) — the cue
# would point at a skill that does nothing for the file. Signals 1 (manifest
# basenames) and 2 (code symbols) are unaffected and still fire.
CQ_60LINES_L="$(printf 'key: value\n%.0s' {1..60})"

echo "--- Test (l): 60-line ArgoCD-style .yaml is silent ---"
CQ_SID_L1="test-sid-l1-$(date +%s%N)"
CQ_PAYLOAD_L1="$(cq_payload Write /repo/argocd/applicationsets/fe-app.yaml '' "$CQ_60LINES_L" "$CQ_SID_L1")"
CQ_OUT_L1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_L1")"
if [ -z "$CQ_OUT_L1" ]; then
  cq_pass "(l) large .yaml config edit is silent"
else
  cq_fail "(l) large .yaml config edit should be silent; got: $CQ_OUT_L1"
fi

echo "--- Test (l): 60-line Terraform .tf is silent ---"
CQ_SID_L2="test-sid-l2-$(date +%s%N)"
CQ_PAYLOAD_L2="$(cq_payload Write /repo/infra/main.tf '' "$CQ_60LINES_L" "$CQ_SID_L2")"
CQ_OUT_L2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_L2")"
if [ -z "$CQ_OUT_L2" ]; then
  cq_pass "(l) large .tf config edit is silent"
else
  cq_fail "(l) large .tf config edit should be silent; got: $CQ_OUT_L2"
fi

echo "--- Test (l): large non-manifest .json data file is silent ---"
CQ_SID_L3="test-sid-l3-$(date +%s%N)"
CQ_PAYLOAD_L3="$(cq_payload Write /repo/data/fixtures.json '' "$CQ_60LINES_L" "$CQ_SID_L3")"
CQ_OUT_L3="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_L3")"
if [ -z "$CQ_OUT_L3" ]; then
  cq_pass "(l) large .json data file is silent"
else
  cq_fail "(l) large .json data file should be silent; got: $CQ_OUT_L3"
fi

echo "--- Test (l): manifest .json (package.json) still fires via Signal 1 ---"
CQ_SID_L4="test-sid-l4-$(date +%s%N)"
CQ_PAYLOAD_L4="$(cq_payload Write /repo/package.json '' "$CQ_60LINES_L" "$CQ_SID_L4")"
CQ_OUT_L4="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_L4")"
if echo "$CQ_OUT_L4" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(l) package.json still fires via Signal 1"
else
  cq_fail "(l) package.json should still fire via Signal 1; got: $CQ_OUT_L4"
fi

echo "--- Test (l): .yaml with a code symbol still fires via Signal 2 ---"
CQ_SID_L5="test-sid-l5-$(date +%s%N)"
CQ_PAYLOAD_L5="$(cq_payload Write /repo/config/app.yaml 'export default config' '' "$CQ_SID_L5")"
CQ_OUT_L5="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_L5")"
if echo "$CQ_OUT_L5" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(l) .yaml with code symbol still fires via Signal 2"
else
  cq_fail "(l) .yaml with code symbol should fire via Signal 2; got: $CQ_OUT_L5"
fi

# --- Summary ---
echo ""
echo "=== RESULTS ==="
echo "PASS: $CQ_PASS"
echo "FAIL: $CQ_FAIL"
if [ "$CQ_FAIL" -eq 0 ]; then
  echo "STATUS=OK"
  exit 0
else
  echo "STATUS=ERROR"
  exit 1
fi
