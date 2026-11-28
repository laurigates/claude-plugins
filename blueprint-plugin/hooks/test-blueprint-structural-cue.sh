#!/usr/bin/env bash
# Regression tests for blueprint-structural-cue.sh (ADR-0017 behavioral cue).
# Run: bash blueprint-plugin/hooks/test-blueprint-structural-cue.sh
#
# Replaces hooks/spec/blueprint_structural_cue_spec.sh: that ShellSpec suite was
# never executed anywhere (shellspec is not installed, not in CI, not in any
# justfile recipe) and its two shape assertions pinned the BROKEN output contract
# — "output should include updatedToolOutput" and "preserves the original
# tool_response". This file lives under */hooks/test-*.sh so
# scripts/run-skill-script-tests.sh discovers it automatically.
#
# The contract this pins (issue #2275): the cue rides the
# {"decision":"block","reason":…} channel with continueOnBlock:true in hooks.json,
# NOT hookSpecificOutput.updatedToolOutput. Write/Edit's tool output shape is
# {content, filePath, originalFile, structuredPatch, type, userModified} — it has
# no free-text field, `content` is the file's real content, and a JSON string
# there is rejected outright, so the hint was silently discarded every time.
set -uo pipefail

BSC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BSC_SCRIPT="${BSC_SCRIPT_DIR}/blueprint-structural-cue.sh"
BSC_HOOKS_JSON="${BSC_SCRIPT_DIR}/../hooks.json"
BSC_PASS=0
BSC_FAIL=0

BSC_TEST_CACHE_DIR="$(mktemp -d)"
# Default project dir for every case: a blueprint project whose manifest has no
# task_registry, so the cue fires and names both tasks. Without this seam the
# hook would read the manifest of whatever checkout the suite runs from (this
# repo's disables derive-plans, #3648). A project with NO manifest is silent
# (#3799), so the default must carry one or every "fires" case goes quiet.
BSC_TEST_PROJECT_DIR="$(mktemp -d)"
mkdir -p "${BSC_TEST_PROJECT_DIR}/docs/blueprint"
printf '%s\n' '{"format_version": "3.3.0"}' > "${BSC_TEST_PROJECT_DIR}/docs/blueprint/manifest.json"
# A project with no docs/blueprint/manifest.json at all (#3799).
BSC_TEST_NO_BLUEPRINT_DIR="$(mktemp -d)"
BSC_TEST_FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$BSC_TEST_CACHE_DIR" "$BSC_TEST_PROJECT_DIR" "$BSC_TEST_NO_BLUEPRINT_DIR" "$BSC_TEST_FIXTURE_ROOT"' EXIT

# Every emitted reason starts with this, so the model reads the cue as advice on
# an edit that already applied, not as a failed edit (#3799). The harness still
# labels the decision:block channel "hook blocking error".
BSC_ADVISORY_PREFIX="Advisory (edit applied): "

bsc_pass() { echo "  PASS: $1"; BSC_PASS=$((BSC_PASS + 1)); }
bsc_fail() { echo "  FAIL: $1"; BSC_FAIL=$((BSC_FAIL + 1)); }

# Build a PostToolUse payload. tool_response is the REAL Write/Edit result object,
# not the bare string the old ShellSpec fixtures used.
bsc_payload() {
    local bsc_tool="$1" bsc_file="$2" bsc_new_string="${3:-}" bsc_content="${4:-}"
    local bsc_sid="${5:-bsc-$$-${RANDOM}}"
    jq -nc \
        --arg tool_name "$bsc_tool" \
        --arg file_path "$bsc_file" \
        --arg new_string "$bsc_new_string" \
        --arg content "$bsc_content" \
        --arg session_id "$bsc_sid" \
        '{
            tool_name: $tool_name,
            tool_input: {file_path: $file_path, new_string: $new_string, content: $content},
            session_id: $session_id,
            tool_response: {
                content: $content,
                filePath: $file_path,
                originalFile: "",
                structuredPatch: [],
                type: "create",
                userModified: false
            }
        }'
}

bsc_run() {
    CLAUDE_PROJECT_DIR="$BSC_TEST_PROJECT_DIR" \
        BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR="$BSC_TEST_CACHE_DIR" bash "$BSC_SCRIPT" <<<"$1"
}

# Run the hook with CLAUDE_PROJECT_DIR pointing at a given project directory.
bsc_run_in() {
    CLAUDE_PROJECT_DIR="$1" \
        BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR="$BSC_TEST_CACHE_DIR" bash "$BSC_SCRIPT" <<<"$2"
}

# Create a project dir whose docs/blueprint/manifest.json holds the given text.
bsc_make_project() {
    local bsc_proj="${BSC_TEST_FIXTURE_ROOT}/$1"
    mkdir -p "${bsc_proj}/docs/blueprint"
    printf '%s\n' "$2" > "${bsc_proj}/docs/blueprint/manifest.json"
    printf '%s' "$bsc_proj"
}

# The cue fired: decision:block with a [blueprint] reason.
assert_fires() {
    local bsc_desc="$1" bsc_out
    bsc_out="$(bsc_run "$2")"
    if printf '%s' "$bsc_out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        bsc_pass "$bsc_desc"
    else
        bsc_fail "$bsc_desc (expected decision:block; got: ${bsc_out:-<empty>})"
    fi
}

# The hook stayed silent.
assert_silent() {
    local bsc_desc="$1" bsc_out
    bsc_out="$(bsc_run "$2")"
    if [ -z "$bsc_out" ]; then
        bsc_pass "$bsc_desc"
    else
        bsc_fail "$bsc_desc (expected silence; got: $bsc_out)"
    fi
}

echo "=== blueprint-structural-cue hook tests ==="

# --- Output contract (#2275): the block channel, exclusively ---
echo ""
echo "output contract: decision:block channel (#2275):"
BSC_OUT_CONTRACT="$(bsc_run "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' contract-1)")"

if printf '%s' "$BSC_OUT_CONTRACT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    bsc_pass "emits decision:block"
else
    bsc_fail "expected decision:block; got: ${BSC_OUT_CONTRACT:-<empty>}"
fi

if printf '%s' "$BSC_OUT_CONTRACT" | jq -e --arg p "${BSC_ADVISORY_PREFIX}[blueprint] " '.reason | startswith($p)' >/dev/null 2>&1; then
    bsc_pass "reason starts with 'Advisory (edit applied): [blueprint] ' (#3799)"
else
    bsc_fail "reason missing 'Advisory (edit applied): [blueprint] ' prefix; got: ${BSC_OUT_CONTRACT:-<empty>}"
fi

if printf '%s' "$BSC_OUT_CONTRACT" | jq -e '.reason | contains("derive-plans") and contains("adr-validate")' >/dev/null 2>&1; then
    bsc_pass "reason names the blueprint skills to run"
else
    bsc_fail "reason missing skill names; got: ${BSC_OUT_CONTRACT:-<empty>}"
fi

# Channel exclusivity — stops a "fix" that emits both channels at once.
if printf '%s' "$BSC_OUT_CONTRACT" | jq -e 'has("hookSpecificOutput") | not' >/dev/null 2>&1; then
    bsc_pass "does NOT emit hookSpecificOutput (wrong channel for Write/Edit)"
else
    bsc_fail "still emits hookSpecificOutput; got: $BSC_OUT_CONTRACT"
fi

# --- Corruption guard: the file's own content must never round-trip ---
# Pre-fix, `tostring` serialized the entire Write response — including the file
# content — into updatedToolOutput, which the model reads as the tool result.
echo ""
echo "corruption guard: file content never echoed back:"
BSC_SENTINEL='export const SENTINEL_CONTENT_MARKER = 1;'
BSC_OUT_SENTINEL="$(bsc_run "$(bsc_payload Write src/sentinel.ts '' "$BSC_SENTINEL" sentinel-1)")"
if grep -qF "SENTINEL_CONTENT_MARKER" <<<"$BSC_OUT_SENTINEL"; then
    bsc_fail "file content leaked into hook output; got: $BSC_OUT_SENTINEL"
else
    bsc_pass "file content does not appear anywhere in the hook output"
fi
if printf '%s' "$BSC_OUT_SENTINEL" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    bsc_pass "the same edit still fires the cue (guard is not vacuous)"
else
    bsc_fail "sentinel edit should still fire; got: ${BSC_OUT_SENTINEL:-<empty>}"
fi

# --- Detection signals (ported from the retired ShellSpec suite) ---
echo ""
echo "detection signals fire:"
assert_fires "plugin.json manifest edit" \
    "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' sig-1)"
assert_fires "marketplace.json edit" \
    "$(bsc_payload Edit .claude-plugin/marketplace.json 'x' '' sig-2)"
assert_fires "export-line write" \
    "$(bsc_payload Write src/index.ts '' 'export function foo() {}' sig-3)"
assert_fires "Rust pub fn write" \
    "$(bsc_payload Write lib.rs '' 'pub fn bar() {}' sig-4)"
assert_fires "TypeScript exported interface" \
    "$(bsc_payload Edit src/types.ts 'export interface MyConfig { host: string; }' '' sig-5)"
assert_fires "TypeScript exported type alias" \
    "$(bsc_payload Write src/api.ts '' 'export type RequestId = string;' sig-6)"
assert_fires "Go exported struct" \
    "$(bsc_payload Edit pkg/server.go 'type Server struct { addr string }' '' sig-7)"
assert_fires "Go exported interface" \
    "$(bsc_payload Edit pkg/handler.go 'type Handler interface { ServeHTTP() }' '' sig-8)"
assert_fires "Rust pub struct" \
    "$(bsc_payload Edit src/lib.rs 'pub struct Config { pub host: String }' '' sig-9)"
assert_fires "Rust pub enum" \
    "$(bsc_payload Edit src/error.rs 'pub enum AppError { NotFound, BadRequest }' '' sig-10)"
assert_fires "Rust pub trait" \
    "$(bsc_payload Edit src/traits.rs 'pub trait Processor { fn process(&self); }' '' sig-11)"
assert_fires "Express route registration" \
    "$(bsc_payload Edit src/routes.js 'app.get("/health", handler);' '' sig-12)"
assert_fires "Flask route decorator" \
    "$(bsc_payload Edit app.py '@app.route("/users")' '' sig-13)"
assert_fires ".proto schema write" \
    "$(bsc_payload Write proto/service.proto '' 'syntax = "proto3";' sig-14)"
assert_fires ".graphql schema write" \
    "$(bsc_payload Write schema/api.graphql '' 'type Query { users: [User] }' sig-15)"
assert_fires "Prisma schema write" \
    "$(bsc_payload Write prisma/schema.prisma '' 'model User { id Int }' sig-16)"
assert_fires "openapi.yaml write" \
    "$(bsc_payload Write docs/openapi.yaml '' 'openapi: 3.0.0' sig-17)"

echo ""
echo "non-structural edits stay silent:"
assert_silent "trivial README edit" \
    "$(bsc_payload Edit README.md 'fixed a typo' '' quiet-1)"
assert_silent "docs/adrs path is excluded (covered by other blueprint hooks)" \
    "$(bsc_payload Edit docs/adrs/0001-x.md 'export note' '' quiet-2)"
assert_silent "lowercase Go struct (unexported)" \
    "$(bsc_payload Edit internal/server.go 'type server struct { addr string }' '' quiet-3)"
assert_silent "non-exported TypeScript interface" \
    "$(bsc_payload Edit src/internal.ts 'interface internalConfig { debug: boolean }' '' quiet-4)"
assert_silent "plain YAML config (not openapi)" \
    "$(bsc_payload Edit config/settings.yaml 'debug: true' '' quiet-5)"

# Non-Edit/Write tool: build the payload by hand (Bash has no file_path).
BSC_BASH_PAYLOAD='{"tool_name":"Bash","session_id":"quiet-6","tool_input":{"command":"export FOO=1"},"tool_response":{"stdout":"ok","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false}}'
assert_silent "non-Edit/Write tool is ignored" "$BSC_BASH_PAYLOAD"

# --- #2336: code-shaped signals (2-6) are gated on a source extension ---
#
# Pre-fix, signals 2-6 grepped the payload of ANY file, so English prose
# containing "export " fired the public-API cue. `file_ext` was computed at the
# top of the hook and referenced nowhere — the dropped guard this pins.
#
# These are SEMANTIC, not a grep for the string `is_code_file`: each feeds the
# hook a payload that is byte-for-byte code-shaped and asserts the VERDICT turns
# on the file's extension alone. The paired "still fires" controls below keep the
# gate from being satisfied by a hook that simply went silent everywhere.
echo ""
echo "prose does not trip the code-shaped signals (#2336):"

# The verbatim repro from the issue: a Markdown table cell reading
# "…the same consumer-contract test before the export can be called correct".
assert_silent "prose containing 'export ' in a .md file (issue #2336 repro)" \
    "$(bsc_payload Write notes.md '' 'needs a test before the export can be called correct' ext-1)"
assert_silent "a Markdown list item starting with the word 'pub'" \
    "$(bsc_payload Edit docs/glossary.md 'pub means published here, not Rust visibility' '' ext-2)"
assert_silent "'module.exports' discussed in prose" \
    "$(bsc_payload Edit README.md 'the legacy module.exports form still works' '' ext-3)"
assert_silent "an Express route shown as a Markdown code sample" \
    "$(bsc_payload Edit docs/guide.md 'app.get("/health", handler);' '' ext-4)"
assert_silent "a TypeScript exported interface quoted in prose" \
    "$(bsc_payload Edit CHANGELOG.md 'renamed export interface MyConfig to Settings' '' ext-5)"
assert_silent "a Go exported struct quoted in a .txt scratch note" \
    "$(bsc_payload Write notes.txt '' 'type Server struct { addr string }' ext-6)"
assert_silent "export-shaped content in a plain .json data file (not a manifest)" \
    "$(bsc_payload Write data/fixture.json '' '{"note": "export default thing"}' ext-7)"
assert_silent "export-shaped content in a .yaml config (not openapi)" \
    "$(bsc_payload Edit config/app.yaml 'comment: export default is unrelated here' '' ext-8)"
assert_silent "a path with no extension at all" \
    "$(bsc_payload Write Makefile '' 'export PATH := /usr/bin' ext-9)"

echo ""
echo "genuine source edits still fire (the gate is not a blanket mute):"
# The issue's control, verbatim. Same payload as ext-5/ext-7 in substance —
# only the extension differs, which is exactly the invariant.
assert_fires "the same 'export interface' payload in a .ts file (issue #2336 control)" \
    "$(bsc_payload Write x.ts '' 'export interface Foo { a: string }' ext-ctl-1)"
assert_fires "the same 'app.get(' payload in a .js file" \
    "$(bsc_payload Edit src/routes.js 'app.get("/health", handler);' '' ext-ctl-2)"
assert_fires "the same 'type Server struct' payload in a .go file" \
    "$(bsc_payload Write pkg/server.go '' 'type Server struct { addr string }' ext-ctl-3)"
assert_fires "a pub struct in a .rs file" \
    "$(bsc_payload Edit src/lib.rs 'pub struct Config { pub host: String }' '' ext-ctl-4)"
assert_fires "def __all__ in a .py file" \
    "$(bsc_payload Write pkg/__init__.py '' 'def __all__(): pass' ext-ctl-5)"
assert_fires ".mjs is a source extension" \
    "$(bsc_payload Write src/mod.mjs '' 'export default function () {}' ext-ctl-6)"
assert_fires ".tsx is a source extension" \
    "$(bsc_payload Write src/App.tsx '' 'export type Props = { a: string };' ext-ctl-7)"

echo ""
echo "path/basename signals (1, 7) stay extension-free (#2336):"
# These identify themselves by path, so the extension gate must NOT reach them —
# .json / .yaml / .proto are all outside the source-extension list.
assert_fires "plugin.json manifest still fires though .json is not a code ext" \
    "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' ext-path-1)"
assert_fires "marketplace.json still fires" \
    "$(bsc_payload Edit .claude-plugin/marketplace.json 'x' '' ext-path-2)"
assert_fires "openapi.yaml still fires though .yaml is not a code ext" \
    "$(bsc_payload Write docs/openapi.yaml '' 'openapi: 3.0.0' ext-path-3)"
assert_fires ".proto still fires though .proto is not a code ext" \
    "$(bsc_payload Write proto/service.proto '' 'syntax = "proto3";' ext-path-4)"
assert_fires "schema.prisma still fires" \
    "$(bsc_payload Write prisma/schema.prisma '' 'model User { id Int }' ext-path-5)"

echo ""
echo "session scratchpad is inert (#2336):"
# /blueprint:derive-plans can never be actionable for a file in the harness's
# per-session scratch tree — it belongs to no repo.
assert_silent "a .ts export under /private/tmp/claude-<uid>/…/scratchpad/" \
    "$(bsc_payload Write /private/tmp/claude-502/-Users-x-repo/abc-123/scratchpad/gen.ts '' 'export interface Foo { a: string }' scratch-1)"
assert_silent "a plugin.json under /tmp/claude-<uid>/…" \
    "$(bsc_payload Write /tmp/claude-502/sess/scratchpad/plugin.json '' '{}' scratch-2)"
assert_silent "a .ts export under /var/folders/…/claude-<uid>/…" \
    "$(bsc_payload Write /var/folders/ab/xy/T/claude-502/sess/scratchpad/gen.ts '' 'export default 1;' scratch-3)"
# Narrowness control: the carve-out is the harness scratchpad, NOT all of /tmp.
assert_fires "a plain /tmp source file is NOT swept up by the scratchpad exit" \
    "$(bsc_payload Write /tmp/x.ts '' 'export interface Foo { a: string }' scratch-ctl-1)"

echo ""
echo "dedup, bypass, and edge cases:"
BSC_DUP_PAYLOAD="$(bsc_payload Edit a/plugin.json 'x' '' dup-session)"
BSC_DUP_1="$(bsc_run "$BSC_DUP_PAYLOAD")"
BSC_DUP_2="$(bsc_run "$BSC_DUP_PAYLOAD")"
if printf '%s' "$BSC_DUP_1" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    bsc_pass "first structural edit in a session fires"
else
    bsc_fail "first structural edit should fire; got: ${BSC_DUP_1:-<empty>}"
fi
if [ -z "$BSC_DUP_2" ]; then
    bsc_pass "second structural edit in the same session is silent (dedup)"
else
    bsc_fail "second edit should be deduped; got: $BSC_DUP_2"
fi

BSC_SKIP_OUT="$(BLUEPRINT_SKIP_HOOKS=1 BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR="$BSC_TEST_CACHE_DIR" \
    bash "$BSC_SCRIPT" <<<"$(bsc_payload Edit b/plugin.json 'x' '' skip-1)")"
if [ -z "$BSC_SKIP_OUT" ]; then
    bsc_pass "BLUEPRINT_SKIP_HOOKS=1 silences the hook"
else
    bsc_fail "BLUEPRINT_SKIP_HOOKS=1 should silence; got: $BSC_SKIP_OUT"
fi

# No session_id: dedup is skipped, the cue still fires, and the hook exits 0.
BSC_NOSID_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"lib.rs","content":"pub fn bar() {}"},"tool_response":{"content":"pub fn bar() {}","filePath":"lib.rs","originalFile":"","structuredPatch":[],"type":"create","userModified":false}}'
BSC_NOSID_EXIT=0
BSC_NOSID_OUT="$(bsc_run "$BSC_NOSID_PAYLOAD")" || BSC_NOSID_EXIT=$?
if [ "$BSC_NOSID_EXIT" -eq 0 ]; then
    bsc_pass "missing session_id exits 0"
else
    bsc_fail "missing session_id crashed with exit $BSC_NOSID_EXIT"
fi
if printf '%s' "$BSC_NOSID_OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    bsc_pass "missing session_id still fires the cue"
else
    bsc_fail "missing session_id should still fire; got: ${BSC_NOSID_OUT:-<empty>}"
fi

# --- #3648: the cue names only tasks the manifest's task_registry enables ---
#
# Pre-fix the cue was one fixed string naming both /blueprint:derive-plans and
# /blueprint:adr-validate in every repo, including repos whose
# docs/blueprint/manifest.json disables derive-plans. Each case asserts on the
# reason text produced for a manifest fixture, not on the hook's source.
echo ""
echo "task_registry gates the named tasks (#3648):"

BSC_PROJ_DP_OFF="$(bsc_make_project dp-off '{"task_registry": {"derive-plans": {"enabled": false}, "adr-validate": {"enabled": true}}}')"
BSC_OUT_DP_OFF="$(bsc_run_in "$BSC_PROJ_DP_OFF" "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' reg-1)")"
if printf '%s' "$BSC_OUT_DP_OFF" | jq -e '.decision == "block" and (.reason | contains("/blueprint:adr-validate")) and (.reason | contains("derive-plans") | not)' >/dev/null 2>&1; then
    bsc_pass "derive-plans disabled -> cue names /blueprint:adr-validate only"
else
    bsc_fail "derive-plans disabled should name adr-validate only; got: ${BSC_OUT_DP_OFF:-<empty>}"
fi

BSC_PROJ_AV_OFF="$(bsc_make_project av-off '{"task_registry": {"derive-plans": {"enabled": true}, "adr-validate": {"enabled": false}}}')"
BSC_OUT_AV_OFF="$(bsc_run_in "$BSC_PROJ_AV_OFF" "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' reg-2)")"
if printf '%s' "$BSC_OUT_AV_OFF" | jq -e '.decision == "block" and (.reason | contains("/blueprint:derive-plans")) and (.reason | contains("adr-validate") | not)' >/dev/null 2>&1; then
    bsc_pass "adr-validate disabled -> cue names /blueprint:derive-plans only"
else
    bsc_fail "adr-validate disabled should name derive-plans only; got: ${BSC_OUT_AV_OFF:-<empty>}"
fi

BSC_PROJ_BOTH_OFF="$(bsc_make_project both-off '{"task_registry": {"derive-plans": {"enabled": false}, "adr-validate": {"enabled": false}}}')"
BSC_BOTH_OFF_EXIT=0
BSC_OUT_BOTH_OFF="$(bsc_run_in "$BSC_PROJ_BOTH_OFF" "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' reg-3)")" || BSC_BOTH_OFF_EXIT=$?
if [ -z "$BSC_OUT_BOTH_OFF" ] && [ "$BSC_BOTH_OFF_EXIT" -eq 0 ]; then
    bsc_pass "both disabled -> no cue, exit 0"
else
    bsc_fail "both disabled should be silent with exit 0; exit=$BSC_BOTH_OFF_EXIT got: ${BSC_OUT_BOTH_OFF:-<empty>}"
fi
# Silence must not burn the session's one cue: the marker is written only when
# a cue is actually emitted.
if [ ! -f "${BSC_TEST_CACHE_DIR}/reg-3" ]; then
    bsc_pass "a suppressed cue does not write the dedup marker"
else
    bsc_fail "dedup marker written although no cue was emitted"
fi

# This repo's manifest shape: auto_run and other tasks alongside enabled.
BSC_PROJ_REAL="$(bsc_make_project real-shape '{"format_version": "3.3.0", "task_registry": {"derive-plans": {"enabled": false, "auto_run": false}, "adr-validate": {"enabled": true, "auto_run": false}, "sync-ids": {"enabled": true}}}')"
BSC_OUT_REAL="$(bsc_run_in "$BSC_PROJ_REAL" "$(bsc_payload Write src/index.ts '' 'export function foo() {}' reg-4)")"
if printf '%s' "$BSC_OUT_REAL" | jq -e '(.reason | contains("/blueprint:adr-validate")) and (.reason | contains("derive-plans") | not)' >/dev/null 2>&1; then
    bsc_pass "manifest with extra keys -> still names adr-validate only"
else
    bsc_fail "manifest with extra keys should name adr-validate only; got: ${BSC_OUT_REAL:-<empty>}"
fi

# Fallbacks: anything other than an explicit enabled:false keeps today's text.
BSC_TODAY_REASON="${BSC_ADVISORY_PREFIX}[blueprint] Structural change detected (manifest / public API). Consider /blueprint:derive-plans or /blueprint:adr-validate to keep PRDs/ADRs current."

BSC_PROJ_EMPTY="$(bsc_make_project empty-object '{}')"
BSC_OUT_EMPTY="$(bsc_run_in "$BSC_PROJ_EMPTY" "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' reg-5)")"
if printf '%s' "$BSC_OUT_EMPTY" | jq -e --arg r "$BSC_TODAY_REASON" '.reason == $r' >/dev/null 2>&1; then
    bsc_pass "empty-object manifest -> full cue text"
else
    bsc_fail "empty-object manifest should keep the full text; got: ${BSC_OUT_EMPTY:-<empty>}"
fi

BSC_PROJ_BAD="$(bsc_make_project malformed '{"task_registry": {"derive-plans": {"enabled": fal')"
BSC_BAD_EXIT=0
BSC_OUT_BAD="$(bsc_run_in "$BSC_PROJ_BAD" "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' reg-6)" 2>&1)" || BSC_BAD_EXIT=$?
if [ "$BSC_BAD_EXIT" -eq 0 ] && printf '%s' "$BSC_OUT_BAD" | jq -e --arg r "$BSC_TODAY_REASON" '.reason == $r' >/dev/null 2>&1; then
    bsc_pass "malformed manifest -> today's text, exit 0, nothing on stderr"
else
    bsc_fail "malformed manifest should fall back cleanly; exit=$BSC_BAD_EXIT got: ${BSC_OUT_BAD:-<empty>}"
fi

BSC_PROJ_NOREG="$(bsc_make_project no-registry '{"format_version": "3.3.0"}')"
BSC_OUT_NOREG="$(bsc_run_in "$BSC_PROJ_NOREG" "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' reg-7)")"
if printf '%s' "$BSC_OUT_NOREG" | jq -e --arg r "$BSC_TODAY_REASON" '.reason == $r' >/dev/null 2>&1; then
    bsc_pass "manifest without task_registry -> cue text unchanged"
else
    bsc_fail "manifest without task_registry should keep today's text; got: ${BSC_OUT_NOREG:-<empty>}"
fi

BSC_PROJ_BOTH_ON="$(bsc_make_project both-on '{"task_registry": {"derive-plans": {"enabled": true}, "adr-validate": {"enabled": true}}}')"
BSC_OUT_BOTH_ON="$(bsc_run_in "$BSC_PROJ_BOTH_ON" "$(bsc_payload Edit foo-plugin/.claude-plugin/plugin.json 'x' '' reg-8)")"
if printf '%s' "$BSC_OUT_BOTH_ON" | jq -e --arg r "$BSC_TODAY_REASON" '.reason == $r' >/dev/null 2>&1; then
    bsc_pass "both enabled -> cue text unchanged"
else
    bsc_fail "both enabled should keep today's text; got: ${BSC_OUT_BOTH_ON:-<empty>}"
fi

# --- #3799: no blueprint manifest, no cue ---
#
# Pre-fix a missing docs/blueprint/manifest.json kept the full cue (#3648 chose
# that fallback), so a plain Rust CLI with no blueprint got "Consider
# /blueprint:derive-plans or /blueprint:adr-validate to keep PRDs/ADRs current"
# on an ordinary Edit, though it has no PRDs or ADRs. Each case below feeds a
# payload that FIRES in a blueprint project and asserts silence in a project
# without a manifest; the paired control runs the same payload with a manifest.
echo ""
echo "no docs/blueprint/manifest.json -> silent (#3799):"

bsc_assert_silent_without_manifest() {
    local bsc_desc="$1" bsc_payload_json="$2" bsc_sid="$3" bsc_out bsc_exit=0
    bsc_out="$(bsc_run_in "$BSC_TEST_NO_BLUEPRINT_DIR" "$bsc_payload_json" 2>&1)" || bsc_exit=$?
    if [ -z "$bsc_out" ] && [ "$bsc_exit" -eq 0 ]; then
        bsc_pass "$bsc_desc"
    else
        bsc_fail "$bsc_desc (expected silence, exit 0; exit=$bsc_exit got: ${bsc_out:-<empty>})"
    fi
    if [ ! -f "${BSC_TEST_CACHE_DIR}/${bsc_sid}" ]; then
        bsc_pass "$bsc_desc: no dedup marker written"
    else
        bsc_fail "$bsc_desc: dedup marker written although no cue was emitted"
    fi
}

# The issue's repro: an Edit to src/config.rs adding pub fn lines, in a Rust CLI
# with no blueprint.
BSC_REPRO_EDIT="$(bsc_payload Edit src/config.rs 'pub fn load() -> Config {
    Config::default()
}' '' nobp-1)"
bsc_assert_silent_without_manifest "Edit adding pub fn in src/config.rs (issue #3799 repro)" \
    "$BSC_REPRO_EDIT" nobp-1
bsc_assert_silent_without_manifest "Write of a plugin.json manifest" \
    "$(bsc_payload Write foo-plugin/.claude-plugin/plugin.json '' '{}' nobp-2)" nobp-2
bsc_assert_silent_without_manifest "Write of an export line in a .ts file" \
    "$(bsc_payload Write src/index.ts '' 'export function foo() {}' nobp-3)" nobp-3

# Payload cwd fallback: no CLAUDE_PROJECT_DIR, cwd names the manifest-less repo.
BSC_CWD_PAYLOAD="$(printf '%s' "$(bsc_payload Edit src/lib.rs 'pub struct Config {}' '' nobp-4)" \
    | jq -c --arg cwd "$BSC_TEST_NO_BLUEPRINT_DIR" '. + {cwd: $cwd}')"
BSC_CWD_OUT="$(env -u CLAUDE_PROJECT_DIR BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR="$BSC_TEST_CACHE_DIR" \
    bash "$BSC_SCRIPT" <<<"$BSC_CWD_PAYLOAD")"
if [ -z "$BSC_CWD_OUT" ]; then
    bsc_pass "payload cwd without a manifest -> silent"
else
    bsc_fail "payload cwd without a manifest should be silent; got: $BSC_CWD_OUT"
fi

# Controls: the same payloads fire once a manifest exists, so the silence above
# comes from the missing manifest and not from a hook that went quiet everywhere.
BSC_REPRO_CTL="$(bsc_run_in "$BSC_TEST_PROJECT_DIR" "$(bsc_payload Edit src/config.rs 'pub fn load() -> Config {
    Config::default()
}' '' nobp-ctl-1)")"
if printf '%s' "$BSC_REPRO_CTL" | jq -e --arg r "$BSC_TODAY_REASON" '.reason == $r' >/dev/null 2>&1; then
    bsc_pass "control: the repro Edit fires in a project with a manifest"
else
    bsc_fail "control: the repro Edit should fire with a manifest; got: ${BSC_REPRO_CTL:-<empty>}"
fi
BSC_CWD_CTL_PAYLOAD="$(printf '%s' "$(bsc_payload Edit src/lib.rs 'pub struct Config {}' '' nobp-ctl-2)" \
    | jq -c --arg cwd "$BSC_TEST_PROJECT_DIR" '. + {cwd: $cwd}')"
BSC_CWD_CTL_OUT="$(env -u CLAUDE_PROJECT_DIR BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR="$BSC_TEST_CACHE_DIR" \
    bash "$BSC_SCRIPT" <<<"$BSC_CWD_CTL_PAYLOAD")"
if printf '%s' "$BSC_CWD_CTL_OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    bsc_pass "control: payload cwd with a manifest fires"
else
    bsc_fail "control: payload cwd with a manifest should fire; got: ${BSC_CWD_CTL_OUT:-<empty>}"
fi

# --- hooks.json registration gate ---
# decision:block WITHOUT continueOnBlock ends the turn. The hook is on by default
# (only BLUEPRINT_SKIP_HOOKS=1 opts out), so a missing flag would turn a silent
# no-op into an active regression on the first structural edit of every session.
# The `length == 2` clause matters: `all` over an empty array is vacuously true,
# so a dropped registration would otherwise pass.
echo ""
echo "hooks.json registration:"
if jq -e '[.hooks.PostToolUse[].hooks[]
          | select(.command | test("blueprint-structural-cue\\.sh"))]
         | length == 2 and all(.continueOnBlock == true)' "$BSC_HOOKS_JSON" >/dev/null 2>&1; then
    bsc_pass "both Write and Edit registrations carry continueOnBlock:true"
else
    bsc_fail "hooks.json: expected 2 blueprint-structural-cue registrations, all with continueOnBlock:true"
fi

echo ""
echo "=== RESULTS ==="
echo "PASS=$BSC_PASS"
echo "FAIL=$BSC_FAIL"
if [ "$BSC_FAIL" -eq 0 ]; then
    echo "STATUS=OK"
    exit 0
else
    echo "STATUS=ERROR"
    exit 1
fi
