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
# GUARD INTEGRITY (issue #2272 follow-up): every invocation here pins
# CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL=0, which makes the sequence-debounce
# layer inert. Without that pin these assertions are VACUOUS — repeat edits to
# the same file are silenced by the debounce whether or not the once-per-session
# dedup exists, so deleting the entire dedup block still passes. Proven: with the
# pin, deleting the dedup block from the hook turns (e) red; without it, green.
echo "--- Test (e): fire-once dedup ---"
CQ_SID_E="test-sid-e-fixed"
CQ_PAYLOAD_E="$(cq_payload Edit /repo/src/app.ts 'export function doThing() { return 1; }' '' "$CQ_SID_E")"
# First call should fire
CQ_OUT_E1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL=0 bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_E")"
# Second call with same session id should be silent
CQ_OUT_E2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL=0 bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_E")"
# Third call: same session, a DIFFERENT (never-touched, so never-debounced) file.
# The dedup is session-wide, so this must be silent too — and no per-file
# mechanism can explain that silence.
CQ_PAYLOAD_E3="$(cq_payload Edit /repo/src/dedup-other.ts 'export function other() { return 2; }' '' "$CQ_SID_E")"
CQ_OUT_E3="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL=0 bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_E3")"
if echo "$CQ_OUT_E1" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(e) first call fires"
else
  cq_fail "(e) first call did not fire; got: $CQ_OUT_E1"
fi
if [ -z "$CQ_OUT_E2" ]; then
  cq_pass "(e) second call is silent (dedup, debounce pinned off)"
else
  cq_fail "(e) second call should be silent; got: $CQ_OUT_E2"
fi
if [ -z "$CQ_OUT_E3" ]; then
  cq_pass "(e) dedup is session-wide: a different file in the same session is silent"
else
  cq_fail "(e) different file in same session should be silent; got: $CQ_OUT_E3"
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

# --- (m) session-scratchpad / harness-temp throwaways are silent (issue #1905) ---
# One-off analysis scripts the harness writes under a per-session scratchpad
# (or its temp root) are never committed, so the cue is pure noise there. Cover
# the `*/scratchpad/*` segment, both harness session-temp roots (/tmp and the
# macOS /private/tmp symlink), and confirm a genuine repo path still fires so the
# exclusion is not over-broad.
CQ_60LINES_M="$(printf 'x = 1\n%.0s' {1..60})"

echo "--- Test (m): 60-line .py under a scratchpad segment is silent ---"
CQ_SID_M1="test-sid-m1-$(date +%s%N)"
CQ_PAYLOAD_M1="$(cq_payload Write /private/tmp/claude-502/abc-uid/scratchpad/survey.py '' "$CQ_60LINES_M" "$CQ_SID_M1")"
CQ_OUT_M1="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_M1")"
if [ -z "$CQ_OUT_M1" ]; then
  cq_pass "(m) large .py under scratchpad/ is silent"
else
  cq_fail "(m) large .py under scratchpad/ should be silent; got: $CQ_OUT_M1"
fi

echo "--- Test (m): .py with a public symbol under scratchpad/ is silent ---"
CQ_SID_M2="test-sid-m2-$(date +%s%N)"
CQ_PAYLOAD_M2="$(cq_payload Write /private/tmp/claude-502/x/scratchpad/bench/scripts/stage_pairs.py 'def stage(): pass' '' "$CQ_SID_M2")"
CQ_OUT_M2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_M2")"
if [ -z "$CQ_OUT_M2" ]; then
  cq_pass "(m) scratchpad .py with public symbol is silent"
else
  cq_fail "(m) scratchpad .py with public symbol should be silent; got: $CQ_OUT_M2"
fi

echo "--- Test (m): .py directly under the /tmp/claude-<uid> harness root is silent ---"
CQ_SID_M3="test-sid-m3-$(date +%s%N)"
CQ_PAYLOAD_M3="$(cq_payload Write /tmp/claude-502/tasks/probe.py 'def run(): pass' '' "$CQ_SID_M3")"
CQ_OUT_M3="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_M3")"
if [ -z "$CQ_OUT_M3" ]; then
  cq_pass "(m) .py under /tmp/claude-<uid> root is silent"
else
  cq_fail "(m) .py under /tmp/claude-<uid> root should be silent; got: $CQ_OUT_M3"
fi

echo "--- Test (m): genuine repo .py at a normal path still fires (not over-broad) ---"
CQ_SID_M4="test-sid-m4-$(date +%s%N)"
CQ_PAYLOAD_M4="$(cq_payload Write /repo/src/service.py '' "$CQ_60LINES_M" "$CQ_SID_M4")"
CQ_OUT_M4="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_TEST_CACHE_DIR" bash "$CQ_SCRIPT" <<< "$CQ_PAYLOAD_M4")"
if echo "$CQ_OUT_M4" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(m) genuine repo .py still fires"
else
  cq_fail "(m) genuine repo .py should still fire; got: $CQ_OUT_M4"
fi

# --- (n) sequence debounce + sequence-aware phrasing (issue #2272) ---
# A PostToolUse cue on edit N of M is inherently early for N < M: the pre-flight
# lint it demands would run against a knowingly half-applied refactor. Two
# guards: (1) stay silent while edits to the SAME file are still in flight, and
# critically do NOT consume the once-per-session budget doing so, so the one cue
# lands on a settled edit instead of the noisiest one; (2) phrase the cue so a
# mid-sequence agent is never pushed to lint an incomplete tree.
#
# Block-local cache dir: n2-n5 use an empty session_id (like test (f)), so they
# would key under `nosession` in the shared dir and collide with each other.
CQ_N_CACHE="$(mktemp -d)"
cq_n_cleanup() { rm -rf "$CQ_TEST_CACHE_DIR" "$CQ_N_CACHE"; }
trap cq_n_cleanup EXIT

# Invoke with the block-local cache dir. $2, when set, overrides the debounce TTL.
cq_n() {
  if [ -n "${2:-}" ]; then
    CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_N_CACHE" \
      CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL="$2" bash "$CQ_SCRIPT" <<< "$1"
  else
    CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_N_CACHE" bash "$CQ_SCRIPT" <<< "$1"
  fi
}

# Payload with no session_id at all (mirrors test (f)'s shape).
cq_payload_nosid() {
  jq -n --arg tool_name "$1" --arg file_path "$2" --arg new_string "$3" \
    '{tool_name: $tool_name, tool_input: {file_path: $file_path, new_string: $new_string}}'
}

echo "--- Test (n1): mid-sequence cue does not consume the session budget ---"
CQ_SID_N1="test-sid-n1-$(date +%s%N)"
# Call 1: trivial (non-structural) edit to seq-a.ts — silent, but arms recency.
CQ_OUT_N1A="$(cq_n "$(cq_payload Edit /repo/src/seq-a.ts 'const x = 1;' '' "$CQ_SID_N1")")"
if [ -z "$CQ_OUT_N1A" ]; then
  cq_pass "(n1) trivial edit is silent"
else
  cq_fail "(n1) trivial edit should be silent; got: $CQ_OUT_N1A"
fi
# Call 2: structural edit to the SAME file moments later — a sequence is in
# flight, so the cue must be suppressed AND must not burn the session marker.
CQ_OUT_N1B="$(cq_n "$(cq_payload Edit /repo/src/seq-a.ts 'export function f(){}' '' "$CQ_SID_N1")")"
if [ -z "$CQ_OUT_N1B" ]; then
  cq_pass "(n1) mid-sequence structural edit is debounced"
else
  cq_fail "(n1) mid-sequence structural edit should be silent; got: $CQ_OUT_N1B"
fi
# Call 3: structural edit to a DIFFERENT, settled file, same session — the
# once-per-session budget must still be available.
CQ_OUT_N1C="$(cq_n "$(cq_payload Edit /repo/src/seq-b.ts 'export function g(){}' '' "$CQ_SID_N1")")"
if echo "$CQ_OUT_N1C" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(n1) settled edit still fires (session budget not consumed)"
else
  cq_fail "(n1) settled edit should still fire; got: $CQ_OUT_N1C"
fi

echo "--- Test (n2): debounce is per-file, not a blanket second-call mute ---"
CQ_OUT_N2A="$(cq_n "$(cq_payload_nosid Edit /repo/src/seq-c.ts 'export function c(){}')")"
CQ_OUT_N2B="$(cq_n "$(cq_payload_nosid Edit /repo/src/seq-d.ts 'export function d(){}')")"
if echo "$CQ_OUT_N2A" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(n2) first distinct file fires"
else
  cq_fail "(n2) first distinct file should fire; got: $CQ_OUT_N2A"
fi
if echo "$CQ_OUT_N2B" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(n2) second distinct file also fires"
else
  cq_fail "(n2) second distinct file should fire; got: $CQ_OUT_N2B"
fi

echo "--- Test (n3): same file, no session_id — second edit is suppressed ---"
CQ_OUT_N3A="$(cq_n "$(cq_payload_nosid Edit /repo/src/seq-e.ts 'export function e1(){}')")"
CQ_OUT_N3B="$(cq_n "$(cq_payload_nosid Edit /repo/src/seq-e.ts 'export function e2(){}')")"
if echo "$CQ_OUT_N3A" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(n3) first edit fires without a session_id"
else
  cq_fail "(n3) first edit should fire; got: $CQ_OUT_N3A"
fi
if [ -z "$CQ_OUT_N3B" ]; then
  cq_pass "(n3) repeat edit to same file is debounced without a session_id"
else
  cq_fail "(n3) repeat edit should be silent; got: $CQ_OUT_N3B"
fi

echo "--- Test (n4): debounce re-arms after the file goes quiet ---"
CQ_OUT_N4A="$(cq_n "$(cq_payload_nosid Edit /repo/src/seq-f.ts 'export function f1(){}')" 1)"
sleep 2
CQ_OUT_N4B="$(cq_n "$(cq_payload_nosid Edit /repo/src/seq-f.ts 'export function f2(){}')" 1)"
if echo "$CQ_OUT_N4A" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(n4) first edit fires"
else
  cq_fail "(n4) first edit should fire; got: $CQ_OUT_N4A"
fi
if echo "$CQ_OUT_N4B" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(n4) edit after TTL expiry fires again (debounce, not a mute)"
else
  cq_fail "(n4) edit after TTL expiry should fire again; got: $CQ_OUT_N4B"
fi

echo "--- Test (n5): CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL=0 disables debounce ---"
CQ_OUT_N5A="$(cq_n "$(cq_payload_nosid Edit /repo/src/seq-g.ts 'export function g1(){}')" 0)"
CQ_OUT_N5B="$(cq_n "$(cq_payload_nosid Edit /repo/src/seq-g.ts 'export function g2(){}')" 0)"
if echo "$CQ_OUT_N5A" | jq -e '.decision == "block"' > /dev/null 2>&1 \
  && echo "$CQ_OUT_N5B" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(n5) TTL=0 disables the debounce (both edits fire)"
else
  cq_fail "(n5) TTL=0 should disable the debounce; got: [$CQ_OUT_N5A] [$CQ_OUT_N5B]"
fi

echo "--- Test (n6): cue phrasing defers the lint to the end of the sequence ---"
# Self-contained: its own fresh cache dir + first-ever edit to seq-h.ts, so this
# always exercises a FIRING invocation. Chaining off another block's output would
# let both assertions pass vacuously whenever that block happened to be silent.
CQ_N6_CACHE="$(mktemp -d)"
CQ_OUT_N6="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_N6_CACHE" bash "$CQ_SCRIPT" \
  <<< "$(cq_payload Edit /repo/src/seq-h.ts 'export function h(){}' '' "test-sid-n6-$(date +%s%N)")")"
rm -rf "$CQ_N6_CACHE"
if echo "$CQ_OUT_N6" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(n6) guard: the probe invocation actually fires"
else
  cq_fail "(n6) guard: probe invocation should fire; got: $CQ_OUT_N6"
fi
if echo "$CQ_OUT_N6" | jq -r '.reason' | grep -q "once this edit sequence is complete"; then
  cq_pass "(n6) reason defers to sequence completion"
else
  cq_fail "(n6) reason should defer to sequence completion; got: $CQ_OUT_N6"
fi
if echo "$CQ_OUT_N6" | jq -r '.reason' | grep -q "before continuing"; then
  cq_fail "(n6) reason must not instruct a mid-sequence lint; got: $CQ_OUT_N6"
else
  cq_pass "(n6) reason omits the mid-sequence 'before continuing' phrasing"
fi

# --- (o) unset HOME must not break the tool call (issue #2272 follow-up) ---
# The cache-dir resolution moved ABOVE the detection block, so a bare "${HOME}"
# under `set -u` would abort on EVERY non-excluded Edit/Write, not just the
# structural ones — contradicting the header's "-e is intentionally omitted: a
# best-effort cue must never break a tool call". Both payload shapes are covered
# because the pre-fix blast radius was exactly the non-structural path.
#
# CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR is deliberately UNSET here: the seam's
# `:-` default is what references HOME, so leaving the seam set would never
# expand the fallback and the assertion would be vacuous. TMPDIR redirects the
# degraded cache into a temp dir so the run stays hermetic.
echo "--- Test (o): unset HOME degrades gracefully ---"
CQ_O_TMP="$(mktemp -d)"

cq_o_probe() {
  # $1 = payload. Echoes "<exit>|<stderr>|<stdout>".
  local cq_o_err cq_o_out cq_o_rc=0
  cq_o_err="$(mktemp)"
  cq_o_out="$(env -u HOME -u CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR TMPDIR="$CQ_O_TMP" \
    bash "$CQ_SCRIPT" <<< "$1" 2>"$cq_o_err")" || cq_o_rc=$?
  printf '%s|%s|%s' "$cq_o_rc" "$(tr -d '\n' < "$cq_o_err")" "$cq_o_out"
  rm -f "$cq_o_err"
}

# Non-structural payload — the path the regression widened to.
CQ_O1="$(cq_o_probe "$(cq_payload Edit /repo/src/home-trivial.ts 'const x = 1;' '' "test-sid-o1-$(date +%s%N)")")"
if [ "${CQ_O1%%|*}" = "0" ]; then
  cq_pass "(o) non-structural edit exits 0 with HOME unset"
else
  cq_fail "(o) non-structural edit with HOME unset should exit 0; got: $CQ_O1"
fi
CQ_O1_REST="${CQ_O1#*|}"
if [ -z "${CQ_O1_REST%%|*}" ]; then
  cq_pass "(o) non-structural edit is silent on stderr with HOME unset"
else
  cq_fail "(o) non-structural edit leaked stderr with HOME unset; got: $CQ_O1"
fi

# Structural payload — must still exit 0, stay clean on stderr, and still fire.
CQ_O2="$(cq_o_probe "$(cq_payload Edit /repo/src/home-structural.ts 'export function ho(){}' '' "test-sid-o2-$(date +%s%N)")")"
if [ "${CQ_O2%%|*}" = "0" ]; then
  cq_pass "(o) structural edit exits 0 with HOME unset"
else
  cq_fail "(o) structural edit with HOME unset should exit 0; got: $CQ_O2"
fi
CQ_O2_REST="${CQ_O2#*|}"
if [ -z "${CQ_O2_REST%%|*}" ]; then
  cq_pass "(o) structural edit is silent on stderr with HOME unset"
else
  cq_fail "(o) structural edit leaked stderr with HOME unset; got: $CQ_O2"
fi
if echo "${CQ_O2_REST#*|}" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  cq_pass "(o) structural edit still fires with HOME unset (degrades, not silences)"
else
  cq_fail "(o) structural edit should still fire with HOME unset; got: $CQ_O2"
fi
rm -rf "$CQ_O_TMP"

# --- (p) recency markers are swept, so the cache cannot grow without bound ---
# The debounce writes one marker per (session, file) for every non-excluded
# Edit/Write, plus a directory per session — unlike the pre-#2272 cache, which
# held one marker per session. The sweep prunes markers older than
# CODE_QUALITY_PREFLIGHT_CUE_MARKER_TTL minutes and the emptied session dirs.
echo "--- Test (p): stale recency markers are pruned ---"
CQ_P_CACHE="$(mktemp -d)"
mkdir -p "$CQ_P_CACHE/.edits/old-session" "$CQ_P_CACHE/.edits/live-session"
CQ_P_STALE="$CQ_P_CACHE/.edits/old-session/gone.ts-123"
CQ_P_FRESH="$CQ_P_CACHE/.edits/live-session/here.ts-456"
echo 1 > "$CQ_P_STALE"
echo 2 > "$CQ_P_FRESH"

# Backdate the stale marker two days (> the 1440-minute default TTL).
# GNU `date -d` and BSD `date -v` differ; try both before giving up.
CQ_P_OLD_STAMP="$(date -d '2 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-2d +%Y%m%d%H%M 2>/dev/null || echo '')"
if [ -n "$CQ_P_OLD_STAMP" ] && touch -t "$CQ_P_OLD_STAMP" "$CQ_P_STALE" 2>/dev/null; then
  CQ_OUT_P="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_P_CACHE" bash "$CQ_SCRIPT" \
    <<< "$(cq_payload Edit /repo/src/sweep.ts 'export function sw(){}' '' "test-sid-p-$(date +%s%N)")")"
  if echo "$CQ_OUT_P" | jq -e '.decision == "block"' > /dev/null 2>&1; then
    cq_pass "(p) guard: the sweeping invocation actually fires"
  else
    cq_fail "(p) guard: sweeping invocation should fire; got: $CQ_OUT_P"
  fi
  if [ ! -e "$CQ_P_STALE" ]; then
    cq_pass "(p) stale recency marker is pruned"
  else
    cq_fail "(p) stale recency marker should have been pruned: $CQ_P_STALE"
  fi
  if [ ! -e "$CQ_P_CACHE/.edits/old-session" ]; then
    cq_pass "(p) emptied session directory is pruned"
  else
    cq_fail "(p) emptied session directory should have been pruned"
  fi
  # Over-broad-sweep guard: a marker inside the TTL must survive, or the sweep
  # would disarm live debounces instead of just reclaiming space.
  if [ -e "$CQ_P_FRESH" ]; then
    cq_pass "(p) in-TTL recency marker survives the sweep"
  else
    cq_fail "(p) in-TTL recency marker must survive the sweep"
  fi
  # The sentinel gates the sweep to at most hourly.
  if [ -e "$CQ_P_CACHE/.last-sweep" ]; then
    cq_pass "(p) sweep sentinel is written"
  else
    cq_fail "(p) sweep sentinel should be written"
  fi
else
  cq_fail "(p) could not backdate a marker (neither GNU nor BSD date/touch worked)"
fi
rm -rf "$CQ_P_CACHE"

# --- (p2) MARKER_TTL=0 is rejected, not honoured as "disable" -----------------
# The sibling knob DEBOUNCE_TTL reads 0 as "disable", so a reader generalising
# that would expect 0 to switch the sweep off. Here 0 means `find -mmin +0` --
# prune anything a minute old -- the OPPOSITE, silently disarming every live
# debounce. 0 must fall back to the default like any other invalid value.
echo "--- Test (p2): MARKER_TTL=0 does not disarm live debounces ---"
CQ_P2_CACHE="$(mktemp -d)"
if [ -n "$CQ_P2_CACHE" ] && [ -d "$CQ_P2_CACHE" ]; then
  mkdir -p "$CQ_P2_CACHE/.edits/live-session"
  CQ_P2_FRESH="$CQ_P2_CACHE/.edits/live-session/active.ts-789"
  echo 1 > "$CQ_P2_FRESH"
  # Age it 3 minutes: well inside the 1440-minute default, but `-mmin +0` eats it.
  CQ_P2_STAMP="$(date -d '3 minutes ago' +%Y%m%d%H%M 2>/dev/null || date -v-3M +%Y%m%d%H%M 2>/dev/null || echo '')"
  if [ -n "$CQ_P2_STAMP" ] && touch -t "$CQ_P2_STAMP" "$CQ_P2_FRESH" 2>/dev/null; then
    CQ_OUT_P2="$(CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR="$CQ_P2_CACHE" \
      CODE_QUALITY_PREFLIGHT_CUE_MARKER_TTL=0 bash "$CQ_SCRIPT" \
      <<< "$(cq_payload Edit /repo/src/other.ts 'export function ot(){}' '' "test-sid-p2-$(date +%s%N)")")"
    # Guard integrity: the sweeping invocation must actually run, or the
    # survival assertion below would pass against a hook that never swept.
    if echo "$CQ_OUT_P2" | jq -e '.decision == "block"' > /dev/null 2>&1; then
      cq_pass "(p2) guard: the sweeping invocation actually fires"
    else
      cq_fail "(p2) guard: sweeping invocation should fire; got: $CQ_OUT_P2"
    fi
    if [ -e "$CQ_P2_FRESH" ]; then
      cq_pass "(p2) MARKER_TTL=0 falls back to the default; live marker survives"
    else
      cq_fail "(p2) MARKER_TTL=0 pruned a 3-minute-old marker, disarming live debounces"
    fi
  else
    cq_fail "(p2) could not backdate a marker (neither GNU nor BSD date/touch worked)"
  fi
  rm -rf "$CQ_P2_CACHE"
else
  cq_fail "(p2) could not create a scratch cache dir"
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
