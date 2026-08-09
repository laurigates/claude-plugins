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
trap 'rm -rf "$BSC_TEST_CACHE_DIR"' EXIT

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
    BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR="$BSC_TEST_CACHE_DIR" bash "$BSC_SCRIPT" <<<"$1"
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

if printf '%s' "$BSC_OUT_CONTRACT" | jq -e '.reason | startswith("[blueprint]")' >/dev/null 2>&1; then
    bsc_pass "reason is prefixed [blueprint]"
else
    bsc_fail "reason missing [blueprint] prefix; got: ${BSC_OUT_CONTRACT:-<empty>}"
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
if printf '%s' "$BSC_OUT_SENTINEL" | grep -qF "SENTINEL_CONTENT_MARKER"; then
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
